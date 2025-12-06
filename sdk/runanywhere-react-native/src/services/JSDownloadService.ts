/**
 * JSDownloadService.ts
 *
 * JavaScript-based model download service using react-native-fs.
 * This provides download functionality without requiring native module implementation.
 *
 * Pattern matches Swift SDK's AlamofireDownloadService.swift
 */

import { Platform } from 'react-native';
import { EventBus } from '../Public/Events';
import { ModelRegistry } from './ModelRegistry';
import type { ModelInfo } from '../types';

// Dynamic import of RNFS to handle cases where it's not installed
let RNFS: typeof import('react-native-fs') | null = null;
try {
  RNFS = require('react-native-fs');
} catch {
  console.warn('[JSDownloadService] react-native-fs not available. Download functionality will be limited.');
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
}

/**
 * JavaScript-based Download Service
 *
 * Uses react-native-fs for HTTP downloads.
 * Follows the same pattern as Swift SDK's download service.
 */
class JSDownloadServiceImpl {
  private activeDownloads: Map<string, ActiveDownload> = new Map();

  /**
   * Check if download functionality is available
   */
  isAvailable(): boolean {
    return RNFS !== null;
  }

  /**
   * Get the models directory path
   */
  getModelsDirectory(): string {
    if (!RNFS) {
      throw new Error('react-native-fs not available');
    }
    // Use DocumentDirectory for iOS, ExternalDirectoryPath for Android
    const baseDir = Platform.OS === 'ios'
      ? RNFS.DocumentDirectoryPath
      : RNFS.ExternalDirectoryPath || RNFS.DocumentDirectoryPath;
    return `${baseDir}/runanywhere-models`;
  }

  /**
   * Ensure the models directory exists
   */
  async ensureModelsDirectory(): Promise<void> {
    if (!RNFS) {
      throw new Error('react-native-fs not available');
    }
    const dir = this.getModelsDirectory();
    const exists = await RNFS.exists(dir);
    if (!exists) {
      await RNFS.mkdir(dir);
      console.log('[JSDownloadService] Created models directory:', dir);
    }
  }

