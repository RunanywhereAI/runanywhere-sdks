/**
 * Model Downloader - Download orchestration with OPFS persistence
 *
 * Handles single-file and multi-file model downloads with progress tracking.
 * Delegates all OPFS storage operations to the enhanced OPFSStorage class.
 * Extracted from ModelManager to separate download concerns from load/catalog logic.
 */

import { EventBus } from '../Foundation/EventBus';
import { SDKLogger } from '../Foundation/SDKLogger';
import { AnalyticsEmitter } from '../services/AnalyticsEmitter';
import type { OPFSStorage, MetadataMap } from './OPFSStorage';
import type { LocalFileStorage } from './LocalFileStorage';
import { ModelStatus, DownloadStage, SDKEventType } from '../types/enums';
import type { ManagedModel, DownloadProgress } from './ModelRegistry';
import type { ModelRegistry } from './ModelRegistry';
import { HTTPAdapter } from '../Adapters/HTTPAdapter';
import { validateModelUrl } from './ModelDownloadValidation';
import { checkModelStorageQuota } from './ModelDownloadQuota';
import type { QuotaCheckResult } from './ModelDownloadQuota';

export type { EvictionCandidateInfo, QuotaCheckResult } from './ModelDownloadQuota';

/**
 * ModelDownloader — downloads model files (single or multi-file) and
 * persists them in OPFS via `OPFSStorage`. Reports progress to the
 * `ModelRegistry` and emits events via `EventBus`.
 */
const logger = new SDKLogger('ModelDownloader');

export class ModelDownloader {
  private readonly storage: OPFSStorage;
  private readonly registry: ModelRegistry;

  /**
   * Optional local filesystem storage. When configured, models are saved
   * to the user's chosen directory instead of OPFS. Set via setLocalFileStorage().
   */
  private localFileStorage: LocalFileStorage | null = null;

  /**
   * In-memory fallback cache for models that were downloaded successfully
   * but failed to persist to OPFS (e.g. storage quota exceeded).
   * Keyed by modelId/file key. Cleared once the data is consumed by loadFromOPFS.
   */
  private readonly memoryCache = new Map<string, Uint8Array>();
  private readonly activeDownloadControllers = new Map<string, Set<AbortController>>();

  constructor(registry: ModelRegistry, storage: OPFSStorage) {
    this.registry = registry;
    this.storage = storage;
  }

