/**
 * Model Loader with progressive downloading and optimization
 */

import { Result } from '../types/result';
import { logger } from '../utils/logger';
import { ModelRegistry, ModelMetadata } from './model-registry';

export interface ModelLoadProgress {
  modelId: string;
  progress: number;
  message?: string;
  bytesLoaded?: number;
  totalBytes?: number;
  speed?: number; // bytes per second
  estimatedTimeRemaining?: number; // seconds
}

export interface LoaderOptions {
  concurrency?: number; // Max concurrent downloads
  chunkSize?: number; // Chunk size for progressive download
  retryAttempts?: number;
  retryDelay?: number; // milliseconds
  timeout?: number; // milliseconds
}

export class ModelLoader {
  private registry = ModelRegistry.getInstance();
  private activeDownloads = new Map<string, AbortController>();
  private downloadQueue: Array<{
    modelId: string;
    resolve: (value: Result<ArrayBuffer, Error>) => void;
    reject: (error: Error) => void;
    options?: LoaderOptions;
  }> = [];
  private concurrentDownloads = 0;
  private defaultOptions: LoaderOptions = {
    concurrency: 2,
    chunkSize: 1024 * 1024, // 1MB chunks
    retryAttempts: 3,
    retryDelay: 1000,
    timeout: 60000 // 60 seconds
  };

  async loadModel(
    modelId: string,
    options?: LoaderOptions & {
      onProgress?: (progress: ModelLoadProgress) => void;
    }
  ): Promise<Result<ArrayBuffer, Error>> {
    const mergedOptions = { ...this.defaultOptions, ...options };

    // Check if model is already being downloaded
    if (this.activeDownloads.has(modelId)) {
      logger.warn(`Model ${modelId} is already being downloaded`, 'ModelLoader');
      return Result.err(new Error('Model is already being downloaded'));
    }

    // Add to queue if at concurrency limit
    if (this.concurrentDownloads >= (mergedOptions.concurrency || 2)) {
      return this.queueDownload(modelId, mergedOptions);
    }

    // Start download
    return this.startDownload(modelId, mergedOptions, options?.onProgress);
  }

  private async queueDownload(
    modelId: string,
    options: LoaderOptions
  ): Promise<Result<ArrayBuffer, Error>> {
    return new Promise((resolve, reject) => {
      logger.info(`Queueing download for model ${modelId}`, 'ModelLoader');
      this.downloadQueue.push({ modelId, resolve, reject, options });
    });
  }

  private async startDownload(
    modelId: string,
    options: LoaderOptions,
    onProgress?: (progress: ModelLoadProgress) => void
  ): Promise<Result<ArrayBuffer, Error>> {
    this.concurrentDownloads++;
    const abortController = new AbortController();
    this.activeDownloads.set(modelId, abortController);

    try {
      const result = await this.downloadWithRetry(
        modelId,
        options,
        abortController.signal,
        onProgress
      );

      return result;
    } finally {
      this.concurrentDownloads--;
      this.activeDownloads.delete(modelId);

      // Process queue if there are pending downloads
      this.processQueue();
    }
  }

