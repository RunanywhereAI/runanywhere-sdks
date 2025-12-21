/**
 * JSDownloadService.ts
 *
 * JavaScript-based model download service using rn-fetch-blob.
 * This provides reliable download functionality for large files.
 *
 * Pattern matches Swift SDK's AlamofireDownloadService.swift
 */

import { EventBus } from '../Public/Events';
import { ModelRegistry } from './ModelRegistry';
import type { ModelInfo } from '../types';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('JSDownloadService');

// Dynamic import of rn-fetch-blob
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let RNFetchBlob: any = null;
try {
  RNFetchBlob = require('rn-fetch-blob').default;
} catch {
  logger.warning('rn-fetch-blob not available.');
}

// Fallback to RNFS for file operations
let RNFS: typeof import('react-native-fs') | null = null;
try {
  RNFS = require('react-native-fs');
} catch {
  logger.warning('react-native-fs not available.');
}

/**
 * Download progress information
 */
export interface JSDownloadProgress {
  modelId: string;
  bytesDownloaded: number;
  totalBytes: number;
  progress: number; // 0-1
}

/**
 * Active download tracking
 */
interface ActiveDownload {
  jobId: number;
  modelId: string;
  promise: Promise<string>;
  cancel: () => void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- RNFetchBlob task type from external package
  task?: any;
}

/**
 * JavaScript-based Download Service
 *
 * Uses rn-fetch-blob for reliable file downloads.
 */
class JSDownloadServiceImpl {
  private activeDownloads: Map<string, ActiveDownload> = new Map();
  private jobIdCounter = 0;

  /**
   * Check if download functionality is available
   */
  isAvailable(): boolean {
    return RNFetchBlob !== null || RNFS !== null;
  }

  /**
   * Get the models directory path
   */
  getModelsDirectory(): string {
    if (RNFetchBlob) {
      const dirs = RNFetchBlob.fs.dirs;
      return `${dirs.DocumentDir}/runanywhere-models`;
    }
    if (RNFS) {
      return `${RNFS.DocumentDirectoryPath}/runanywhere-models`;
    }
    throw new Error('No file system library available');
  }

  /**
   * Ensure the models directory exists
   */
  async ensureModelsDirectory(): Promise<void> {
    const dir = this.getModelsDirectory();

    if (RNFetchBlob) {
      const exists = await RNFetchBlob.fs.isDir(dir);
      if (!exists) {
        await RNFetchBlob.fs.mkdir(dir);
        logger.debug(`Created models directory: ${dir}`);
      }
    } else if (RNFS) {
      const exists = await RNFS.exists(dir);
      if (!exists) {
        await RNFS.mkdir(dir);
        logger.debug(`Created models directory: ${dir}`);
      }
    }
  }

  /**
   * Download a model by ID using rn-fetch-blob
   *
   * @param modelId - Model ID to download
   * @param onProgress - Optional progress callback
   * @returns Promise that resolves to local file path
   */
  async downloadModel(
    modelId: string,
    onProgress?: (progress: JSDownloadProgress) => void
  ): Promise<string> {
    if (!RNFetchBlob && !RNFS) {
      throw new Error(
        'No download library available. Please install rn-fetch-blob or react-native-fs.'
      );
    }

    // Check if already downloading
    const existingDownload = this.activeDownloads.get(modelId);
    if (existingDownload) {
      logger.debug(`Model already downloading: ${modelId}`);
      return existingDownload.promise;
    }

    // Get model info from registry
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo) {
      throw new Error(`Model not found: ${modelId}`);
    }

    if (!modelInfo.downloadURL) {
      throw new Error(`Model has no download URL: ${modelId}`);
    }

    // Check if already downloaded
    const existingPath = await this.checkExistingDownload(modelInfo);
    if (existingPath) {
      return existingPath;
    }

    // Ensure models directory exists
    await this.ensureModelsDirectory();

    // Determine file extension from URL or format
    const urlPath = modelInfo.downloadURL.split('?')[0] || '';
    const urlExtension = urlPath.split('.').pop() || '';
    const extension =
      urlExtension || (modelInfo.format === 'gguf' ? 'gguf' : 'bin');

    // Create destination path
    const destPath = `${this.getModelsDirectory()}/${modelId}.${extension}`;

    logger.debug(' Starting download:', {
      modelId,
      url: modelInfo.downloadURL,
      destPath,
    });

    // Publish download started event
    EventBus.publish('Model', {
      type: 'downloadStarted',
      modelId,
    });

    const jobId = ++this.jobIdCounter;