  /**
   * Set the local file storage backend.
   * When configured and ready, models are saved/loaded from the local filesystem first.
   */
  setLocalFileStorage(storage: LocalFileStorage): void {
    this.localFileStorage = storage;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Check whether a model will fit in OPFS without eviction.
   *
   * Uses `navigator.storage.estimate()` for available space and compares
   * against the model's total size (primary + additional files).
   * If the model won't fit, returns eviction candidates sorted by LRU.
   *
   * @param model       - The model to check
   * @param metadata    - LRU metadata map (lastUsedAt per model)
   * @param loadedModelId - Currently loaded model ID (excluded from eviction)
   */
  async checkStorageQuota(
    model: ManagedModel,
    metadata: MetadataMap,
    loadedModelId?: string,
  ): Promise<QuotaCheckResult> {
    return checkModelStorageQuota(model, metadata, loadedModelId, this.storage, this.registry);
  }

  /**
   * Download a model (and any additional companion files).
   * Handles both single-file and multi-file models.
   */
  async downloadModel(modelId: string): Promise<void> {
    const model = this.registry.getModel(modelId);
    if (!model) return;

    this.registry.updateModel(modelId, { status: ModelStatus.Downloading, downloadProgress: 0 });
    EventBus.shared.emit('model.downloadStarted', SDKEventType.Model, { modelId, url: model.url });
    AnalyticsEmitter.emitModelDownloadStarted(modelId);

    try {
      const totalFiles = 1 + (model.additionalFiles?.length ?? 0);
      let cumulativeBytesDownloaded = 0;
      let cumulativeBytesExpected = 0;
      const completedFileSizes: number[] = [];

      const primaryProgressCb = (progress: number, bytesDown: number, bytesTotal: number) => {
        cumulativeBytesDownloaded = bytesDown;
        cumulativeBytesExpected = bytesTotal * totalFiles;
        const overallProgress = progress / totalFiles;
        this.registry.updateModel(modelId, { downloadProgress: overallProgress });
        this.emitDownloadProgress({
          modelId,
          stage: DownloadStage.Downloading,
          progress: overallProgress,
          bytesDownloaded: cumulativeBytesDownloaded,
          totalBytes: cumulativeBytesExpected,
          currentFile: model.url.split('/').pop(),
          filesCompleted: 0,
          filesTotal: totalFiles,
        });
      };

      let primarySize = await this.downloadAndStoreStreaming(model.url, modelId, primaryProgressCb, modelId);
      if (primarySize === null) {
        const primaryData = await this.downloadFile(model.url, primaryProgressCb, modelId);
        await this.storeInOPFS(modelId, primaryData);
        primarySize = primaryData.length;
      }
      completedFileSizes.push(primarySize);

      // Download additional files (e.g., mmproj for VLM)
      if (model.additionalFiles && model.additionalFiles.length > 0) {
        for (let i = 0; i < model.additionalFiles.length; i++) {
          const file = model.additionalFiles[i];
          const fileKey = this.additionalFileKey(modelId, file.filename);
          const priorCompleted = completedFileSizes.reduce((a, b) => a + b, 0);

          const fileProgressCb = (progress: number, bytesDown: number, bytesTotal: number) => {
            cumulativeBytesDownloaded = priorCompleted + bytesDown;
            cumulativeBytesExpected = priorCompleted + bytesTotal;
            const baseProgress = (1 + i) / totalFiles;
            const fileProgress = progress / totalFiles;
            const overallProgress = baseProgress + fileProgress;
            this.registry.updateModel(modelId, { downloadProgress: overallProgress });
            this.emitDownloadProgress({
              modelId,
              stage: DownloadStage.Downloading,
              progress: overallProgress,
              bytesDownloaded: cumulativeBytesDownloaded,
              totalBytes: cumulativeBytesExpected,
              currentFile: file.filename,
              filesCompleted: 1 + i,
              filesTotal: totalFiles,
            });
          };

          let fileSize: number;
          const streamedSize = await this.downloadAndStoreStreaming(file.url, fileKey, fileProgressCb, modelId);
          if (streamedSize === null) {
            const fileData = await this.downloadFile(file.url, fileProgressCb, modelId);
            await this.storeInOPFS(fileKey, fileData);
            fileSize = fileData.length;
          } else {
            fileSize = streamedSize;
          }
          completedFileSizes.push(fileSize);
        }
      }

      const totalSize = completedFileSizes.reduce((a, b) => a + b, 0);

      // Validating stage
      this.emitDownloadProgress({
        modelId,
        stage: DownloadStage.Validating,
        progress: 0.95,
        bytesDownloaded: totalSize,
        totalBytes: totalSize,
        filesCompleted: totalFiles,
        filesTotal: totalFiles,
      });

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
      AnalyticsEmitter.emitModelDownloadCompleted(modelId, totalSize, 0);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.registry.updateModel(modelId, { status: ModelStatus.Error, error: message });
      EventBus.shared.emit('model.downloadFailed', SDKEventType.Model, { modelId, error: message });
      AnalyticsEmitter.emitModelDownloadFailed(modelId, message);
    } finally {
      this.activeDownloadControllers.delete(modelId);
    }
  }

  cancelDownload(modelId: string): boolean {
    const controllers = this.activeDownloadControllers.get(modelId);
    if (!controllers || controllers.size === 0) return false;

    for (const controller of controllers) {
      controller.abort();
    }
    this.activeDownloadControllers.delete(modelId);
    this.registry.updateModel(modelId, { status: ModelStatus.Registered, downloadProgress: 0 });
    EventBus.shared.emit('model.downloadCancelled', SDKEventType.Model, { modelId });
    return true;
  }

  private registerAbortController(modelId: string): AbortController {
    const controller = new AbortController();
    const controllers = this.activeDownloadControllers.get(modelId) ?? new Set<AbortController>();
    controllers.add(controller);
    this.activeDownloadControllers.set(modelId, controllers);
    return controller;
  }

  private unregisterAbortController(modelId: string, controller: AbortController): void {
    const controllers = this.activeDownloadControllers.get(modelId);
    if (!controllers) return;
    controllers.delete(controller);
    if (controllers.size === 0) {
      this.activeDownloadControllers.delete(modelId);
    }
  }

  // ---------------------------------------------------------------------------
  // OPFS delegation helpers (used by ModelManager for load-time operations)
  // ---------------------------------------------------------------------------

  /**
   * Download a file from a URL with optional progress callback.
   * Exposed so ModelManager can use it for on-demand file downloads during load.
   *
   * URLs are validated before fetching to prevent SSRF and enforce HTTPS.
   *
   * Transport selection (T3.13):
   *   1. If a backend package has registered an Emscripten module with
   *      HTTPAdapter, route through the commons libcurl C ABI for
   *      parity with Swift/Kotlin/RN/Flutter downloads.
   *   2. Otherwise fall back to the browser fetch stream — this
   *      is the bootstrap path, reached before any backend WASM has
   *      loaded (e.g. a consumer that only uses core storage APIs).
   */
  async downloadFile(
    url: string,
    onProgress?: (progress: number, bytesDownloaded: number, totalBytes: number) => void,
    cancelGroup?: string,
  ): Promise<Uint8Array> {
    validateModelUrl(url);

    const http = HTTPAdapter.tryDefault();
    if (http) {
      return this.downloadFileViaWasm(http, url, onProgress);
    }

    // HTTP_FETCH_CARVE_OUTS.noWasmModuleRegisteredFallback: pure-core callers can download before a backend loads.
    const controller = cancelGroup ? this.registerAbortController(cancelGroup) : null;
    try {
      const response = await fetch(url, { signal: controller?.signal }); // fetch() carve-out: fallback when no WASM module registered.
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
    } finally {
      if (cancelGroup && controller) this.unregisterAbortController(cancelGroup, controller);
    }
  }

  /**
   * WASM-backed variant of `downloadFile` — collects chunks delivered
   * via the commons streaming HTTP client into a single `Uint8Array`.
   */
  private async downloadFileViaWasm(
    http: HTTPAdapter,
    url: string,
    onProgress?: (progress: number, bytesDownloaded: number, totalBytes: number) => void,
  ): Promise<Uint8Array> {
    const chunks: Uint8Array[] = [];
    let received = 0;
    let declaredTotal = 0;

    await http.stream({ url }, (chunk, totalWritten, contentLength) => {
      chunks.push(chunk);
      received = totalWritten;
      if (contentLength > 0) declaredTotal = contentLength;
      const progress = declaredTotal > 0 ? received / declaredTotal : 0;
      onProgress?.(progress, received, declaredTotal);
    });

    const data = new Uint8Array(received);
    let offset = 0;
    for (const c of chunks) {
      data.set(c, offset);
      offset += c.length;
    }
    return data;
  }

  /**
   * Download a file and stream it directly to persistent storage (OPFS or local FS)
   * without buffering the entire payload in memory.
   *
   * Returns the total bytes downloaded. Falls back to buffered download + store
   * if streaming write is not supported or fails.
   *
   * @returns Total bytes written, or null if streaming was not possible.
   */
  async downloadAndStoreStreaming(
    url: string,
    storageKey: string,
    onProgress?: (progress: number, bytesDownloaded: number, totalBytes: number) => void,
    cancelGroup?: string,
  ): Promise<number | null> {
    validateModelUrl(url);

    const http = HTTPAdapter.tryDefault();
    if (http) {
      return this.streamViaWasm(http, url, storageKey, onProgress);
    }

    // HTTP_FETCH_CARVE_OUTS.noWasmModuleRegisteredFallback: pure-core callers can stream before a backend loads.
    const controller = cancelGroup ? this.registerAbortController(cancelGroup) : null;
    try {
      const response = await fetch(url, { signal: controller?.signal }); // fetch() carve-out: fallback when no WASM module registered.
      if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);
      if (!response.body) return null;

      const total = Number(response.headers.get('content-length') || 0);
      let received = 0;

      const progressTransform = new TransformStream<Uint8Array, Uint8Array>({
        transform: (chunk, controller) => {
          received += chunk.length;
          onProgress?.(total > 0 ? received / total : 0, received, total);
          controller.enqueue(chunk);
        },
      });

      const storageStream = response.body.pipeThrough(progressTransform);

      if (this.localFileStorage?.isReady) {
        await this.localFileStorage.saveModelFromStream(storageKey, storageStream);
        logger.info(`Streamed ${storageKey} to local storage (${(received / 1024 / 1024).toFixed(1)} MB)`);
        return received;
      }

      await this.storage.saveModelFromStream(storageKey, storageStream);
      logger.info(`Streamed ${storageKey} to OPFS (${(received / 1024 / 1024).toFixed(1)} MB)`);
      return received;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warning(`Streaming store failed for "${storageKey}": ${msg}, will fall back to buffered download`);
      return null;
    } finally {
      if (cancelGroup && controller) this.unregisterAbortController(cancelGroup, controller);
    }
  }

