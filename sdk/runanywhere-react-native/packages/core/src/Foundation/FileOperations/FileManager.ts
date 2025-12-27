/**
 * FileManager.ts
 *
 * Simplified file manager using external React Native packages.
 * Primary: react-native-fs, react-native-blob-util
 * Fallback: Nitrogen native bridge (HybridRunAnywhereFileSystem)
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/FileSystem/SimplifiedFileManager.swift
 */

import { Platform } from 'react-native';
import { SDKLogger } from '../Logging/Logger/SDKLogger';
import type { LLMFramework } from '../../Core/Models/Framework/LLMFramework';

// Dynamic imports for optional peer dependencies

let RNFS: typeof import('react-native-fs') | null = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let RNBlobUtil: any = null;

// Try to load react-native-fs
try {
  RNFS = require('react-native-fs');
} catch {
  // Package not installed
}

// Try to load react-native-blob-util (preferred for downloads)
try {
  RNBlobUtil = require('react-native-blob-util').default;
} catch {
  // Package not installed
}

const _logger = new SDKLogger('FileManager');

/**
 * Get the base documents directory path
 */
function getDocumentsPath(): string {
  if (RNBlobUtil) {
    return RNBlobUtil.fs.dirs.DocumentDir;
  }
  if (RNFS) {
    return RNFS.DocumentDirectoryPath;
  }
  throw new Error(
    'No file system package available. Install react-native-fs or react-native-blob-util.'
  );
}

/**
 * Simplified file manager using external React Native packages.
 *
 * Uses react-native-fs for file operations and react-native-blob-util for downloads.
 * These are well-maintained community packages that provide native file system access.
 */
export class FileManager {
  private logger: SDKLogger;
  private _basePath: string | null = null;
  private _modelsPath: string | null = null;

  constructor() {
    this.logger = new SDKLogger('FileManager');
  }

  /**
   * Check if file system packages are available
   */
  public isAvailable(): boolean {
    return RNFS !== null || RNBlobUtil !== null;
  }

  /**
   * Get the base data directory path
   */
  public async getBasePath(): Promise<string> {
    if (!this._basePath) {
      const docsPath = getDocumentsPath();
      this._basePath = `${docsPath}/runanywhere-data`;
      await this.ensureDirectoryExists(this._basePath);
    }
    return this._basePath;
  }

  /**
   * Get the models directory path
   */
  public async getModelsPath(): Promise<string> {
    if (!this._modelsPath) {
      const docsPath = getDocumentsPath();
      this._modelsPath = `${docsPath}/runanywhere-models`;
      await this.ensureDirectoryExists(this._modelsPath);
    }
    return this._modelsPath;
  }

  /**
   * Ensure a directory exists, creating it if necessary
   */
  private async ensureDirectoryExists(path: string): Promise<void> {
    if (RNBlobUtil) {
      const exists = await RNBlobUtil.fs.isDir(path);
      if (!exists) {
        await RNBlobUtil.fs.mkdir(path);
      }
    } else if (RNFS) {
      const exists = await RNFS.exists(path);
      if (!exists) {
        await RNFS.mkdir(path);
      }
    }
  }

  /**
   * Find model file by searching all possible locations
   */
  public async findModelFile(
    modelId: string,
    expectedPath?: string | null
  ): Promise<string | null> {
    try {
      // If expected path exists and is valid, check it first
      if (expectedPath) {
        const exists = await this.fileExists(expectedPath);
        if (exists) {
          return expectedPath;
        }
      }

      // Check if model exists in models directory
      const modelPath = await this.getModelPath(modelId);
      const exists = await this.fileExists(modelPath);
      if (exists) {
        return modelPath;
      }

      return null;
    } catch (error) {
      this.logger.warning('Error finding model file', { modelId, error });
      return null;
    }
  }

  /**
   * Get model directory
   */
  public async getModelDirectory(
    modelId: string,
    framework?: LLMFramework
  ): Promise<string> {
    const modelsPath = await this.getModelsPath();
    if (framework) {
      return `${modelsPath}/${framework}/${modelId}`;
    }
    return `${modelsPath}/${modelId}`;
  }

