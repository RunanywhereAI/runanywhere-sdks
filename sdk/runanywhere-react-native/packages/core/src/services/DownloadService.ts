/**
 * Download Service for RunAnywhere React Native SDK
 *
 * Thin wrapper over native download service.
 * All download logic lives in native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift
 */

import {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadResumeRequest,
  DownloadResumeResult,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
  DownloadState,
} from '@runanywhere/proto-ts/download_service';
import { requireNativeModule, isNativeModuleAvailable } from '../native';
import { EventBus } from '../Public/Events';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { arrayBufferToBytes, bytesToArrayBuffer } from './ProtoBytes';

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

function encode<T>(
  message: T,
  codec: { encode(value: T): { finish(): Uint8Array } }
): ArrayBuffer {
  return bytesToArrayBuffer(codec.encode(message).finish());
}

function decode<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T },
  fallback: T
): T {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? fallback : codec.decode(bytes);
}

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
   * Plan a model download through native commons.
   */
  async planDownload(request: DownloadPlanRequest): Promise<DownloadPlanResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const buffer = await native.downloadPlanProto(
      encode(request, DownloadPlanRequest)
    );
    return decode(
      buffer,
      DownloadPlanResult,
      DownloadPlanResult.fromPartial({
        canStart: false,
        modelId: request.modelId,
        errorMessage: 'download planning returned an empty result',
      })
    );
  }

  /**
   * Start a planned native download.
   */
  async startDownload(request: DownloadStartRequest): Promise<DownloadStartResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const buffer = await native.downloadStartProto(
      encode(request, DownloadStartRequest)
    );
    const result = decode(
      buffer,
      DownloadStartResult,
      DownloadStartResult.fromPartial({
        accepted: false,
        modelId: request.modelId,
        errorMessage: 'download start returned an empty result',
      })
    );

    if (result.accepted && result.taskId) {
      this.activeTasks.set(result.taskId, {
        id: result.taskId,
        modelId: result.modelId,
        state:
          result.initialProgress?.state ??
          DownloadState.DOWNLOAD_STATE_PENDING,
        promise: Promise.resolve(result.initialProgress?.localPath ?? ''),
        cancel: async () => {
          await this.cancelNativeDownload({
            taskId: result.taskId,
            modelId: result.modelId,
            deletePartialBytes: false,
          });
        },
      });
    }

    return result;
  }

  /**
   * Cancel a native proto download.
   */
  async cancelNativeDownload(
    request: DownloadCancelRequest
  ): Promise<DownloadCancelResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const buffer = await native.downloadCancelProto(
      encode(request, DownloadCancelRequest)
    );
    const result = decode(
      buffer,
      DownloadCancelResult,
      DownloadCancelResult.fromPartial({
        success: false,
        taskId: request.taskId,
        modelId: request.modelId,
        errorMessage: 'download cancel returned an empty result',
      })
    );
    if (result.success) {
      this.activeTasks.delete(result.taskId);
    }
    return result;
  }

  /**
   * Resume a native proto download.
   */
  async resumeNativeDownload(
    request: DownloadResumeRequest
  ): Promise<DownloadResumeResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const buffer = await native.downloadResumeProto(
      encode(request, DownloadResumeRequest)
    );
    return decode(
      buffer,
      DownloadResumeResult,
      DownloadResumeResult.fromPartial({
        accepted: false,
        taskId: request.taskId,
        modelId: request.modelId,
        errorMessage: 'download resume returned an empty result',
      })
    );
  }

  /**
   * Poll native proto download progress.
   */
  async pollProgress(
    request: DownloadSubscribeRequest
  ): Promise<DownloadProgress | null> {
    if (!isNativeModuleAvailable()) {
      return null;
    }

    const native = requireNativeModule();
    const buffer = await native.downloadProgressPollProto(
      encode(request, DownloadSubscribeRequest)
    );
    const bytes = arrayBufferToBytes(buffer);
    if (bytes.byteLength === 0) {
      return null;
    }
    return DownloadProgress.decode(bytes);
  }

  /**
   * Subscribe to process-wide native DownloadProgress proto callbacks.
   */
  async subscribeProgress(
    callback: ProgressCallback
  ): Promise<() => Promise<void>> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const ok = await native.setDownloadProgressCallbackProto(
      (progressBytes: ArrayBuffer) => {
        try {
          callback(DownloadProgress.decode(arrayBufferToBytes(progressBytes)));
        } catch (error) {
          logger.warning('Failed to decode native DownloadProgress proto:', {
            error,
          });
        }
      }
    );
    if (!ok) {
      throw new Error('Native download progress subscription failed');
    }

    return async () => {
      await native.clearDownloadProgressCallbackProto();
    };
  }

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
    const task = this.activeTasks.get(taskId);
    if (task) {
      await this.cancelNativeDownload({
        taskId,
        modelId: task.modelId,
        deletePartialBytes: false,
      });
    } else {
      await native.cancelDownload(taskId);
    }
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
