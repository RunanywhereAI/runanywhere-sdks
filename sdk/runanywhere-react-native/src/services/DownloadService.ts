/**
 * Download Service for RunAnywhere React Native SDK
 *
 * Manages model downloads with progress tracking and resume support.
 * The actual download logic lives in the native SDK.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/AlamofireDownloadService.swift
 */

import { requireNativeModule } from '../native';
import { EventBus } from '../Public/Events';
import type { ModelInfo } from '../types';

/**
 * Download state
 */
export enum DownloadState {
  /** Download not started */
  Idle = 'idle',
  /** Download queued */
  Queued = 'queued',
  /** Download in progress */
  Downloading = 'downloading',
  /** Download paused */
  Paused = 'paused',
  /** Download completed */
  Completed = 'completed',
  /** Download failed */
  Failed = 'failed',
  /** Download cancelled */
  Cancelled = 'cancelled',
}

/**
 * Download progress information
 */
export interface DownloadProgress {
  /** Task ID */
  taskId: string;
  /** Model ID being downloaded */
  modelId: string;
  /** Bytes downloaded */
  bytesDownloaded: number;
  /** Total bytes to download */
  totalBytes: number;
  /** Progress as fraction (0-1) */
  progress: number;
  /** Current download state */
  state: DownloadState;
  /** Error message if failed */
  error?: string;
  /** Download speed in bytes per second */
  speedBps?: number;
  /** Estimated time remaining in seconds */
  estimatedTimeRemaining?: number;
}

/**
 * Download task handle
 */
export interface DownloadTask {
  /** Unique task ID */
  id: string;
  /** Model ID being downloaded */
  modelId: string;
  /** Current state */
  state: DownloadState;
  /** Promise that resolves when download completes */
  promise: Promise<string>;
  /** Cancel the download */
  cancel: () => Promise<void>;
  /** Pause the download */
  pause: () => Promise<void>;
  /** Resume the download */
  resume: () => Promise<void>;
}

/**
 * Download configuration
 */
export interface DownloadConfiguration {
  /** Request timeout in seconds */
  timeout?: number;
  /** Maximum concurrent downloads */
  maxConcurrentDownloads?: number;
  /** Number of retry attempts */
  retryCount?: number;
  /** Delay between retries in seconds */
  retryDelay?: number;
  /** Whether to allow cellular downloads */
  allowCellular?: boolean;
}

/**
 * Progress callback type
 */
export type ProgressCallback = (progress: DownloadProgress) => void;

/**
 * Download Service
 *
 * Manages model downloads with progress tracking, pause/resume, and cancellation.
 */
class DownloadServiceImpl {
  private activeTasks: Map<string, DownloadTask> = new Map();
  private progressCallbacks: Map<string, Set<ProgressCallback>> = new Map();
  private eventSubscription: (() => void) | null = null;

  constructor() {
    this.setupEventListeners();
  }

  /**
   * Set up event listeners for download progress
   */
  private setupEventListeners(): void {
    // Subscribe to model events for download progress
    this.eventSubscription = EventBus.onModel((event) => {
      if (event.type === 'downloadProgress') {
        const progress: DownloadProgress = {
          taskId: event.taskId ?? event.modelId,
          modelId: event.modelId,
          bytesDownloaded: event.bytesDownloaded ?? 0,
          totalBytes: event.totalBytes ?? 0,
          progress: event.progress ?? 0,
          state: this.mapDownloadState(event.downloadState),
          error: event.error,
        };

        this.notifyProgress(progress);
      }

      if (event.type === 'downloadCompleted') {
        const taskId = event.taskId ?? event.modelId;
        this.activeTasks.delete(taskId);
        this.progressCallbacks.delete(taskId);
      }

      if (event.type === 'downloadFailed') {
        const taskId = event.taskId ?? event.modelId;
        this.activeTasks.delete(taskId);
        this.progressCallbacks.delete(taskId);
      }
    });
  }

  /**
   * Map native download state to enum
   */
  private mapDownloadState(state?: string): DownloadState {
    switch (state) {
      case 'queued':
        return DownloadState.Queued;
      case 'downloading':
        return DownloadState.Downloading;
      case 'paused':
        return DownloadState.Paused;
      case 'completed':
        return DownloadState.Completed;
      case 'failed':
        return DownloadState.Failed;
      case 'cancelled':
        return DownloadState.Cancelled;
      default:
        return DownloadState.Idle;
    }
  }

