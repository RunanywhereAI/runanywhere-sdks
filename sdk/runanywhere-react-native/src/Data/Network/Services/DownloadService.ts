/**
 * DownloadService.ts
 *
 * Download service using external React Native packages.
 * Uses react-native-blob-util or react-native-fs for downloads.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Downloading/DownloadManager.swift
 */

import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';
import type { DownloadProgress } from '../../Models/Downloading/DownloadProgress';
import { DownloadState } from '../../Models/Downloading/DownloadState';
import type { DownloadTask } from '../../Models/Downloading/DownloadTask';
import { FileManager } from '../../../Foundation/FileOperations/FileManager';
import { ArchiveManager } from '../../../Foundation/FileOperations/ArchiveManager';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('DownloadService');

/**
 * Protocol for download management operations
 */
export interface DownloadService {
  /**
   * Download a model
   */
  downloadModel(model: ModelInfo): Promise<DownloadTask>;

  /**
   * Cancel a download
   */
  cancelDownload(taskId: string): void;

  /**
   * Get all active downloads
   */
  activeDownloads(): DownloadTask[];
}

/**
 * Download service implementation using external packages.
 *
 * Uses react-native-blob-util (preferred) or react-native-fs for downloads.
 * Provides progress tracking, automatic archive extraction, and cancellation.
 */
export class DownloadServiceImpl implements DownloadService {
  private readonly _activeDownloads: Map<string, DownloadTask> = new Map();
  private readonly _cancelTokens: Map<string, { cancelled: boolean }> =
    new Map();
  private readonly fileManager: FileManager;
  private readonly archiveManager: ArchiveManager;

  constructor() {
    this.fileManager = new FileManager();
    this.archiveManager = ArchiveManager.shared;
  }

  /**
   * Check if download service is available
   */
  public isAvailable(): boolean {
    return this.fileManager.isAvailable();
  }

  public async downloadModel(model: ModelInfo): Promise<DownloadTask> {
    const taskId = `download-${model.id}-${Date.now()}`;

    // Check if already downloading
    for (const [, task] of this._activeDownloads) {
      if (task.modelId === model.id) {
        logger.debug('Model already downloading', { modelId: model.id });
        return task;
      }
    }

    // Create cancel token
    const cancelToken = { cancelled: false };
    this._cancelTokens.set(taskId, cancelToken);

    // Create progress generator
    const progressGenerator = this.createProgressGenerator(
      model,
      taskId,
      cancelToken
    );

    // Create result promise
    const resultPromise = this.downloadFile(model, taskId, cancelToken);

    const task: DownloadTask = {
      id: taskId,
      modelId: model.id,
      progress: progressGenerator,
      result: resultPromise,
    };

    this._activeDownloads.set(taskId, task);

    // Clean up when done
    resultPromise.finally(() => {
      this._activeDownloads.delete(taskId);
      this._cancelTokens.delete(taskId);
    });

    return task;
  }

  public cancelDownload(taskId: string): void {
    const cancelToken = this._cancelTokens.get(taskId);
    if (cancelToken) {
      cancelToken.cancelled = true;
      logger.debug('Download cancelled', { taskId });
    }
    this._activeDownloads.delete(taskId);
    this._cancelTokens.delete(taskId);
  }

  public activeDownloads(): DownloadTask[] {
    return Array.from(this._activeDownloads.values());
  }

  /**
   * Create progress generator that yields download progress
   */
  private async *createProgressGenerator(
    model: ModelInfo,
    taskId: string,
    cancelToken: { cancelled: boolean }
  ): AsyncGenerator<DownloadProgress, void, unknown> {
    const lastBytesDownloaded = 0;

    // Initial progress
    yield {
      bytesDownloaded: 0,
      totalBytes: model.downloadSize ?? 0,
      state: DownloadState.Downloading,
      speed: null,
      estimatedTimeRemaining: null,
    };

    // Poll for progress while download is active
    while (this._activeDownloads.has(taskId) && !cancelToken.cancelled) {
      await new Promise((resolve) => setTimeout(resolve, 250));

      if (cancelToken.cancelled) {
        yield {
          bytesDownloaded: lastBytesDownloaded,
          totalBytes: model.downloadSize ?? 0,
          state: DownloadState.Cancelled,
          speed: null,
          estimatedTimeRemaining: null,
        };
        return;
      }
    }
  }

  /**
   * Download file using FileManager (which uses external packages)
   */
  private async downloadFile(
    model: ModelInfo,
    _taskId: string,
    cancelToken: { cancelled: boolean }
  ): Promise<string> {
    if (!model.downloadURL) {
      throw new Error('Model has no download URL');
    }

    if (!this.fileManager.isAvailable()) {
      throw new Error(
        'No download package available. Install react-native-blob-util or react-native-fs.'
      );
    }

    logger.debug('Starting download', {
      modelId: model.id,
      url: model.downloadURL,
    });

    const startTime = Date.now();

    try {
      // Determine file name from URL
      const urlPath = model.downloadURL.split('?')[0] || '';
      const fileName = urlPath.split('/').pop() || model.id;

      // Download the file
      const downloadPath = await this.fileManager.downloadModel(
        fileName,
        model.downloadURL,
        (progress: number) => {
          if (cancelToken.cancelled) {
            return;
          }
          logger.debug('Download progress', {
            modelId: model.id,
            progress: Math.round(progress * 100),
          });
        }
      );

      if (cancelToken.cancelled) {
        // Clean up downloaded file
        try {
          await this.fileManager.deleteFile(downloadPath);
        } catch {
          // Ignore cleanup errors
        }
        throw new Error('Download cancelled');
      }

      // Check if file is an archive that needs extraction
      let finalPath = downloadPath;
      if (this.archiveManager.isArchive(downloadPath)) {
        logger.debug('Extracting archive', { path: downloadPath });

        const modelsPath = await this.fileManager.getModelsPath();
        const extractDir = `${modelsPath}/${model.id}`;

        const result = await this.archiveManager.extract(
          downloadPath,
          extractDir
        );

        if (result.success && result.extractedPath) {
          finalPath = result.extractedPath;

          // Delete the archive file after extraction
          try {
            await this.fileManager.deleteFile(downloadPath);
          } catch {
            // Ignore cleanup errors
          }

          logger.debug('Archive extracted', { extractedPath: finalPath });
        } else {
          logger.warning('Archive extraction failed, using archive path', {
            error: result.error,
          });
        }
      }

      const duration = (Date.now() - startTime) / 1000;
      logger.debug('Download completed', {
        modelId: model.id,
        path: finalPath,
        duration: `${duration.toFixed(1)}s`,
      });

      return finalPath;
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error('Download failed', {
        modelId: model.id,
        error: errorMessage,
      });

      throw error;
    }
  }
}
