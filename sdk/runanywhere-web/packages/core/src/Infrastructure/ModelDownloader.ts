/**
 * Model Downloader - Download orchestration with OPFS persistence
 *
 * Handles single-file and multi-file model downloads with progress tracking.
 * Delegates all OPFS storage operations to the enhanced OPFSStorage class.
 * Extracted from ModelManager to separate download concerns from load/catalog logic.
 */

import { EventBus } from '../Foundation/EventBus';
import { OPFSStorage } from './OPFSStorage';
import { ModelStatus, DownloadStage, SDKEventType } from '../types/enums';
import type { ManagedModel, DownloadProgress } from './ModelRegistry';
import type { ModelRegistry } from './ModelRegistry';

// ---------------------------------------------------------------------------
// Model Downloader
// ---------------------------------------------------------------------------

/**
 * ModelDownloader — downloads model files (single or multi-file) and
 * persists them in OPFS via `OPFSStorage`. Reports progress to the
 * `ModelRegistry` and emits events via `EventBus`.
 */
export class ModelDownloader {
  private readonly storage: OPFSStorage;
  private readonly registry: ModelRegistry;

  constructor(registry: ModelRegistry, storage: OPFSStorage) {
    this.registry = registry;
    this.storage = storage;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Download a model (and any additional companion files).
   * Handles both single-file and multi-file models.
   */
  async downloadModel(modelId: string): Promise<void> {
    const model = this.registry.getModel(modelId);
    if (!model) return;

    this.registry.updateModel(modelId, { status: ModelStatus.Downloading, downloadProgress: 0 });
    EventBus.shared.emit('model.downloadStarted', SDKEventType.Model, { modelId, url: model.url });

    try {
      const totalFiles = 1 + (model.additionalFiles?.length ?? 0);
      let totalBytesDownloaded = 0;
      let totalBytesExpected = 0;

      // Download the primary file
      const primaryData = await this.downloadFile(model.url, (progress, bytesDown, bytesTotal) => {
        totalBytesDownloaded = bytesDown;
        totalBytesExpected = bytesTotal * totalFiles; // rough estimate
        const overallProgress = progress / totalFiles;
        this.registry.updateModel(modelId, { downloadProgress: overallProgress });
        this.emitDownloadProgress({
          modelId,
          stage: DownloadStage.Downloading,
          progress: overallProgress,
          bytesDownloaded: totalBytesDownloaded,
          totalBytes: totalBytesExpected,
          currentFile: model.url.split('/').pop(),
          filesCompleted: 0,
          filesTotal: totalFiles,
        });
      });

      await this.storeInOPFS(modelId, primaryData);

      // Download additional files (e.g., mmproj for VLM)
      if (model.additionalFiles && model.additionalFiles.length > 0) {
        for (let i = 0; i < model.additionalFiles.length; i++) {
          const file = model.additionalFiles[i];
          const fileKey = this.additionalFileKey(modelId, file.filename);
          const fileData = await this.downloadFile(file.url, (progress, bytesDown, bytesTotal) => {
            const baseProgress = (1 + i) / totalFiles;
            const fileProgress = progress / totalFiles;
            const overallProgress = baseProgress + fileProgress;
            this.registry.updateModel(modelId, { downloadProgress: overallProgress });
            this.emitDownloadProgress({
              modelId,
              stage: DownloadStage.Downloading,
              progress: overallProgress,
              bytesDownloaded: bytesDown,
              totalBytes: bytesTotal,
              currentFile: file.filename,
              filesCompleted: 1 + i,
              filesTotal: totalFiles,
            });
          });
          await this.storeInOPFS(fileKey, fileData);
        }
      }

      // Validating stage
      this.emitDownloadProgress({
        modelId,
        stage: DownloadStage.Validating,
        progress: 0.95,
        bytesDownloaded: totalBytesDownloaded,
        totalBytes: totalBytesExpected,
        filesCompleted: totalFiles,
        filesTotal: totalFiles,
      });

      let totalSize = primaryData.length;
      if (model.additionalFiles) {
        for (const file of model.additionalFiles) {
          const fileKey = this.additionalFileKey(modelId, file.filename);
          const size = await this.storage.getFileSize(fileKey);
          if (size !== null) totalSize += size;
        }
      }

      this.registry.updateModel(modelId, {
        status: ModelStatus.Downloaded,
        downloadProgress: 1,
        sizeBytes: totalSize,
      });

      // Completed stage
      this.emitDownloadProgress({
        modelId,
        stage: DownloadStage.Completed,
        progress: 1,
        bytesDownloaded: totalSize,
        totalBytes: totalSize,
        filesCompleted: totalFiles,
        filesTotal: totalFiles,
      });
      EventBus.shared.emit('model.downloadCompleted', SDKEventType.Model, { modelId, sizeBytes: totalSize });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.registry.updateModel(modelId, { status: ModelStatus.Error, error: message });
      EventBus.shared.emit('model.downloadFailed', SDKEventType.Model, { modelId, error: message });
    }
  }

  // ---------------------------------------------------------------------------
  // OPFS delegation helpers (used by ModelManager for load-time operations)
  // ---------------------------------------------------------------------------

  /**
   * Download a file from a URL with optional progress callback.
   * Exposed so ModelManager can use it for on-demand file downloads during load.
   */
  async downloadFile(
    url: string,
    onProgress?: (progress: number, bytesDownloaded: number, totalBytes: number) => void,
  ): Promise<Uint8Array> {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);

    const total = Number(response.headers.get('content-length') || 0);
    const reader = response.body?.getReader();
    if (!reader) throw new Error('No response body');

    const chunks: Uint8Array[] = [];
    let received = 0;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      received += value.length;
      const progress = total > 0 ? received / total : 0;
      onProgress?.(progress, received, total);
    }