  /**
   * Notify progress callbacks
   */
  private notifyProgress(progress: DownloadProgress): void {
    const callbacks = this.progressCallbacks.get(progress.taskId);
    if (callbacks) {
      for (const callback of callbacks) {
        callback(progress);
      }
    }
  }

  /**
   * Download a model
   *
   * @param model - Model to download
   * @param onProgress - Optional progress callback
   * @returns Download task handle
   */
  async downloadModel(
    model: ModelInfo,
    onProgress?: ProgressCallback
  ): Promise<DownloadTask> {
    const native = requireNativeModule();
    const taskId = await native.startModelDownload(model.id);

    // Create promise that resolves when download completes
    const promise = new Promise<string>((resolve, reject) => {
      const unsubscribe = EventBus.onModel((event) => {
        if (event.type === 'downloadCompleted' && event.modelId === model.id) {
          unsubscribe();
          resolve(event.localPath ?? '');
        }
        if (event.type === 'downloadFailed' && event.modelId === model.id) {
          unsubscribe();
          reject(new Error(event.error ?? 'Download failed'));
        }
      });
    });

    const task: DownloadTask = {
      id: taskId,
      modelId: model.id,
      state: DownloadState.Downloading,
      promise,
      cancel: async () => {
        await this.cancelDownload(taskId);
      },
      pause: async () => {
        await this.pauseDownload(taskId);
      },
      resume: async () => {
        await this.resumeDownload(taskId);
      },
    };

    this.activeTasks.set(taskId, task);

    // Register progress callback
    if (onProgress) {
      this.addProgressCallback(taskId, onProgress);
    }

    return task;
  }

  /**
   * Download a model by ID
   *
   * @param modelId - Model ID to download
   * @param onProgress - Optional progress callback
   * @returns Promise that resolves to local path when complete
   */
  async downloadModelById(
    modelId: string,
    onProgress?: ProgressCallback
  ): Promise<string> {
    const native = requireNativeModule();
    const taskId = await native.startModelDownload(modelId);

    // Register progress callback
    if (onProgress) {
      this.addProgressCallback(taskId, onProgress);
    }

    // Wait for completion
    return new Promise<string>((resolve, reject) => {
      const unsubscribe = EventBus.onModel((event) => {
        if (event.type === 'downloadCompleted' && event.modelId === modelId) {
          unsubscribe();
          this.progressCallbacks.delete(taskId);
          resolve(event.localPath ?? '');
        }
        if (event.type === 'downloadFailed' && event.modelId === modelId) {
          unsubscribe();
          this.progressCallbacks.delete(taskId);
          reject(new Error(event.error ?? 'Download failed'));
        }
      });
    });
  }

  /**
   * Cancel a download
   *
   * @param taskId - Task ID to cancel
   */
  async cancelDownload(taskId: string): Promise<void> {
    const native = requireNativeModule();
    await native.cancelDownload(taskId);

    this.activeTasks.delete(taskId);
    this.progressCallbacks.delete(taskId);
  }

  /**
   * Pause a download
   *
   * @param taskId - Task ID to pause
   */
  async pauseDownload(taskId: string): Promise<void> {
    const native = requireNativeModule();
    await native.pauseDownload(taskId);

    const task = this.activeTasks.get(taskId);
    if (task) {
      task.state = DownloadState.Paused;
    }
  }

  /**
   * Resume a paused download
   *
   * @param taskId - Task ID to resume
   */
  async resumeDownload(taskId: string): Promise<void> {
    const native = requireNativeModule();
    await native.resumeDownload(taskId);

    const task = this.activeTasks.get(taskId);
    if (task) {
      task.state = DownloadState.Downloading;
    }
  }

  /**
   * Pause all downloads
   */
  async pauseAll(): Promise<void> {
    const native = requireNativeModule();
    await native.pauseAllDownloads();

    for (const task of this.activeTasks.values()) {
      task.state = DownloadState.Paused;
    }
  }

  /**
   * Resume all paused downloads
   */
  async resumeAll(): Promise<void> {
    const native = requireNativeModule();
    await native.resumeAllDownloads();

    for (const task of this.activeTasks.values()) {
      if (task.state === DownloadState.Paused) {
        task.state = DownloadState.Downloading;
      }
    }
  }

