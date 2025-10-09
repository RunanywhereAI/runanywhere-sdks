/**
 * Unified Download Manager inspired by iOS SDK patterns
 * Handles model downloading, caching, and validation across different frameworks
 */

import { Result } from '../types/result';
import { logger } from '../utils/logger';
import { ModelCache } from '../models/model-cache';
import { ModelRegistry, type ModelMetadata } from '../models/model-registry';

export enum DownloadState {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  EXTRACTING = 'extracting',
  RETRYING = 'retrying',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export interface DownloadProgress {
  modelId: string;
  bytesDownloaded: number;
  totalBytes: number;
  state: DownloadState;
  estimatedTimeRemaining?: number;
  downloadSpeed?: number;
  percentage: number;
  currentFile?: string;
  message?: string;
}

export interface DownloadTask {
  readonly id: string;
  readonly modelId: string;
  readonly state: DownloadState;
  readonly progress: DownloadProgress;
  cancel(): void;
  getResult(): Promise<ArrayBuffer>;
  onProgress(callback: (progress: DownloadProgress) => void): void;
  onStateChange(callback: (state: DownloadState) => void): void;
}

export interface DownloadStrategy {
  readonly name: string;
  canHandle(model: ModelMetadata): boolean;
  download(
    model: ModelMetadata,
    options?: DownloadOptions
  ): Promise<DownloadTask>;
}

export interface DownloadOptions {
  onProgress?: (progress: DownloadProgress) => void;
  onStateChange?: (state: DownloadState) => void;
  validateHash?: boolean;
  maxRetries?: number;
  timeout?: number;
  resumeData?: ArrayBuffer;
}

class DownloadTaskImpl implements DownloadTask {
  private progressCallbacks: Array<(progress: DownloadProgress) => void> = [];
  private stateCallbacks: Array<(state: DownloadState) => void> = [];
  private abortController = new AbortController();
  private currentProgress: DownloadProgress;
  private currentState: DownloadState = DownloadState.PENDING;

  constructor(
    public readonly id: string,
    public readonly modelId: string,
    private downloadPromise: Promise<ArrayBuffer>,
    initialProgress: DownloadProgress
  ) {
    this.currentProgress = initialProgress;
  }

  get state(): DownloadState {
    return this.currentState;
  }

  get progress(): DownloadProgress {
    return this.currentProgress;
  }

  updateProgress(progress: DownloadProgress): void {
    this.currentProgress = progress;
    this.progressCallbacks.forEach(callback => callback(progress));

    if (progress.state !== this.currentState) {
      this.currentState = progress.state;
      this.stateCallbacks.forEach(callback => callback(progress.state));
    }
  }

  onProgress(callback: (progress: DownloadProgress) => void): void {
    this.progressCallbacks.push(callback);
  }

  onStateChange(callback: (state: DownloadState) => void): void {
    this.stateCallbacks.push(callback);
  }

  cancel(): void {
    this.abortController.abort();
    this.updateProgress({
      ...this.currentProgress,
      state: DownloadState.CANCELLED,
      message: 'Download cancelled'
    });
  }

  async getResult(): Promise<ArrayBuffer> {
    return this.downloadPromise;
  }

  getAbortSignal(): AbortSignal {
    return this.abortController.signal;
  }
}

/**
 * Standard HTTP download strategy for single-file models
 */
class StandardDownloadStrategy implements DownloadStrategy {
  readonly name = 'standard';

  canHandle(model: ModelMetadata): boolean {
    return model.format === 'onnx' || model.format === 'tensorflow' || model.format === 'pytorch';
  }

  async download(model: ModelMetadata, options?: DownloadOptions): Promise<DownloadTask> {
    const taskId = `download-${model.id}-${Date.now()}`;

    const initialProgress: DownloadProgress = {
      modelId: model.id,
      bytesDownloaded: 0,
      totalBytes: model.size,
      state: DownloadState.PENDING,
      percentage: 0,
      message: 'Initializing download...'
    };

    const downloadPromise = this.performDownload(model, options, (progress) => {
      task.updateProgress(progress);
    });

    const task = new DownloadTaskImpl(taskId, model.id, downloadPromise, initialProgress);

    // Set up callbacks if provided
    if (options?.onProgress) {
      task.onProgress(options.onProgress);
    }
    if (options?.onStateChange) {
      task.onStateChange(options.onStateChange);
    }

    return task;
  }