    const data = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) {
      data.set(chunk, offset);
      offset += chunk.length;
    }

    return data;
  }

  /** Store data in OPFS via OPFSStorage. */
  async storeInOPFS(key: string, data: Uint8Array): Promise<void> {
    try {
      await this.storage.saveModel(key, data.buffer as ArrayBuffer);
      console.log(`[ModelDownloader] Stored ${key} in OPFS (${(data.length / 1024 / 1024).toFixed(1)} MB)`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[ModelDownloader] OPFS store failed for "${key}": ${msg}`);
    }
  }

  /** Load data from OPFS via OPFSStorage. */
  async loadFromOPFS(key: string): Promise<Uint8Array | null> {
    const buffer = await this.storage.loadModel(key);
    if (!buffer) return null;
    console.log(`[ModelDownloader] Loading ${key} from OPFS (${(buffer.byteLength / 1024 / 1024).toFixed(1)} MB)`);
    return new Uint8Array(buffer);
  }

  /** Check existence in OPFS via OPFSStorage. */
  async existsInOPFS(key: string): Promise<boolean> {
    return this.storage.hasModel(key);
  }

  /** Delete from OPFS via OPFSStorage. */
  async deleteFromOPFS(key: string): Promise<void> {
    await this.storage.deleteModel(key);
  }

  /** Get file size from OPFS without reading into memory. */
  async getOPFSFileSize(key: string): Promise<number | null> {
    return this.storage.getFileSize(key);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /**
   * Build an OPFS key for additional files (e.g., mmproj).
   * Uses `__` separator to avoid name collisions between
   * a primary model FILE and a directory with the same name.
   */
  additionalFileKey(modelId: string, filename: string): string {
    return `${modelId}__${filename}`;
  }

  /** Emit a structured download progress event via EventBus */
  private emitDownloadProgress(progress: DownloadProgress): void {
    EventBus.shared.emit('model.downloadProgress', SDKEventType.Model, progress as unknown as Record<string, unknown>);
  }
}