  /**
   * Cancel all downloads
   */
  async cancelAll(): Promise<void> {
    const native = requireNativeModule();
    await native.cancelAllDownloads();

    this.activeTasks.clear();
    this.progressCallbacks.clear();
  }

  /**
   * Get active downloads
   *
   * @returns Array of active download tasks
   */
  getActiveDownloads(): DownloadTask[] {
    return Array.from(this.activeTasks.values());
  }

  /**
   * Check if a download is active
   *
   * @param modelId - Model ID to check
   * @returns Whether the model is being downloaded
   */
  isDownloading(modelId: string): boolean {
    for (const task of this.activeTasks.values()) {
      if (task.modelId === modelId && task.state === DownloadState.Downloading) {
        return true;
      }
    }
    return false;
  }

  /**
   * Get download progress for a model
   *
   * @param modelId - Model ID to check
   * @returns Current progress (0-1 fraction) or null if not downloading
   */
  async getDownloadProgress(modelId: string): Promise<number | null> {
    const native = requireNativeModule();
    const progressJson = await native.getDownloadProgress(modelId);
    try {
      const progressData = JSON.parse(progressJson);
      const progress = typeof progressData === 'number' ? progressData : progressData?.progress;
      return typeof progress === 'number' && progress >= 0 ? progress : null;
    } catch {
      return null;
    }
  }

  /**
   * Add a progress callback for a download
   *
   * @param taskId - Task ID to monitor
   * @param callback - Progress callback
   * @returns Function to remove the callback
   */
  addProgressCallback(taskId: string, callback: ProgressCallback): () => void {
    let callbacks = this.progressCallbacks.get(taskId);
    if (!callbacks) {
      callbacks = new Set();
      this.progressCallbacks.set(taskId, callbacks);
    }
    callbacks.add(callback);

    return () => {
      callbacks?.delete(callback);
    };
  }

  /**
   * Configure download settings
   *
   * @param config - Download configuration
   */
  async configure(config: DownloadConfiguration): Promise<void> {
    const native = requireNativeModule();
    await native.configureDownloadService(JSON.stringify(config));
  }

  /**
   * Check if download service is healthy
   *
   * @returns Whether the service is healthy
   */
  async isHealthy(): Promise<boolean> {
    const native = requireNativeModule();
    return native.isDownloadServiceHealthy();
  }

  /**
   * Get resume data for a failed download
   *
   * @param modelId - Model ID that failed
   * @returns Resume data or null
   */
  async getResumeData(modelId: string): Promise<string | null> {
    const native = requireNativeModule();
    return native.getDownloadResumeData(modelId);
  }

  /**
   * Resume a download with saved resume data
   *
   * @param modelId - Model ID to resume
   * @param resumeData - Resume data from getResumeData
   * @returns Download task
   */
  async resumeWithData(
    modelId: string,
    resumeData: string
  ): Promise<DownloadTask> {
    const native = requireNativeModule();
    const taskId = await native.resumeDownloadWithData(modelId, resumeData);

    const promise = new Promise<string>((resolve, reject) => {
      const unsubscribe = EventBus.onModel((event) => {
        if (event.type === 'downloadCompleted' && event.modelId === modelId) {
          unsubscribe();
          resolve(event.localPath ?? '');
        }
        if (event.type === 'downloadFailed' && event.modelId === modelId) {
          unsubscribe();
          reject(new Error(event.error ?? 'Download failed'));
        }
      });
    });

    const task: DownloadTask = {
      id: taskId,
      modelId,
      state: DownloadState.Downloading,
      promise,
      cancel: async () => this.cancelDownload(taskId),
      pause: async () => this.pauseDownload(taskId),
      resume: async () => this.resumeDownload(taskId),
    };

    this.activeTasks.set(taskId, task);
    return task;
  }

  /**
   * Reset the download service
   */
  reset(): void {
    this.activeTasks.clear();
    this.progressCallbacks.clear();
  }

  /**
   * Cleanup when done
   */
  destroy(): void {
    if (this.eventSubscription) {
      this.eventSubscription();
      this.eventSubscription = null;
    }
    this.reset();
  }
}

/**
 * Singleton instance of the Download Service
 */
export const DownloadService = new DownloadServiceImpl();

export default DownloadService;
