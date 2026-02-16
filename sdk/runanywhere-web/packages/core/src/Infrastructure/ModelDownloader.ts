/**
 * Model Downloader - Download orchestration with OPFS persistence
 *
 * Handles single-file and multi-file model downloads with progress tracking.
 * Delegates all OPFS storage operations to the enhanced OPFSStorage class.
 * Extracted from ModelManager to separate download concerns from load/catalog logic.
 */

import { EventBus } from '../Foundation/EventBus';
import { SDKLogger } from '../Foundation/SDKLogger';
import { OPFSStorage } from './OPFSStorage';
import type { MetadataMap } from './OPFSStorage';
import type { LocalFileStorage } from './LocalFileStorage';
import { ModelStatus, DownloadStage, SDKEventType } from '../types/enums';
import type { ManagedModel, DownloadProgress } from './ModelRegistry';
import type { ModelRegistry } from './ModelRegistry';

// ---------------------------------------------------------------------------
// Quota Check Result
// ---------------------------------------------------------------------------

/** Candidate model that could be evicted to free space. */
export interface EvictionCandidateInfo {
  id: string;
  name: string;
  sizeBytes: number;
  lastUsedAt: number;
}

/** Result of a pre-download quota check. */
export interface QuotaCheckResult {
  /** Whether the model fits in available storage without eviction. */
  fits: boolean;
  /** Currently available bytes (estimate). */
  availableBytes: number;
  /** Total bytes needed for the model (primary + additional files). */
  neededBytes: number;
  /**
   * Models that could be evicted to free space, sorted by lastUsedAt ascending
   * (least recently used first). Only populated when `fits` is false.
   */
  evictionCandidates: EvictionCandidateInfo[];
}

// ---------------------------------------------------------------------------
// Model Downloader
// ---------------------------------------------------------------------------

/**
 * Validate that a URL is safe to fetch from.
 *
 * Security: Prevents SSRF-like attacks where user-controlled model URLs
 * could be pointed at internal/private network addresses. Only HTTPS is
 * allowed in production. HTTP is permitted for localhost during development.
 *
 * @param url - The URL to validate
 * @throws Error if the URL is not allowed
 */
function validateModelUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`Invalid model URL: ${url}`);
  }

  // Only allow HTTPS (and HTTP for localhost during development)
  const isLocalhost =
    parsed.hostname === 'localhost' ||
    parsed.hostname === '127.0.0.1' ||
    parsed.hostname === '[::1]';

  if (parsed.protocol === 'http:' && !isLocalhost) {
    throw new Error(
      `Model URL must use HTTPS (got HTTP for ${parsed.hostname}). ` +
      'HTTP is only allowed for localhost during development.',
    );
  }

  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new Error(`Model URL has unsupported protocol: ${parsed.protocol}`);
  }

  // Block common private/internal network ranges
  const blockedPatterns = [
    /^10\./,
    /^172\.(1[6-9]|2\d|3[0-1])\./,
    /^192\.168\./,
    /^169\.254\./,
    /^0\./,
  ];

  if (!isLocalhost) {
    for (const pattern of blockedPatterns) {
      if (pattern.test(parsed.hostname)) {
        throw new Error(`Model URL points to private network address: ${parsed.hostname}`);
      }
    }
  }
}

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
    const { usedBytes, quotaBytes } = await this.storage.getStorageUsage();
    const availableBytes = Math.max(0, quotaBytes - usedBytes);

    // Estimate total download size
    const neededBytes = model.memoryRequirement ?? 0;

    if (availableBytes >= neededBytes) {
      return { fits: true, availableBytes, neededBytes, evictionCandidates: [] };
    }

    // Not enough space — build eviction candidate list
    const stored = await this.storage.listModels();
    const keepBase = model.id.split('__')[0];

    const candidates: EvictionCandidateInfo[] = [];
    for (const s of stored) {
      // Skip the model being downloaded and its siblings
      const storedBase = s.id.split('__')[0];
      if (storedBase === keepBase) continue;
      // Skip currently loaded model
      if (loadedModelId && s.id === loadedModelId) continue;
      // Skip metadata file
      if (s.id === '_metadata.json') continue;

      const registered = this.registry.getModel(s.id) ?? this.registry.getModel(storedBase);
      candidates.push({
        id: storedBase,
        name: registered?.name ?? s.id,
        sizeBytes: s.sizeBytes,
        lastUsedAt: metadata[storedBase]?.lastUsedAt ?? s.lastModified,
      });
    }

    // Deduplicate by base id (main model + companion files combined)
    const deduped = new Map<string, EvictionCandidateInfo>();
    for (const c of candidates) {
      const existing = deduped.get(c.id);
      if (existing) {
        existing.sizeBytes += c.sizeBytes;
      } else {
        deduped.set(c.id, { ...c });
      }
    }

    // Sort by least-recently-used first
    const sorted = [...deduped.values()].sort((a, b) => a.lastUsedAt - b.lastUsedAt);

    return { fits: false, availableBytes, neededBytes, evictionCandidates: sorted };
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
   *
   * URLs are validated before fetching to prevent SSRF and enforce HTTPS.
   */
  async downloadFile(
    url: string,
    onProgress?: (progress: number, bytesDownloaded: number, totalBytes: number) => void,
  ): Promise<Uint8Array> {
    validateModelUrl(url);
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