    // Use rn-fetch-blob for download
    if (RNFetchBlob) {
      return this.downloadWithRNFetchBlob(
        modelId,
        modelInfo,
        destPath,
        jobId,
        onProgress
      );
    } else {
      // Fallback to fetch + RNFS (may have issues with large files)
      return this.downloadWithFetch(
        modelId,
        modelInfo,
        destPath,
        jobId,
        onProgress
      );
    }
  }

  /**
   * Download using rn-fetch-blob (preferred method)
   */
  private async downloadWithRNFetchBlob(
    modelId: string,
    modelInfo: ModelInfo,
    destPath: string,
    jobId: number,
    onProgress?: (progress: JSDownloadProgress) => void
  ): Promise<string> {
    const downloadURL = modelInfo.downloadURL;
    if (!downloadURL) {
      throw new Error(`Model has no download URL: ${modelId}`);
    }

    let lastProgressPercent = 0;

    const downloadPromise = new Promise<string>((resolve, reject) => {
      const task = RNFetchBlob.config({
        path: destPath,
        fileCache: false,
      })
        .fetch('GET', downloadURL, {
          // Add headers if needed
        })
        .progress({ interval: 100 }, (received: number, total: number) => {
          const progress = total > 0 ? received / total : 0;
          const progressPercent = Math.floor(progress * 100);

          if (progressPercent > lastProgressPercent) {
            lastProgressPercent = progressPercent;
            logger.debug(`Progress callback EMIT: ${progressPercent}%`);

            if (onProgress) {
              onProgress({
                modelId,
                bytesDownloaded: received,
                totalBytes: total,
                progress,
              });
            }

            EventBus.publish('Model', {
              type: 'downloadProgress',
              modelId,
              bytesDownloaded: received,
              totalBytes: total,
              progress,
            });
          }
        });

      // Store task for cancellation
      const activeDownload: ActiveDownload = {
        jobId,
        modelId,
        promise: downloadPromise,
        cancel: () => task.cancel(),
        task,
      };
      this.activeDownloads.set(modelId, activeDownload);

      task
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- RNFetchBlob response type
        .then(async (res: any) => {
          const status = res.info().status;

          if (status === 200) {
            logger.debug(`Download completed: ${destPath}`);

            // Update model info with local path
            const updatedModel: ModelInfo = {
              ...modelInfo,
              localPath: destPath,
              isDownloaded: true,
            };

            try {
              await ModelRegistry.registerModel(updatedModel);
            } catch (e) {
              logger.warning('Failed to update model in registry:', {
                error: e,
              });
            }

            EventBus.publish('Model', {
              type: 'downloadCompleted',
              modelId,
              localPath: destPath,
            });

            this.activeDownloads.delete(modelId);
            resolve(destPath);
          } else {
            const error = new Error(`Download failed with status: ${status}`);
            logger.error(`Download failed: ${error.message}`);

            // Clean up partial file
            try {
              await RNFetchBlob.fs.unlink(destPath);
            } catch {
              // Ignore
            }

            EventBus.publish('Model', {
              type: 'downloadFailed',
              modelId,
              error: error.message,
            });

            this.activeDownloads.delete(modelId);
            reject(error);
          }
        })
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        .catch(async (error: any) => {
          logger.error(`Download error: ${error?.message || String(error)}`);

          // Clean up partial file
          try {
            await RNFetchBlob.fs.unlink(destPath);
          } catch {
            // Ignore
          }

          EventBus.publish('Model', {
            type: 'downloadFailed',
            modelId,
            error: error.message || String(error),
          });

          this.activeDownloads.delete(modelId);
          reject(error);
        });
    });

    return downloadPromise;
  }

  /**
   * Fallback download using fetch + RNFS
   */
  private async downloadWithFetch(
    modelId: string,
    modelInfo: ModelInfo,
    destPath: string,
    jobId: number,
    onProgress?: (progress: JSDownloadProgress) => void
  ): Promise<string> {
    const downloadURL = modelInfo.downloadURL;
    if (!downloadURL) {
      throw new Error(`Model has no download URL: ${modelId}`);
    }
    if (!RNFS) {
      throw new Error('RNFS is not available');
    }
    // Capture RNFS in a const so TypeScript knows it's non-null in the async block
    const rnfs = RNFS;

    const abortController = new AbortController();

    const downloadPromise = (async (): Promise<string> => {
      try {
        logger.debug(`Fetching with fallback: ${downloadURL}`);

        const response = await fetch(downloadURL, {
          method: 'GET',
          signal: abortController.signal,
        });

        if (!response.ok) {
          throw new Error(`Download failed with status: ${response.status}`);
        }

        const contentLength = parseInt(
          response.headers.get('content-length') || '0',
          10
        );
        logger.debug(`Content-Length: ${contentLength}`);

        const blob = await response.blob();

        // Read blob as base64
        const base64Data = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => {
            const dataUrl = reader.result as string;
            const base64 = dataUrl.split(',')[1] || dataUrl;
            resolve(base64);
          };
          reader.onerror = () => reject(new Error('Failed to read blob'));
          reader.readAsDataURL(blob);
        });

        logger.debug(' Writing file...');
        await rnfs.writeFile(destPath, base64Data, 'base64');

        // Emit 100% progress
        if (onProgress) {
          onProgress({
            modelId,
            bytesDownloaded: contentLength || blob.size,
            totalBytes: contentLength || blob.size,
            progress: 1,
          });
        }

        // Update model info
        const updatedModel: ModelInfo = {
          ...modelInfo,
          localPath: destPath,
          isDownloaded: true,
        };

        try {
          await ModelRegistry.registerModel(updatedModel);
        } catch (e) {
          logger.warning('Failed to update model in registry:', { error: e });
        }

        EventBus.publish('Model', {
          type: 'downloadCompleted',
          modelId,
          localPath: destPath,
        });

        this.activeDownloads.delete(modelId);
        return destPath;
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } catch (error: any) {
        logger.error(`Download error: ${error?.message || String(error)}`);

        try {
          const exists = await rnfs.exists(destPath);
          if (exists) {
            await rnfs.unlink(destPath);
          }
        } catch {
          // Ignore
        }

        EventBus.publish('Model', {
          type: 'downloadFailed',
          modelId,
          error: error.message || String(error),
        });

        this.activeDownloads.delete(modelId);
        throw error;
      }
    })();

    const activeDownload: ActiveDownload = {
      jobId,
      modelId,
      promise: downloadPromise,
      cancel: () => abortController.abort(),
    };
    this.activeDownloads.set(modelId, activeDownload);

    return downloadPromise;
  }

  /**
   * Check if model is already downloaded
   */
  private async checkExistingDownload(
    modelInfo: ModelInfo
  ): Promise<string | null> {
    if (!modelInfo.localPath) {
      return null;
    }

    let exists = false;
    if (RNFetchBlob) {
      exists = await RNFetchBlob.fs.exists(modelInfo.localPath);
    } else if (RNFS) {
      exists = await RNFS.exists(modelInfo.localPath);
    }

    if (exists) {
      logger.debug(`Model already downloaded: ${modelInfo.id}`);
      return modelInfo.localPath;
    }

    return null;
  }

  /**
   * Cancel an active download
   */
  async cancelDownload(modelId: string): Promise<boolean> {
    const download = this.activeDownloads.get(modelId);
    if (download) {
      download.cancel();
      this.activeDownloads.delete(modelId);

      EventBus.publish('Model', {
        type: 'downloadCancelled',
        modelId,
      });

      return true;
    }
    return false;
  }

  /**
   * Check if a model is currently being downloaded
   */
  isDownloading(modelId: string): boolean {
    return this.activeDownloads.has(modelId);
  }

  /**
   * Delete a downloaded model
   */
  async deleteModel(modelId: string): Promise<boolean> {
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo?.localPath) {
      return false;
    }

    try {
      let exists = false;
      if (RNFetchBlob) {
        exists = await RNFetchBlob.fs.exists(modelInfo.localPath);
        if (exists) {
          await RNFetchBlob.fs.unlink(modelInfo.localPath);
        }
      } else if (RNFS) {
        exists = await RNFS.exists(modelInfo.localPath);
        if (exists) {
          await RNFS.unlink(modelInfo.localPath);
        }
      }

      if (exists) {
        logger.debug(`Deleted model: ${modelId}`);

        const updatedModel: ModelInfo = {
          ...modelInfo,
          localPath: undefined,
          isDownloaded: false,
        };
        await ModelRegistry.registerModel(updatedModel);

        return true;
      }
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error(`Error deleting model: ${errorMessage}`);
    }

    return false;
  }

  /**
   * Check if a model file exists locally
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo?.localPath) {
      return false;
    }

    if (RNFetchBlob) {
      return RNFetchBlob.fs.exists(modelInfo.localPath);
    } else if (RNFS) {
      return RNFS.exists(modelInfo.localPath);
    }

    return false;
  }

  /**
   * Get the local path for a downloaded model
   */
  async getModelPath(modelId: string): Promise<string | null> {
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo?.localPath) {
      return null;
    }

    let exists = false;
    if (RNFetchBlob) {
      exists = await RNFetchBlob.fs.exists(modelInfo.localPath);
    } else if (RNFS) {
      exists = await RNFS.exists(modelInfo.localPath);
    }

    return exists ? modelInfo.localPath : null;
  }

  /**
   * Get storage usage information
   */
  async getStorageUsage(): Promise<{ used: number; free: number }> {
    if (RNFS) {
      try {
        const fsInfo = await RNFS.getFSInfo();
        return {
          used: fsInfo.totalSpace - fsInfo.freeSpace,
          free: fsInfo.freeSpace,
        };
      } catch {
        return { used: 0, free: 0 };
      }
    }
    return { used: 0, free: 0 };
  }
}

/**
 * Singleton instance
 */
export const JSDownloadService = new JSDownloadServiceImpl();