  /**
   * WASM-backed streaming download: bridges `rac_http_request_stream`
   * chunk callbacks into a JS `ReadableStream` that the same storage
   * pipeline (`saveModelFromStream`) can consume unchanged.
   */
  private async streamViaWasm(
    http: HTTPAdapter,
    url: string,
    storageKey: string,
    onProgress?: (progress: number, bytesDownloaded: number, totalBytes: number) => void,
  ): Promise<number | null> {
    let received = 0;
    let declaredTotal = 0;
    let enqueue: ((chunk: Uint8Array) => void) | null = null;
    let closeStream: (() => void) | null = null;
    let errorStream: ((err: unknown) => void) | null = null;

    const body: ReadableStream<Uint8Array> = new ReadableStream({
      start(controller) {
        enqueue = (chunk) => controller.enqueue(chunk);
        closeStream = () => controller.close();
        errorStream = (err) => controller.error(err);
      },
    });

    const pump = http.stream({ url }, (chunk, totalWritten, contentLength) => {
      if (enqueue) enqueue(chunk);
      received = totalWritten;
      if (contentLength > 0) declaredTotal = contentLength;
      onProgress?.(declaredTotal > 0 ? received / declaredTotal : 0, received, declaredTotal);
    }).then(() => {
      closeStream?.();
    }, (err) => {
      errorStream?.(err);
    });

    try {
      if (this.localFileStorage?.isReady) {
        await this.localFileStorage.saveModelFromStream(storageKey, body);
        await pump;
        logger.info(`Streamed ${storageKey} to local storage via WASM HTTP (${(received / 1024 / 1024).toFixed(1)} MB)`);
        return received;
      }

      await this.storage.saveModelFromStream(storageKey, body);
      await pump;
      logger.info(`Streamed ${storageKey} to OPFS via WASM HTTP (${(received / 1024 / 1024).toFixed(1)} MB)`);
      return received;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warning(`WASM-backed streaming store failed for "${storageKey}": ${msg}, will fall back to buffered download`);
      return null;
    }
  }