  private async performDownload(
    model: ModelMetadata,
    options?: DownloadOptions,
    progressCallback?: (progress: DownloadProgress) => void
  ): Promise<ArrayBuffer> {
    const startTime = Date.now();

    progressCallback?.({
      modelId: model.id,
      bytesDownloaded: 0,
      totalBytes: model.size,
      state: DownloadState.DOWNLOADING,
      percentage: 0,
      message: 'Starting download...'
    });

    const response = await fetch(model.url, {
      signal: AbortSignal.timeout(options?.timeout || 300000) // 5 minutes default
    });

    if (!response.ok) {
      throw new Error(`Failed to download model: ${response.statusText}`);
    }

    const contentLength = response.headers.get('content-length');
    const totalBytes = contentLength ? parseInt(contentLength, 10) : model.size;

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('Response body is not readable');
    }

    const chunks: Uint8Array[] = [];
    let bytesDownloaded = 0;
    let lastProgressTime = startTime;

    while (true) {
      const { done, value } = await reader.read();

      if (done) break;

      chunks.push(value);
      bytesDownloaded += value.length;

      // Update progress (throttled)
      const now = Date.now();
      if (now - lastProgressTime > 100 || bytesDownloaded === totalBytes) { // Update every 100ms
        const elapsed = now - startTime;
        const downloadSpeed = elapsed > 0 ? (bytesDownloaded / elapsed) * 1000 : 0; // bytes/second
        const estimatedTimeRemaining = downloadSpeed > 0 ?
          (totalBytes - bytesDownloaded) / downloadSpeed : undefined;

        progressCallback?.({
          modelId: model.id,
          bytesDownloaded,
          totalBytes,
          state: DownloadState.DOWNLOADING,
          percentage: Math.round((bytesDownloaded / totalBytes) * 100),
          downloadSpeed,
          estimatedTimeRemaining,
          message: `Downloading... ${Math.round((bytesDownloaded / totalBytes) * 100)}%`
        });

        lastProgressTime = now;
      }
    }

    // Combine chunks
    const buffer = new Uint8Array(bytesDownloaded);
    let position = 0;
    for (const chunk of chunks) {
      buffer.set(chunk, position);
      position += chunk.length;
    }

    progressCallback?.({
      modelId: model.id,
      bytesDownloaded,
      totalBytes: bytesDownloaded,
      state: DownloadState.COMPLETED,
      percentage: 100,
      message: 'Download completed'
    });

    return buffer.buffer;
  }
}

/**
 * Transformers.js-aware download strategy that integrates with transformers.js caching
 */
class TransformersDownloadStrategy implements DownloadStrategy {
  readonly name = 'transformers';

  canHandle(model: ModelMetadata): boolean {
    return model.format === 'custom' &&
           (model.provider === 'openai' || model.provider === 'huggingface');
  }

  async download(model: ModelMetadata, options?: DownloadOptions): Promise<DownloadTask> {
    // Transformers.js handles its own downloads, so we create a monitoring task
    const taskId = `transformers-${model.id}-${Date.now()}`;

    const initialProgress: DownloadProgress = {
      modelId: model.id,
      bytesDownloaded: 0,
      totalBytes: model.size,
      state: DownloadState.PENDING,
      percentage: 0,
      message: 'Preparing transformers.js download...'
    };

    // Create a promise that resolves when transformers.js completes loading
    const downloadPromise = new Promise<ArrayBuffer>((resolve, reject) => {
      // This will be handled by the transformers.js worker
      // We return an empty buffer since transformers.js manages the actual files
      resolve(new ArrayBuffer(0));
    });

    const task = new DownloadTaskImpl(taskId, model.id, downloadPromise, initialProgress);

    // Set up callbacks if provided
    if (options?.onProgress) {
      task.onProgress(options.onProgress);
    }
    if (options?.onStateChange) {
      task.onStateChange(options.onStateChange);
    }

    // Immediately mark as completed since transformers.js will handle the actual download
    setTimeout(() => {
      task.updateProgress({
        ...initialProgress,
        state: DownloadState.COMPLETED,
        percentage: 100,
        message: 'Delegated to transformers.js'
      });
    }, 100);

    return task;
  }
}

/**
 * Unified Download Manager that coordinates different download strategies
 */
export class UnifiedDownloadManager {
  private static instance: UnifiedDownloadManager;
  private strategies = new Map<string, DownloadStrategy>();
  private activeTasks = new Map<string, DownloadTask>();
  private modelRegistry: ModelRegistry;
  private modelCache: ModelCache;
  private resumeDataStore = new Map<string, ArrayBuffer>();

  private constructor() {
    this.modelRegistry = ModelRegistry.getInstance();
    this.modelCache = new ModelCache();
    this.initializeStrategies();
  }