  /**
   * Get the full path for a model
   */
  public async getModelPath(modelId: string): Promise<string> {
    const modelsPath = await this.getModelsPath();
    return `${modelsPath}/${modelId}`;
  }

  /**
   * Check if a model exists locally
   */
  public async modelExists(modelId: string): Promise<boolean> {
    try {
      const modelPath = await this.getModelPath(modelId);
      return await this.fileExists(modelPath);
    } catch {
      return false;
    }
  }

  /**
   * Check if file exists at path
   */
  public async fileExists(path: string): Promise<boolean> {
    try {
      if (RNBlobUtil) {
        return await RNBlobUtil.fs.exists(path);
      }
      if (RNFS) {
        return await RNFS.exists(path);
      }
      return false;
    } catch {
      return false;
    }
  }

  /**
   * Get file size in bytes
   */
  public async getFileSize(path: string): Promise<number | null> {
    try {
      if (RNFS) {
        const stat = await RNFS.stat(path);
        return stat.size;
      }
      if (RNBlobUtil) {
        const stat = await RNBlobUtil.fs.stat(path);
        return stat.size;
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Download a model from URL with progress tracking
   *
   * @param modelId - Unique model identifier
   * @param url - Download URL
   * @param onProgress - Optional callback for progress updates (0.0 to 1.0)
   */
  public async downloadModel(
    modelId: string,
    url: string,
    onProgress?: (progress: number) => void
  ): Promise<string> {
    const modelPath = await this.getModelPath(modelId);

    // Check if already downloaded
    if (await this.fileExists(modelPath)) {
      this.logger.debug('Model already exists', { modelId, path: modelPath });
      onProgress?.(1.0);
      return modelPath;
    }

    this.logger.debug('Starting model download', { modelId, url });

    // Use react-native-blob-util for downloads (better progress support)
    if (RNBlobUtil) {
      return await this.downloadWithBlobUtil(
        modelId,
        url,
        modelPath,
        onProgress
      );
    }

    // Fallback to react-native-fs
    if (RNFS) {
      return await this.downloadWithRNFS(modelId, url, modelPath, onProgress);
    }

    throw new Error(
      'No download package available. Install react-native-blob-util or react-native-fs.'
    );
  }

  /**
   * Download using react-native-blob-util (preferred)
   */
  private async downloadWithBlobUtil(
    modelId: string,
    url: string,
    destPath: string,
    onProgress?: (progress: number) => void
  ): Promise<string> {
    let lastProgress = 0;

    return new Promise<string>((resolve, reject) => {
      const task = RNBlobUtil.config({
        path: destPath,
        fileCache: false,
      })
        .fetch('GET', url)
        .progress({ interval: 100 }, (received: number, total: number) => {
          if (total > 0) {
            const progress = received / total;
            if (progress - lastProgress >= 0.01) {
              lastProgress = progress;
              onProgress?.(progress);
            }
          }
        });

      task
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        .then((res: any) => {
          const status = res.info().status;
          if (status === 200) {
            this.logger.debug('Download completed', {
              modelId,
              path: destPath,
            });
            onProgress?.(1.0);
            resolve(destPath);
          } else {
            reject(new Error(`Download failed with status: ${status}`));
          }
        })
        .catch((error: Error) => {
          this.logger.error('Download failed', {
            modelId,
            error: error.message,
          });
          reject(error);
        });
    });
  }

  /**
   * Download using react-native-fs (fallback)
   */
  private async downloadWithRNFS(
    modelId: string,
    url: string,
    destPath: string,
    onProgress?: (progress: number) => void
  ): Promise<string> {
    if (!RNFS) {
      throw new Error('react-native-fs not available');
    }

    const rnfs = RNFS;

    return new Promise<string>((resolve, reject) => {
      const downloadResult = rnfs.downloadFile({
        fromUrl: url,
        toFile: destPath,
        progress: (res) => {
          if (res.contentLength > 0) {
            const progress = res.bytesWritten / res.contentLength;
            onProgress?.(progress);
          }
        },
        progressDivider: 10, // Report progress every 10% instead of progressInterval
      });

      downloadResult.promise
        .then((result) => {
          if (result.statusCode === 200) {
            this.logger.debug('Download completed', {
              modelId,
              path: destPath,
            });
            onProgress?.(1.0);
            resolve(destPath);
          } else {
            reject(
              new Error(`Download failed with status: ${result.statusCode}`)
            );
          }
        })
        .catch((error: Error) => {
          this.logger.error('Download failed', {
            modelId,
            error: error.message,
          });
          reject(error);
        });
    });
  }

  /**
   * Delete a downloaded model
   */
  public async deleteModel(modelId: string): Promise<void> {
    const modelPath = await this.getModelPath(modelId);
    await this.deleteFile(modelPath);
    this.logger.debug('Model deleted', { modelId });
  }

  /**
   * Read a text file
   */
  public async readFile(path: string): Promise<string> {
    if (RNFS) {
      return await RNFS.readFile(path, 'utf8');
    }
    if (RNBlobUtil) {
      return await RNBlobUtil.fs.readFile(path, 'utf8');
    }
    throw new Error('No file system package available');
  }

  /**
   * Write a text file
   */
  public async writeFile(path: string, content: string): Promise<void> {
    if (RNFS) {
      await RNFS.writeFile(path, content, 'utf8');
      return;
    }
    if (RNBlobUtil) {
      await RNBlobUtil.fs.writeFile(path, content, 'utf8');
      return;
    }
    throw new Error('No file system package available');
  }

  /**
   * Delete a file or directory
   */
  public async deleteFile(path: string): Promise<void> {
    const exists = await this.fileExists(path);
    if (!exists) return;

    if (RNFS) {
      await RNFS.unlink(path);
      return;
    }
    if (RNBlobUtil) {
      await RNBlobUtil.fs.unlink(path);
      return;
    }
  }

  /**
   * Get available disk space in bytes
   */
  public async getAvailableDiskSpace(): Promise<number> {
    try {
      if (RNFS) {
        const info = await RNFS.getFSInfo();
        return info.freeSpace;
      }
      if (RNBlobUtil) {
        const info = await RNBlobUtil.fs.df();
        return Platform.OS === 'ios' ? info.free : info.internal_free;
      }
      return 0;
    } catch {
      return 0;
    }
  }

  /**
   * Get total disk space in bytes
   */
  public async getTotalDiskSpace(): Promise<number> {
    try {
      if (RNFS) {
        const info = await RNFS.getFSInfo();
        return info.totalSpace;
      }
      if (RNBlobUtil) {
        const info = await RNBlobUtil.fs.df();
        return Platform.OS === 'ios' ? info.total : info.internal_total;
      }
      return 0;
    } catch {
      return 0;
    }
  }

  /**
   * Copy a file
   */
  public async copyFile(source: string, destination: string): Promise<void> {
    if (RNFS) {
      await RNFS.copyFile(source, destination);
      return;
    }
    if (RNBlobUtil) {
      await RNBlobUtil.fs.cp(source, destination);
      return;
    }
    throw new Error('No file system package available');
  }

  /**
   * Move a file
   */
  public async moveFile(source: string, destination: string): Promise<void> {
    if (RNFS) {
      await RNFS.moveFile(source, destination);
      return;
    }
    if (RNBlobUtil) {
      await RNBlobUtil.fs.mv(source, destination);
      return;
    }
    throw new Error('No file system package available');
  }

  /**
   * List files in a directory
   */
  public async listDir(path: string): Promise<string[]> {
    if (RNFS) {
      const items = await RNFS.readDir(path);
      return items.map((item) => item.path);
    }
    if (RNBlobUtil) {
      return await RNBlobUtil.fs.ls(path);
    }
    return [];
  }

  /**
   * Check if path is a directory
   */
  public async isDirectory(path: string): Promise<boolean> {
    try {
      if (RNFS) {
        const stat = await RNFS.stat(path);
        return stat.isDirectory();
      }
      if (RNBlobUtil) {
        return await RNBlobUtil.fs.isDir(path);
      }
      return false;
    } catch {
      return false;
    }
  }
}