  /** Store data, preferring local filesystem when available, then OPFS, then memory cache. */
  async storeInOPFS(key: string, data: Uint8Array): Promise<void> {
    const sizeMB = (data.length / 1024 / 1024).toFixed(1);

    // Try local filesystem first (permanent, no quota issues)
    if (this.localFileStorage?.isReady) {
      try {
        await this.localFileStorage.saveModel(key, data.buffer as ArrayBuffer);
        logger.info(`Stored ${key} in local storage (${sizeMB} MB)`);
        this.memoryCache.delete(key);
        return;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.warning(`Local storage write failed for "${key}": ${msg}, falling back to OPFS`);
      }
    }

    try {
      // First attempt — OPFS
      await this.storage.saveModel(key, data.buffer as ArrayBuffer);
      logger.info(`Stored ${key} in OPFS (${sizeMB} MB)`);
      this.memoryCache.delete(key);
      return;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const isQuota = msg.toLowerCase().includes('quota');

      if (!isQuota) {
        // Non-quota error — fall back to memory cache directly
        logger.warning(`OPFS store failed for "${key}": ${msg}`);
        logger.info(`Caching "${key}" in memory (${sizeMB} MB) for current session`);
        this.memoryCache.set(key, data);
        return;
      }

      // Quota exceeded — try to evict old models and retry
      logger.warning(`OPFS quota exceeded for "${key}" (${sizeMB} MB), evicting old models...`);
      await this.evictOPFSModels(key, data.length);
    }

    // Retry after eviction
    try {
      await this.storage.saveModel(key, data.buffer as ArrayBuffer);
      logger.info(`Stored ${key} in OPFS after eviction (${sizeMB} MB)`);
      this.memoryCache.delete(key);
    } catch (retryErr) {
      const retryMsg = retryErr instanceof Error ? retryErr.message : String(retryErr);
      logger.warning(`OPFS store still failed after eviction for "${key}": ${retryMsg}`);
      logger.info(`Caching "${key}" in memory (${sizeMB} MB) for current session`);
      this.memoryCache.set(key, data);
    }
  }

