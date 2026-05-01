/**
 * Download Service for RunAnywhere React Native SDK
 *
 * Thin wrapper over native download service.
 * All download logic lives in native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift
 */

import {
  DownloadProgress,
  DownloadState,
} from '@runanywhere/proto-ts/download_service';
import { requireNativeModule, isNativeModuleAvailable } from '../native';
import { EventBus } from '../Public/Events';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('DownloadService');

/**
 * Re-export the canonical proto types so consumers have a single import
 * surface. `DownloadProgress` is the 10-field
 * `runanywhere.v1.DownloadProgress` message; `DownloadState` is the matching
 * enum. Field names are proto-ts camelCase (`bytesDownloaded`,
 * `stageProgress`, etc.).
 */
export { DownloadProgress, DownloadState } from '@runanywhere/proto-ts/download_service';
export { DownloadStage } from '@runanywhere/proto-ts/download_service';

/**
 * Extended native module type for download service methods
 * These methods are optional and may not be implemented in all backends
 */
interface DownloadNativeModule {
  startModelDownload?: (modelId: string) => Promise<string>;
  pauseDownload?: (taskId: string) => Promise<void>;
  resumeDownload?: (taskId: string) => Promise<void>;
  pauseAllDownloads?: () => Promise<void>;
  resumeAllDownloads?: () => Promise<void>;
  cancelAllDownloads?: () => Promise<void>;
  configureDownloadService?: (configJson: string) => Promise<void>;
  isDownloadServiceHealthy?: () => Promise<boolean>;
  cancelDownload: (taskId: string) => Promise<boolean>;
  getDownloadProgress: (modelId: string) => Promise<string>;
}

/**
 * Download task handle
 */
export interface DownloadTask {
  id: string;
  modelId: string;
  state: DownloadState;
  promise: Promise<string>;
  cancel: () => Promise<void>;
}

/**
 * Download configuration
 */
export interface DownloadConfiguration {
  timeout?: number;
  maxConcurrentDownloads?: number;
  retryCount?: number;
  allowCellular?: boolean;
}

/**
 * Progress callback type — receives the full 10-field proto
 * `runanywhere.v1.DownloadProgress` message.
 */
export type ProgressCallback = (progress: DownloadProgress) => void;

/**
 * Download Service - Thin wrapper over native
 */
class DownloadServiceImpl {
  private activeTasks = new Map<string, DownloadTask>();

  /**
   * Download a model by ID
   */
  async downloadModelById(
    modelId: string,
    onProgress?: ProgressCallback
  ): Promise<string> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (!native.startModelDownload) {
      throw new Error('startModelDownload not available');
    }
    const taskId = await native.startModelDownload(modelId);

    logger.debug(`Started download: ${modelId} (task: ${taskId})`);

    // Subscribe to progress events if callback provided
    let unsubscribe: (() => void) | null = null;
    if (onProgress) {
      unsubscribe = EventBus.onModel((event) => {
        if (
          event.type === 'downloadProgress' &&
          'modelId' in event &&
          event.modelId === modelId
        ) {
          const payload = event as Record<string, unknown>;
          const progress = DownloadProgress.fromPartial({
            modelId,
            bytesDownloaded:
              typeof payload.bytesDownloaded === 'number' ? payload.bytesDownloaded : 0,
            totalBytes: typeof payload.totalBytes === 'number' ? payload.totalBytes : 0,
            stageProgress:
              typeof payload.progress === 'number' ? payload.progress : 0,
            state: DownloadState.DOWNLOAD_STATE_DOWNLOADING,
          });
          onProgress(progress);
        }
      });
    }

    // Wait for completion
    return new Promise<string>((resolve, reject) => {
      const eventUnsubscribe = EventBus.onModel((event) => {
        if (!('modelId' in event) || event.modelId !== modelId) return;

        if (event.type === 'downloadCompleted') {
          eventUnsubscribe();
          unsubscribe?.();
          resolve((event as { localPath?: string }).localPath ?? '');
        }
        if (event.type === 'downloadFailed') {
          eventUnsubscribe();
          unsubscribe?.();
          reject(new Error((event as { error?: string }).error ?? 'Download failed'));
        }
      });
    });
  }

  /**
   * Cancel a download
   */
  async cancelDownload(taskId: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    await native.cancelDownload(taskId);
    this.activeTasks.delete(taskId);
  }

  /**
   * Pause a download
   */
  async pauseDownload(taskId: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (native.pauseDownload) {
      await native.pauseDownload(taskId);
    }
  }

  /**
   * Resume a download
   */
  async resumeDownload(taskId: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (native.resumeDownload) {
      await native.resumeDownload(taskId);
    }
  }

  /**
   * Pause all downloads
   */
  async pauseAll(): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (native.pauseAllDownloads) {
      await native.pauseAllDownloads();
    }
  }

  /**
   * Resume all downloads
   */
  async resumeAll(): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (native.resumeAllDownloads) {
      await native.resumeAllDownloads();
    }
  }

  /**
   * Cancel all downloads
   */
  async cancelAll(): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (native.cancelAllDownloads) {
      await native.cancelAllDownloads();
    }
    this.activeTasks.clear();
  }

  /**
   * Get download progress
   */
  async getDownloadProgress(modelId: string): Promise<number | null> {
    if (!isNativeModuleAvailable()) return null;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    const json = await native.getDownloadProgress(modelId);
    try {
      const data = JSON.parse(json);
      return typeof data === 'number' ? data : data?.progress ?? null;
    } catch {
      return null;
    }
  }

  /**
   * Configure download service
   */
  async configure(config: DownloadConfiguration): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (native.configureDownloadService) {
      await native.configureDownloadService(JSON.stringify(config));
    }
  }

  /**
   * Check if service is healthy
   */
  async isHealthy(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;

    const native = requireNativeModule() as unknown as DownloadNativeModule;
    if (!native.isDownloadServiceHealthy) {
      return true; // Assume healthy if method not available
    }
    return native.isDownloadServiceHealthy();
  }

  /**
   * Check if downloading
   */
  isDownloading(modelId: string): boolean {
    for (const task of this.activeTasks.values()) {
      if (
        task.modelId === modelId &&
        task.state === DownloadState.DOWNLOAD_STATE_DOWNLOADING
      ) {
        return true;
      }
    }
    return false;
  }

  /**
   * Reset (for testing)
   */
  reset(): void {
    this.activeTasks.clear();
  }
}

/**
 * Singleton instance
 */
export const DownloadService = new DownloadServiceImpl();