  static getInstance(): UnifiedDownloadManager {
    if (!UnifiedDownloadManager.instance) {
      UnifiedDownloadManager.instance = new UnifiedDownloadManager();
    }
    return UnifiedDownloadManager.instance;
  }

  private initializeStrategies(): void {
    this.registerStrategy(new StandardDownloadStrategy());
    this.registerStrategy(new TransformersDownloadStrategy());
  }

  async initialize(): Promise<Result<void, Error>> {
    try {
      await this.modelCache.initialize();
      logger.info('Unified Download Manager initialized', 'UnifiedDownloadManager');
      return Result.ok(undefined);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to initialize download manager: ${err.message}`, 'UnifiedDownloadManager');
      return Result.err(err);
    }
  }

  registerStrategy(strategy: DownloadStrategy): void {
    this.strategies.set(strategy.name, strategy);
    logger.debug(`Registered download strategy: ${strategy.name}`, 'UnifiedDownloadManager');
  }

  async downloadModel(
    modelId: string,
    options?: DownloadOptions
  ): Promise<Result<DownloadTask, Error>> {
    try {
      // Check if already downloading
      const existingTask = this.activeTasks.get(modelId);
      if (existingTask && existingTask.state !== DownloadState.COMPLETED &&
          existingTask.state !== DownloadState.FAILED && existingTask.state !== DownloadState.CANCELLED) {
        logger.debug(`Model ${modelId} already downloading`, 'UnifiedDownloadManager');
        return Result.ok(existingTask);
      }

      // Check cache first
      const cached = await this.modelCache.get(modelId);
      if (cached && !options?.resumeData) {
        logger.info(`Model ${modelId} found in cache`, 'UnifiedDownloadManager');

        // Create a completed task for cached models
        const cachedTask = new DownloadTaskImpl(
          `cached-${modelId}`,
          modelId,
          Promise.resolve(cached),
          {
            modelId,
            bytesDownloaded: cached.byteLength,
            totalBytes: cached.byteLength,
            state: DownloadState.COMPLETED,
            percentage: 100,
            message: 'Loaded from cache'
          }
        );

        return Result.ok(cachedTask);
      }

      // Get model metadata
      const model = this.modelRegistry.getModel(modelId);
      if (!model) {
        return Result.err(new Error(`Model ${modelId} not found in registry`));
      }

      // Find appropriate strategy
      const strategy = this.findStrategy(model);
      if (!strategy) {
        return Result.err(new Error(`No download strategy available for model ${modelId}`));
      }

      // Start download
      logger.info(`Starting download for model ${modelId} using ${strategy.name} strategy`, 'UnifiedDownloadManager');

      const task = await strategy.download(model, {
        ...options,
        onProgress: (progress) => {
          options?.onProgress?.(progress);
          // Cache the model when download completes
          if (progress.state === DownloadState.COMPLETED) {
            this.cacheCompletedDownload(modelId, task);
          }
        }
      });

      this.activeTasks.set(modelId, task);

      // Clean up task when it's done
      task.onStateChange((state) => {
        if (state === DownloadState.COMPLETED ||
            state === DownloadState.FAILED ||
            state === DownloadState.CANCELLED) {
          this.activeTasks.delete(modelId);
        }
      });

      return Result.ok(task);

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to start download for model ${modelId}: ${err.message}`, 'UnifiedDownloadManager');
      return Result.err(err);
    }
  }

  private findStrategy(model: ModelMetadata): DownloadStrategy | null {
    for (const strategy of this.strategies.values()) {
      if (strategy.canHandle(model)) {
        return strategy;
      }
    }
    return null;
  }

  private async cacheCompletedDownload(modelId: string, task: DownloadTask): Promise<void> {
    try {
      const result = await task.getResult();
      await this.modelCache.set(modelId, result);
      logger.info(`Cached model ${modelId} after successful download`, 'UnifiedDownloadManager');
    } catch (error) {
      logger.error(`Failed to cache model ${modelId}: ${error}`, 'UnifiedDownloadManager');
    }
  }

  cancelDownload(modelId: string): void {
    const task = this.activeTasks.get(modelId);
    if (task) {
      task.cancel();
      logger.info(`Cancelled download for model ${modelId}`, 'UnifiedDownloadManager');
    }
  }

  getActiveDownloads(): DownloadTask[] {
    return Array.from(this.activeTasks.values());
  }

  getDownloadStatus(modelId: string): DownloadTask | null {
    return this.activeTasks.get(modelId) || null;
  }

  async clearCache(modelId?: string): Promise<void> {
    await this.modelCache.clearCache(modelId);
    logger.info(modelId ? `Cleared cache for model ${modelId}` : 'Cleared all model cache', 'UnifiedDownloadManager');
  }
}