  private async downloadWithRetry(
    modelId: string,
    options: LoaderOptions,
    signal: AbortSignal,
    onProgress?: (progress: ModelLoadProgress) => void
  ): Promise<Result<ArrayBuffer, Error>> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < (options.retryAttempts || 3); attempt++) {
      if (signal.aborted) {
        return Result.err(new Error('Download cancelled'));
      }

      try {
        const result = await this.performDownload(modelId, options, signal, onProgress);
        if (result.success) {
          return result;
        }
        lastError = result.error;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
      }

      // Wait before retry
      if (attempt < (options.retryAttempts || 3) - 1) {
        logger.warn(`Download failed, retrying... (attempt ${attempt + 1})`, 'ModelLoader', {
          modelId,
          error: lastError?.message
        });
        await this.delay(options.retryDelay || 1000);
      }
    }

    return Result.err(lastError || new Error('Download failed after all retries'));
  }

  private async performDownload(
    modelId: string,
    options: LoaderOptions,
    signal: AbortSignal,
    onProgress?: (progress: ModelLoadProgress) => void
  ): Promise<Result<ArrayBuffer, Error>> {
    const metadata = this.registry.getModel(modelId);
    if (!metadata) {
      return Result.err(new Error(`Model ${modelId} not found`));
    }

    try {
      logger.info(`Starting progressive download for model ${modelId}`, 'ModelLoader');

      // Set up timeout
      const timeoutId = setTimeout(() => {
        signal.dispatchEvent(new Event('abort'));
      }, options.timeout || 60000);

      const response = await fetch(metadata.url, { signal });
      clearTimeout(timeoutId);

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const contentLength = response.headers.get('content-length');
      const total = contentLength ? parseInt(contentLength, 10) : metadata.size;

      // Check if we can use streaming
      if (!response.body) {
        // Fallback to simple download
        const buffer = await response.arrayBuffer();
        onProgress?.({
          modelId,
          progress: 100,
          message: 'Download complete',
          bytesLoaded: buffer.byteLength,
          totalBytes: buffer.byteLength
        });
        return Result.ok(buffer);
      }

      // Progressive download with chunks
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let receivedBytes = 0;
      const startTime = Date.now();

      while (true) {
        if (signal.aborted) {
          reader.cancel();
          throw new Error('Download cancelled');
        }

        const { done, value } = await reader.read();

        if (done) break;

        chunks.push(value);
        receivedBytes += value.length;

        // Calculate progress metrics
        const progress = Math.round((receivedBytes / total) * 100);
        const elapsedTime = (Date.now() - startTime) / 1000;
        const speed = receivedBytes / elapsedTime;
        const remainingBytes = total - receivedBytes;
        const estimatedTimeRemaining = remainingBytes / speed;

        onProgress?.({
          modelId,
          progress,
          message: `Downloading... ${this.formatBytes(receivedBytes)} / ${this.formatBytes(total)}`,
          bytesLoaded: receivedBytes,
          totalBytes: total,
          speed,
          estimatedTimeRemaining
        });
      }

      // Combine chunks
      const buffer = new Uint8Array(receivedBytes);
      let position = 0;
      for (const chunk of chunks) {
        buffer.set(chunk, position);
        position += chunk.length;
      }

      const arrayBuffer = buffer.buffer;

      onProgress?.({
        modelId,
        progress: 100,
        message: 'Download complete',
        bytesLoaded: receivedBytes,
        totalBytes: receivedBytes
      });

      logger.info(`Model ${modelId} downloaded successfully`, 'ModelLoader', {
        size: receivedBytes,
        duration: (Date.now() - startTime) / 1000
      });

      return Result.ok(arrayBuffer);

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to download model ${modelId}: ${err.message}`, 'ModelLoader');
      return Result.err(err);
    }
  }

  private processQueue(): void {
    if (this.downloadQueue.length === 0 ||
        this.concurrentDownloads >= (this.defaultOptions.concurrency || 2)) {
      return;
    }

    const next = this.downloadQueue.shift();
    if (next) {
      logger.info(`Processing queued download for model ${next.modelId}`, 'ModelLoader');
      this.startDownload(next.modelId, next.options || this.defaultOptions)
        .then(next.resolve)
        .catch(next.reject);
    }
  }

  cancelDownload(modelId: string): boolean {
    const controller = this.activeDownloads.get(modelId);
    if (controller) {
      controller.abort();
      this.activeDownloads.delete(modelId);
      logger.info(`Download cancelled for model ${modelId}`, 'ModelLoader');
      return true;
    }

    // Remove from queue if present
    const queueIndex = this.downloadQueue.findIndex(item => item.modelId === modelId);
    if (queueIndex !== -1) {
      const item = this.downloadQueue.splice(queueIndex, 1)[0];
      item.reject(new Error('Download cancelled'));
      return true;
    }

    return false;
  }

  cancelAllDownloads(): void {
    // Cancel active downloads
    for (const [modelId, controller] of this.activeDownloads) {
      controller.abort();
      logger.info(`Cancelled download for model ${modelId}`, 'ModelLoader');
    }
    this.activeDownloads.clear();
    this.concurrentDownloads = 0;

    // Clear queue
    for (const item of this.downloadQueue) {
      item.reject(new Error('All downloads cancelled'));
    }
    this.downloadQueue = [];
  }

  getActiveDownloads(): string[] {
    return Array.from(this.activeDownloads.keys());
  }

  getQueuedDownloads(): string[] {
    return this.downloadQueue.map(item => item.modelId);
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) return '0 Bytes';

    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));

    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  async preloadModels(
    modelIds: string[],
    onProgress?: (modelId: string, progress: ModelLoadProgress) => void
  ): Promise<Map<string, Result<ArrayBuffer, Error>>> {
    const results = new Map<string, Result<ArrayBuffer, Error>>();

    // Load models with controlled concurrency
    const loadPromises = modelIds.map(async (modelId) => {
      const result = await this.loadModel(modelId, {
        onProgress: (progress) => onProgress?.(modelId, progress)
      });
      results.set(modelId, result);
    });

    await Promise.all(loadPromises);

    return results;
  }
}