  /**
   * Download a model by ID
   *
   * @param modelId - Model ID to download
   * @param onProgress - Optional progress callback
   * @returns Promise that resolves to local file path
   */
  async downloadModel(
    modelId: string,
    onProgress?: (progress: JSDownloadProgress) => void
  ): Promise<string> {
    if (!RNFS) {
      throw new Error('react-native-fs not available. Please install it to enable model downloads.');
    }

    // Check if already downloading
    if (this.activeDownloads.has(modelId)) {
      console.log('[JSDownloadService] Model already downloading:', modelId);
      return this.activeDownloads.get(modelId)!.promise;
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
    if (modelInfo.localPath) {
      const exists = await RNFS.exists(modelInfo.localPath);
      if (exists) {
        console.log('[JSDownloadService] Model already downloaded:', modelId);
        return modelInfo.localPath;
      }
    }

    // Ensure models directory exists
    await this.ensureModelsDirectory();

    // Determine file extension from URL or format
    const urlPath = modelInfo.downloadURL.split('?')[0] || '';
    const urlExtension = urlPath.split('.').pop() || '';
    const extension = urlExtension || (modelInfo.format === 'gguf' ? 'gguf' : 'bin');

    // Create destination path
    const destPath = `${this.getModelsDirectory()}/${modelId}.${extension}`;

    console.log('[JSDownloadService] Starting download:', {
      modelId,
      url: modelInfo.downloadURL,
      destPath,
    });

    // Publish download started event
    EventBus.publish('Model', {
      type: 'downloadStarted',
      modelId,
    });

    // Create download promise
    const downloadPromise = new Promise<string>((resolve, reject) => {
      const downloadTask = RNFS!.downloadFile({
        fromUrl: modelInfo.downloadURL!,
        toFile: destPath,
        background: true, // Enable background downloads on iOS
        discretionary: false, // Allow downloads on cellular
        cacheable: false,
        progressDivider: 1, // Report progress frequently
        begin: (res) => {
          console.log('[JSDownloadService] Download started, content-length:', res.contentLength);
          // Store the job ID for cancellation
          const download = this.activeDownloads.get(modelId);
          if (download) {
            download.jobId = res.jobId;
          }
        },
        progress: (res) => {
          const progress = res.contentLength > 0
            ? res.bytesWritten / res.contentLength
            : 0;

          // Call progress callback
          if (onProgress) {
            onProgress({
              modelId,
              bytesDownloaded: res.bytesWritten,
              totalBytes: res.contentLength,
              progress,
            });
          }

          // Publish progress event
          EventBus.publish('Model', {
            type: 'downloadProgress',
            modelId,
            bytesDownloaded: res.bytesWritten,
            totalBytes: res.contentLength,
            progress,
          });
        },
      });

      // Store job ID immediately (may be updated in begin callback)
      const activeDownload: ActiveDownload = {
        jobId: downloadTask.jobId,
        modelId,
        promise: downloadPromise,
        cancel: () => {
          RNFS!.stopDownload(downloadTask.jobId);
        },
      };
      this.activeDownloads.set(modelId, activeDownload);

      // Handle download completion
      downloadTask.promise
        .then(async (res) => {
          if (res.statusCode === 200) {
            console.log('[JSDownloadService] Download completed:', modelId);

            // Update model info with local path
            const updatedModel: ModelInfo = {
              ...modelInfo,
              localPath: destPath,
              isDownloaded: true,
            };

            // Update in registry
            try {
              await ModelRegistry.registerModel(updatedModel);
            } catch (e) {
              console.warn('[JSDownloadService] Failed to update model in registry:', e);
            }

            // Publish completion event
            EventBus.publish('Model', {
              type: 'downloadCompleted',
              modelId,
              localPath: destPath,
            });

            this.activeDownloads.delete(modelId);
            resolve(destPath);
          } else {
            const error = new Error(`Download failed with status: ${res.statusCode}`);
            console.error('[JSDownloadService] Download failed:', error);

            // Clean up partial file
            try {
              const exists = await RNFS!.exists(destPath);
              if (exists) {
                await RNFS!.unlink(destPath);
              }
            } catch (e) {
              console.warn('[JSDownloadService] Failed to clean up partial download:', e);
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
        .catch(async (error) => {
          console.error('[JSDownloadService] Download error:', error);

          // Clean up partial file
          try {
            const exists = await RNFS!.exists(destPath);
            if (exists) {
              await RNFS!.unlink(destPath);
            }
          } catch (e) {
            console.warn('[JSDownloadService] Failed to clean up partial download:', e);
          }

          EventBus.publish('Model', {
            type: 'downloadFailed',
            modelId,
            error: error.message,
          });

          this.activeDownloads.delete(modelId);
          reject(error);
        });
    });

    return downloadPromise;
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
    if (!RNFS) {
      return false;
    }

    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo?.localPath) {
      return false;
    }

    try {
      const exists = await RNFS.exists(modelInfo.localPath);
      if (exists) {
        await RNFS.unlink(modelInfo.localPath);
        console.log('[JSDownloadService] Deleted model:', modelId);

        // Update model info
        const updatedModel: ModelInfo = {
          ...modelInfo,
          localPath: undefined,
          isDownloaded: false,
        };
        await ModelRegistry.registerModel(updatedModel);

        return true;
      }
    } catch (error) {
      console.error('[JSDownloadService] Error deleting model:', error);
    }

    return false;
  }

  /**
   * Check if a model file exists locally
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    if (!RNFS) {
      return false;
    }

    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo?.localPath) {
      return false;
    }

    return RNFS.exists(modelInfo.localPath);
  }

  /**
   * Get the local path for a downloaded model
   */
  async getModelPath(modelId: string): Promise<string | null> {
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo?.localPath) {
      return null;
    }

    if (!RNFS) {
      return modelInfo.localPath;
    }

    const exists = await RNFS.exists(modelInfo.localPath);
    return exists ? modelInfo.localPath : null;
  }

  /**
   * Get storage usage information
   */
  async getStorageUsage(): Promise<{ used: number; free: number }> {
    if (!RNFS) {
      return { used: 0, free: 0 };
    }

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
}

/**
 * Singleton instance
 */
export const JSDownloadService = new JSDownloadServiceImpl();

export default JSDownloadService;