  /**
   * Evict old models from OPFS to free space for a new model.
   * Deletes models sorted by oldest-first until enough space is freed,
   * skipping the model being stored AND any sibling files that belong
   * to the same model (e.g. main model file and its mmproj companion).
   *
   * Sibling detection: files are siblings if one key is a prefix of
   * the other, separated by "__" (e.g. "modelA" and "modelA__mmproj-...").
   */
  private async evictOPFSModels(keepKey: string, neededBytes: number): Promise<void> {
    const stored = await this.storage.listModels();
    if (stored.length === 0) return;

    // Extract the base model ID (everything before the first "__" separator).
    // This links companion files: "modelA__mmproj-..." → base "modelA".
    const keepBase = keepKey.split('__')[0];

    // Sort by oldest first (least recently modified)
    stored.sort((a, b) => a.lastModified - b.lastModified);

    let freedBytes = 0;
    for (const model of stored) {
      // Never evict the file we're about to store
      if (model.id === keepKey) continue;

      // Never evict internal metadata files
      if (model.id === '_metadata.json') continue;

      // Never evict sibling files that belong to the same model.
      // A stored file is a sibling if its base (before "__") matches keepBase,
      // or if keepBase starts with the stored file's ID (the stored file IS
      // the main model and we're storing a companion like mmproj).
      const storedBase = model.id.split('__')[0];
      if (storedBase === keepBase) continue;

      const sizeMBEvict = (model.sizeBytes / 1024 / 1024).toFixed(1);
      logger.info(`Evicting "${model.id}" (${sizeMBEvict} MB) from OPFS`);
      await this.storage.deleteModel(model.id);

      // Also update registry status if this model is registered
      const registered = this.registry.getModel(model.id);
      if (registered && registered.status === ModelStatus.Downloaded) {
        this.registry.updateModel(model.id, { status: ModelStatus.Registered });
      }

      // Emit event so UI can show a toast notification
      EventBus.shared.emit('model.evicted', SDKEventType.Storage, {
        modelId: model.id,
        modelName: registered?.name ?? model.id,
        freedBytes: model.sizeBytes,
      });

      freedBytes += model.sizeBytes;
      if (freedBytes >= neededBytes) {
        logger.info(`Evicted ${(freedBytes / 1024 / 1024).toFixed(1)} MB, should have room now`);
        break;
      }
    }
  }

  /**
   * Store a file from a ReadableStream, avoiding loading the entire file into memory.
   * Priority: local filesystem > OPFS. Falls back to buffered write if streaming not supported.
   */
  async storeStreamInOPFS(key: string, stream: ReadableStream<Uint8Array>): Promise<void> {
    // Try local filesystem first (permanent, no quota issues)
    if (this.localFileStorage?.isReady) {
      try {
        await this.localFileStorage.saveModelFromStream(key, stream);
        return;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.warning(`Local storage stream write failed for "${key}": ${msg}, falling back to OPFS`);
      }
    }

    try {
      await this.storage.saveModelFromStream(key, stream);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warning(`OPFS stream store failed for "${key}": ${msg}`);
      throw err;
    }
  }

  /** Load data from storage. Priority: local filesystem > OPFS > memory cache. */
  async loadFromOPFS(key: string): Promise<Uint8Array | null> {
    // Try local filesystem first (permanent storage)
    if (this.localFileStorage?.isReady) {
      const localBuffer = await this.localFileStorage.loadModel(key);
      if (localBuffer && localBuffer.byteLength > 0) {
        const sizeMB = localBuffer.byteLength / 1024 / 1024;
        logger.debug(`Loading ${key} from local storage (${sizeMB.toFixed(1)} MB)`);
        return new Uint8Array(localBuffer);
      }
    }

    // Try OPFS (persistent browser storage)
    const buffer = await this.storage.loadModel(key);
    if (buffer && buffer.byteLength > 0) {
      const sizeMB = buffer.byteLength / 1024 / 1024;
      logger.debug(`Loading ${key} from OPFS (${sizeMB.toFixed(1)} MB)`);
      return new Uint8Array(buffer);
    }

    // Clean up corrupted 0-byte OPFS entries
    if (buffer && buffer.byteLength === 0) {
      logger.warning(`OPFS entry for "${key}" is 0 bytes (corrupted), deleting`);
      await this.deleteFromOPFS(key);
    }

    // Fall back to in-memory cache (populated when OPFS store failed, e.g. quota exceeded).
    // IMPORTANT: Do NOT delete from cache here — the model may be unloaded and
    // reloaded later (switching between models). Memory cache entries are only
    // cleared on explicit model deletion via deleteFromOPFS().
    const cached = this.memoryCache.get(key);
    if (cached) {
      const sizeMB = cached.length / 1024 / 1024;
      logger.debug(`Loading ${key} from memory cache (${sizeMB.toFixed(1)} MB) — not persisted to OPFS`);
      return cached;
    }

    return null;
  }

  /** Load data from storage as a ReadableStream. Priority: local filesystem > OPFS > memory cache. */
  async loadStreamFromOPFS(key: string): Promise<ReadableStream<Uint8Array> | null> {
    // Try local filesystem first
    if (this.localFileStorage?.isReady) {
      const localStream = await this.localFileStorage.loadModelStream(key);
      if (localStream) {
        logger.debug(`Loading ${key} stream from local storage`);
        return localStream;
      }
    }

    // Try OPFS
    const opfsStream = await this.storage.loadModelStream(key);
    if (opfsStream) {
      logger.debug(`Loading ${key} stream from OPFS`);
      return opfsStream;
    }

    // Fall back to in-memory cache
    const cached = this.memoryCache.get(key);
    if (cached) {
      const sizeMB = cached.length / 1024 / 1024;
      logger.debug(`Loading ${key} stream from memory cache (${sizeMB.toFixed(1)} MB)`);
      return new ReadableStream({
        start(controller) {
          controller.enqueue(cached);
          controller.close();
        }
      });
    }

    return null;
  }

  /** Load file object from storage (local FS or OPFS) without reading into memory. */
  async loadModelFile(key: string): Promise<File | null> {
    // Try local filesystem first
    if (this.localFileStorage?.isReady) {
      const file = await this.localFileStorage.loadModelFile(key);
      if (file) return file;
    }

    // Try OPFS
    return this.storage.loadModelFile(key);
  }

  /** Check existence in local storage, OPFS, or in-memory cache. */
  async existsInOPFS(key: string): Promise<boolean> {
    if (this.localFileStorage?.isReady) {
      const localExists = await this.localFileStorage.hasModel(key);
      if (localExists) return true;
    }
    if (this.memoryCache.has(key)) return true;
    return this.storage.hasModel(key);
  }

  /** Check if data exists in actual OPFS storage (NOT memory cache). */
  async existsInActualOPFS(key: string): Promise<boolean> {
    return this.storage.hasModel(key);
  }

  /** Delete from all storage backends (local filesystem, OPFS, memory cache). */
  async deleteFromOPFS(key: string): Promise<void> {
    this.memoryCache.delete(key);
    if (this.localFileStorage?.isReady) {
      await this.localFileStorage.deleteModel(key);
    }
    await this.storage.deleteModel(key);
  }

  /** Get file size from storage without reading into memory. */
  async getOPFSFileSize(key: string): Promise<number | null> {
    if (this.localFileStorage?.isReady) {
      const localSize = await this.localFileStorage.getFileSize(key);
      if (localSize !== null) return localSize;
    }
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
    EventBus.shared.emit('model.downloadProgress', SDKEventType.Model, {
      modelId: progress.modelId,
      progress: progress.progress,
      bytesDownloaded: progress.bytesDownloaded,
      totalBytes: progress.totalBytes,
      stage: progress.stage as string | undefined,
    });
  }
}
