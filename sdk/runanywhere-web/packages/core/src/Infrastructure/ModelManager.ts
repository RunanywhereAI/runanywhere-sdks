/**
 * Model Manager - Thin orchestrator for model lifecycle
 *
 * Composes ModelRegistry (catalog) + ModelDownloader (downloads) and adds
 * model-loading orchestration (STT / TTS / LLM / VLM routing).
 *
 * Backend-specific logic (writing to sherpa-onnx FS, extracting archives,
 * creating recognizer configs) is handled by the pluggable loader interfaces.
 * This keeps ModelManager backend-agnostic — it only depends on core types.
 */

import { EventBus } from '../Foundation/EventBus';
import { SDKLogger } from '../Foundation/SDKLogger';
import { ModelCategory, LLMFramework, ModelStatus, DownloadStage, SDKEventType } from '../types/enums';
import type { LLMModelLoader, STTModelLoader, TTSModelLoader, VADModelLoader, ModelLoadContext } from './ModelLoaderTypes';
import { OPFSStorage } from './OPFSStorage';
import type { MetadataMap } from './OPFSStorage';
import { ModelRegistry } from './ModelRegistry';
import { ModelDownloader } from './ModelDownloader';
import { inferModelFromFilename, sanitizeId } from './ModelFileInference';
import type {
  ManagedModel,
  CompactModelDef,
  DownloadProgress,
  ModelFileDescriptor,
  ModelChangeCallback,
  ArtifactType,
} from './ModelRegistry';

// Re-export types so existing imports from './Infrastructure/ModelManager' still work
export { ModelCategory, LLMFramework, ModelStatus, DownloadStage };
export type { ManagedModel, CompactModelDef, DownloadProgress, ModelFileDescriptor, ArtifactType };

// ---------------------------------------------------------------------------
// VLM Loader Interface (pluggable by the app)
// ---------------------------------------------------------------------------

/** Parameters for loading a VLM model in a dedicated worker. */
export interface VLMLoadParams {
  modelOpfsKey: string;
  modelFilename: string;
  mmprojOpfsKey: string;
  mmprojFilename: string;
  modelId: string;
  modelName: string;
  modelData?: ArrayBuffer;
  mmprojData?: ArrayBuffer;
}

/**
 * Interface for VLM (vision-language model) loading.
 * The app provides an implementation (typically backed by a Web Worker)
 * via `ModelManager.setVLMLoader()`.
 */
export interface VLMLoader {
  init(): Promise<void>;
  readonly isInitialized: boolean;
  loadModel(params: VLMLoadParams): Promise<void>;
  unloadModel(): Promise<void>;
}

// ---------------------------------------------------------------------------
// Model Manager Singleton
// ---------------------------------------------------------------------------

const logger = new SDKLogger('ModelManager');

class ModelManagerImpl {
  private readonly registry = new ModelRegistry();
  private readonly storage = new OPFSStorage();
  private readonly downloader: ModelDownloader;

  /**
   * Tracks loaded models per category — allows STT + LLM + TTS simultaneously
   * for the voice pipeline. Key = ModelCategory, Value = model id.
   */
  private loadedByCategory: Map<ModelCategory, string> = new Map();

  /** LRU metadata: lastUsedAt timestamps persisted in OPFS */
  private metadata: MetadataMap = {};

  /** Pluggable VLM loader (set by the app via setVLMLoader) */
  private vlmLoader: VLMLoader | null = null;

  /** Pluggable model loaders — registered by backend providers */
  private llmLoader: LLMModelLoader | null = null;
  private sttLoader: STTModelLoader | null = null;
  private ttsLoader: TTSModelLoader | null = null;
  private vadLoader: VADModelLoader | null = null;

  constructor() {
    this.downloader = new ModelDownloader(this.registry, this.storage);
    this.initStorage();
    this.requestPersistentStorage();
  }

  private async initStorage(): Promise<void> {
    await this.storage.initialize();
  }

  // --- Registration API ---

  registerModels(models: CompactModelDef[]): void {
    this.registry.registerModels(models);
    this.refreshDownloadStatus();
  }

  setVLMLoader(loader: VLMLoader): void {
    this.vlmLoader = loader;
  }

  setLLMLoader(loader: LLMModelLoader): void { this.llmLoader = loader; }
  setSTTLoader(loader: STTModelLoader): void { this.sttLoader = loader; }
  setTTSLoader(loader: TTSModelLoader): void { this.ttsLoader = loader; }
  setVADLoader(loader: VADModelLoader): void { this.vadLoader = loader; }

  /** Expose the downloader for backend packages that need file operations. */
  getDownloader(): ModelDownloader { return this.downloader; }

  /** Set the local file storage backend for persistent model storage. */
  setLocalFileStorage(storage: import('./LocalFileStorage').LocalFileStorage): void {
    this.downloader.setLocalFileStorage(storage);
  }

  // --- Internal init ---

  private async requestPersistentStorage(): Promise<void> {
    try {
      if (navigator.storage?.persist) {
        const persisted = await navigator.storage.persist();
        if (persisted) {
          logger.info('Persistent storage: granted');
        } else {
          logger.debug('Persistent storage: denied (expected on first visit)');
        }
      }
    } catch {
      // Not supported or denied
    }
  }

  private async refreshDownloadStatus(): Promise<void> {
    // Ensure OPFS is initialized before checking for previously downloaded models.
    // initStorage() is idempotent — returns immediately if already done.
    await this.storage.initialize();

    this.metadata = await this.storage.loadMetadata();

    for (const model of this.registry.getModels()) {
      if (model.status !== ModelStatus.Registered) continue;
      try {
        const size = await this.downloader.getOPFSFileSize(model.id);
        if (size !== null && size > 0) {
          this.registry.updateModel(model.id, { status: ModelStatus.Downloaded, sizeBytes: size });

          if (!this.metadata[model.id]) {
            const stored = await this.storage.listModels();
            const entry = stored.find((s) => s.id === model.id);
            this.metadata[model.id] = {
              lastUsedAt: entry?.lastModified ?? Date.now(),
              sizeBytes: size,
            };
          }
        }
      } catch {
        // Not in OPFS, keep as registered
      }
    }

    await this.storage.saveMetadata(this.metadata);
  }

  // --- Queries ---

  getModels(): ManagedModel[] { return this.registry.getModels(); }
  getModelsByCategory(category: ModelCategory): ManagedModel[] { return this.registry.getModelsByCategory(category); }
  getModelsByFramework(framework: LLMFramework): ManagedModel[] { return this.registry.getModelsByFramework(framework); }
  getLLMModels(): ManagedModel[] { return this.registry.getLLMModels(); }
  getVLMModels(): ManagedModel[] { return this.registry.getVLMModels(); }
  getSTTModels(): ManagedModel[] { return this.registry.getSTTModels(); }
  getTTSModels(): ManagedModel[] { return this.registry.getTTSModels(); }
  getVADModels(): ManagedModel[] { return this.registry.getVADModels(); }

  getLoadedModel(category?: ModelCategory): ManagedModel | null {
    if (category) {
      const id = this.loadedByCategory.get(category);
      return id ? this.registry.getModel(id) ?? null : null;
    }
    return this.registry.getModels().find((m) => m.status === ModelStatus.Loaded) ?? null;
  }

  getLoadedModelId(category?: ModelCategory): string | null {
    if (category) {
      return this.loadedByCategory.get(category) ?? null;
    }
    return this.registry.getModels().find((m) => m.status === ModelStatus.Loaded)?.id ?? null;
  }

  areAllLoaded(categories: ModelCategory[]): boolean {
    return categories.every((c) => this.loadedByCategory.has(c));
  }

  async ensureLoaded(category: ModelCategory, options?: { coexist?: boolean }): Promise<ManagedModel | null> {
    const loaded = this.getLoadedModel(category);
    if (loaded) return loaded;

    const models = this.getModels();
    const downloaded = models.find(
      m => m.modality === category && m.status === ModelStatus.Downloaded
    );
    if (!downloaded) return null;

    await this.loadModel(downloaded.id, options);
    return this.getLoadedModel(category);
  }

  // --- Download ---

  async checkDownloadFit(modelId: string): Promise<import('./ModelDownloader').QuotaCheckResult> {
    const model = this.registry.getModel(modelId);
    if (!model) return { fits: true, availableBytes: 0, neededBytes: 0, evictionCandidates: [] };

    const loadedId = this.loadedByCategory.get(model.modality ?? ModelCategory.Language);
    return this.downloader.checkStorageQuota(model, this.metadata, loadedId ?? undefined);
  }

  async downloadModel(modelId: string): Promise<void> {
    return this.downloader.downloadModel(modelId);
  }

  // --- Model Import (file picker / drag-drop) ---

  /**
   * Import a model from a user-provided File (via picker or drag-and-drop).
   * Stores the file in the active storage backend and registers it as downloaded.
   * If the model isn't already in the catalog, auto-registers it based on filename.
   *
   * @param file - The File object from file picker or drag-drop
   * @param modelId - Optional: associate with an existing registered model
   * @returns The model ID (existing or auto-generated)
   */
  async importModel(file: File, modelId?: string): Promise<string> {
    let id = modelId ?? sanitizeId(file.name.replace(/\.[^.]+$/, ''));

    // Auto-register if not in the catalog
    if (!this.registry.getModel(id)) {
      const meta = inferModelFromFilename(file.name);
      this.registry.addModel({
        id: meta.id,
        name: meta.name,
        url: '',
        modality: meta.category,
        framework: meta.framework,
        status: ModelStatus.Registered,
      });
      // Use the inferred ID if different
      id = meta.id;
    }

    logger.info(`Importing model from file: ${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB) -> ${id}`);

    // Stream the file directly to storage to avoid loading the entire file into memory.
    // file.stream() returns a ReadableStream<Uint8Array> in modern browsers.
    if (typeof file.stream === 'function') {
      await this.downloader.storeStreamInOPFS(id, file.stream());
    } else {
      // Fallback for older browsers: buffer the entire file
      const data = new Uint8Array(await file.arrayBuffer());
      await this.downloader.storeInOPFS(id, data);
    }

    // Use file.size (already known) instead of data.length to avoid extra reference
    const sizeBytes = file.size;

    this.registry.updateModel(id, {
      status: ModelStatus.Downloaded,
      sizeBytes,
    });

    this.touchLastUsed(id, sizeBytes);

    EventBus.shared.emit('model.imported', SDKEventType.Model, {
      modelId: id,
      filename: file.name,
      sizeBytes,
    });

    logger.info(`Model imported: ${id} (${(sizeBytes / 1024 / 1024).toFixed(1)} MB)`);
    return id;
  }

  // --- Model loading orchestration ---

  async loadModel(modelId: string, options?: { coexist?: boolean }): Promise<boolean> {
    const model = this.registry.getModel(modelId);
    if (!model || (model.status !== ModelStatus.Downloaded && model.status !== ModelStatus.Registered)) return false;

    const category = model.modality ?? ModelCategory.Language;

    if (options?.coexist) {
      const currentId = this.loadedByCategory.get(category);
      if (currentId && currentId !== modelId) {
        logger.info(`Swapping ${category} model: ${currentId} → ${modelId}`);
        await this.unloadModelByCategory(category);
      }
    } else {
      await this.unloadAll(modelId);
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Loading });
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, category });

    try {
      if (model.modality === ModelCategory.Multimodal) {
        await this.loadVLMModel(model, modelId);
      } else if (model.modality === ModelCategory.SpeechRecognition) {
        const data = await this.downloader.loadFromOPFS(modelId);
        if (!data) throw new Error('Model not downloaded — please download the model first.');
        await this.loadSTTModel(model, data);
      } else if (model.modality === ModelCategory.SpeechSynthesis) {
        const data = await this.downloader.loadFromOPFS(modelId);
        if (!data) throw new Error('Model not downloaded — please download the model first.');
        await this.loadTTSModel(model, data);
      } else if (model.modality === ModelCategory.Audio) {
        const data = await this.downloader.loadFromOPFS(modelId);
        if (!data) throw new Error('Model not downloaded — please download the model first.');
        await this.loadVADModel(model, data);
      } else {
        // Try to get the File object directly (WORKERFS path) to avoid loading into memory
        const file = await this.downloader.loadModelFile(modelId);
        let dataStream: ReadableStream<Uint8Array> | undefined;
        let data: Uint8Array | undefined;

        if (!file) {
          // Try streaming
          dataStream = await this.downloader.loadStreamFromOPFS(modelId) ?? undefined;

          if (!dataStream) {
            // Fallback to legacy buffering
            data = await this.downloader.loadFromOPFS(modelId) ?? undefined;
          }
        }

        if (!file && !dataStream && !data) throw new Error('Model not downloaded — please download the model first.');

        await this.loadLLMModel(model, modelId, data, dataStream, file ?? undefined);
      }

      this.loadedByCategory.set(category, modelId);
      this.registry.updateModel(modelId, { status: ModelStatus.Loaded });
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, category });

      this.touchLastUsed(modelId, model.sizeBytes ?? 0);

      return true;
    } catch (err) {
      const message = err instanceof Error
        ? err.message
        : (typeof err === 'object' ? JSON.stringify(err) : String(err));
      logger.error(`Failed to load model ${modelId}: ${message}`);
      this.registry.updateModel(modelId, { status: ModelStatus.Error, error: message });
      EventBus.shared.emit('model.loadFailed', SDKEventType.Model, { modelId, error: message });
      return false;
    }
  }

  async unloadModel(modelId: string): Promise<void> {
    const model = this.registry.getModel(modelId);
    if (!model) return;
    const category = model.modality ?? ModelCategory.Language;
    await this.unloadModelByCategory(category);
  }

  async unloadAll(exceptModelId?: string): Promise<void> {
    const loaded = [...this.loadedByCategory.entries()];
    if (loaded.length === 0) return;

    for (const [category, loadedId] of loaded) {
      if (exceptModelId && loadedId === exceptModelId) continue;
      logger.info(`Unloading ${category} model (${loadedId}) — freeing resources`);
      await this.unloadModelByCategory(category);
    }
  }

  async deleteModel(modelId: string): Promise<void> {
    for (const [category, id] of this.loadedByCategory) {
      if (id === modelId) {
        this.loadedByCategory.delete(category);
        break;
      }
    }

    await this.downloader.deleteFromOPFS(modelId);

    const model = this.registry.getModel(modelId);
    if (model?.additionalFiles) {
      for (const file of model.additionalFiles) {
        await this.downloader.deleteFromOPFS(this.downloader.additionalFileKey(modelId, file.filename));
      }
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Registered, downloadProgress: undefined, sizeBytes: undefined });
    this.removeMetadata(modelId);
  }

  async clearAll(): Promise<void> {
    await this.storage.clearAll();
    this.metadata = {};
    this.loadedByCategory.clear();
    for (const model of this.registry.getModels()) {
      if (model.status !== ModelStatus.Registered) {
        this.registry.updateModel(model.id, {
          status: ModelStatus.Registered,
          downloadProgress: undefined,
          sizeBytes: undefined,
        });
      }
    }
  }

  async getStorageInfo(): Promise<{ modelCount: number; totalSize: number; available: number }> {
    let modelCount = 0;
    let totalSize = 0;
    try {
      const root = await navigator.storage.getDirectory();
      const modelsDir = await root.getDirectoryHandle('models');
      const dir = modelsDir as FileSystemDirectoryHandle & { entries(): AsyncIterableIterator<[string, FileSystemFileHandle | FileSystemDirectoryHandle]> };
      for await (const [name, handle] of dir.entries()) {
        if (handle.kind === 'file' && !name.startsWith('_')) {
          modelCount++;
          const file = await (handle as FileSystemFileHandle).getFile();
          totalSize += file.size;
        }
      }
    } catch {
      // OPFS may not exist yet
    }

    let available = 0;
    try {
      const estimate = await navigator.storage.estimate();
      available = (estimate.quota ?? 0) - (estimate.usage ?? 0);
    } catch {
      // storage API may not be available
    }

    return { modelCount, totalSize, available };
  }

  // --- LRU Metadata ---

  getModelLastUsedAt(modelId: string): number {
    return this.metadata[modelId]?.lastUsedAt ?? 0;
  }

  private touchLastUsed(modelId: string, sizeBytes: number): void {
    this.metadata[modelId] = { lastUsedAt: Date.now(), sizeBytes };
    this.storage.saveMetadata(this.metadata).catch(() => { /* non-critical */ });
  }

  private removeMetadata(modelId: string): void {
    delete this.metadata[modelId];
    this.storage.saveMetadata(this.metadata).catch(() => { /* non-critical */ });
  }

  // --- Subscriptions ---

  onChange(callback: ModelChangeCallback): () => void {
    return this.registry.onChange(callback);
  }

  // ---------------------------------------------------------------------------
  // Private — model loading by modality
  // ---------------------------------------------------------------------------

  /**
   * Build a ModelLoadContext for passing to backend loaders.
   */
  private buildLoadContext(model: ManagedModel, data?: Uint8Array, dataStream?: ReadableStream<Uint8Array>, file?: File): ModelLoadContext {
    return {
      model,
      data,
      dataStream,
      file,
      downloadFile: (url: string) => this.downloader.downloadFile(url),
      loadFile: (fileKey: string) => this.downloader.loadFromOPFS(fileKey),
      storeFile: (fileKey: string, fileData: Uint8Array) => this.downloader.storeInOPFS(fileKey, fileData),
      additionalFileKey: (modelId: string, filename: string) => this.downloader.additionalFileKey(modelId, filename),
    };
  }

  /**
   * Load an LLM model via the pluggable loader.
   * The loader (in @runanywhere/web-llamacpp) handles writing to its own
   * Emscripten FS and calling the C API.
   */
  private async loadLLMModel(model: ManagedModel, _modelId: string, data?: Uint8Array, dataStream?: ReadableStream<Uint8Array>, file?: File): Promise<void> {
    if (!this.llmLoader) throw new Error('No LLM loader registered. Register the @runanywhere/web-llamacpp package.');
    const ctx = this.buildLoadContext(model, data, dataStream, file);
    await this.llmLoader.loadModelFromData(ctx);
    logger.info(`LLM model loaded: ${model.id}`);
  }

  /**
   * Load a VLM (vision-language) model via the pluggable VLM loader.
   */
  private async loadVLMModel(model: ManagedModel, modelId: string): Promise<void> {
    const exists = await this.downloader.existsInOPFS(modelId);
    if (!exists) {
      throw new Error('Model not downloaded — please download the model first.');
    }

    const mmprojFile = model.additionalFiles?.find((f) => f.filename.includes('mmproj'));
    if (!mmprojFile) {
      // No mmproj — load as text-only LLM
      logger.warning(`No mmproj found, loading as text-only LLM: ${modelId}`);

      const file = await this.downloader.loadModelFile(modelId);
      let dataStream: ReadableStream<Uint8Array> | undefined;
      let data: Uint8Array | undefined;

      if (!file) {
        dataStream = await this.downloader.loadStreamFromOPFS(modelId) ?? undefined;
        if (!dataStream) data = await this.downloader.loadFromOPFS(modelId) ?? undefined;
      }

      if (!file && !dataStream && !data) throw new Error('Model not downloaded.');
      await this.loadLLMModel(model, modelId, data, dataStream, file ?? undefined);
      return;
    }

    // Ensure mmproj is available
    const mmprojKey = this.downloader.additionalFileKey(modelId, mmprojFile.filename);
    const mmprojExists = await this.downloader.existsInOPFS(mmprojKey);
    if (!mmprojExists && mmprojFile.url) {
      logger.debug(`mmproj not in storage, downloading on-demand: ${mmprojFile.filename}`);
      const mmprojDownload = await this.downloader.downloadFile(mmprojFile.url);
      await this.downloader.storeInOPFS(mmprojKey, mmprojDownload);
    }

    if (!this.vlmLoader) {
      throw new Error('No VLM loader registered. Call ModelManager.setVLMLoader() first.');
    }

    if (!this.vlmLoader.isInitialized) {
      logger.info('Initializing VLM loader...');
      await this.vlmLoader.init();
    }

    // Transfer data to Worker when model is only in memory cache
    let modelDataBuf: ArrayBuffer | undefined;
    let mmprojDataBuf: ArrayBuffer | undefined;

    const modelInOPFS = await this.downloader.existsInActualOPFS(modelId);
    if (!modelInOPFS) {
      const data = await this.downloader.loadFromOPFS(modelId);
      if (data && data.length > 0) {
        modelDataBuf = new ArrayBuffer(data.byteLength);
        new Uint8Array(modelDataBuf).set(data);
        logger.debug(`Transferring model data to VLM Worker (${(data.length / 1024 / 1024).toFixed(1)} MB)`);
      }
    }

    const mmprojInOPFS = await this.downloader.existsInActualOPFS(mmprojKey);
    if (!mmprojInOPFS) {
      const mmprojBytes = await this.downloader.loadFromOPFS(mmprojKey);
      if (mmprojBytes) {
        mmprojDataBuf = new ArrayBuffer(mmprojBytes.byteLength);
        new Uint8Array(mmprojDataBuf).set(mmprojBytes);
        logger.debug(`Transferring mmproj data to VLM Worker (${(mmprojBytes.length / 1024 / 1024).toFixed(1)} MB)`);
      }
    }

    logger.info(`Loading VLM model: ${modelId}`);
    await this.vlmLoader.loadModel({
      modelOpfsKey: modelId,
      modelFilename: `${modelId}.gguf`,
      mmprojOpfsKey: mmprojKey,
      mmprojFilename: mmprojFile.filename,
      modelId,
      modelName: model.name,
      modelData: modelDataBuf,
      mmprojData: mmprojDataBuf,
    });
    logger.info(`VLM model loaded: ${modelId}`);
  }

  /**
   * Load an STT model via the pluggable loader.
   * All sherpa-onnx FS operations are handled by the loader.
   */
  private async loadSTTModel(model: ManagedModel, data: Uint8Array): Promise<void> {
    if (!this.sttLoader) throw new Error('No STT loader registered. Register the @runanywhere/web-onnx package.');
    const ctx = this.buildLoadContext(model, data);
    await this.sttLoader.loadModelFromData(ctx);
    logger.info(`STT model loaded: ${model.id}`);
  }

  /**
   * Load a TTS model via the pluggable loader.
   * All sherpa-onnx FS operations are handled by the loader.
   */
  private async loadTTSModel(model: ManagedModel, data: Uint8Array): Promise<void> {
    if (!this.ttsLoader) throw new Error('No TTS loader registered. Register the @runanywhere/web-onnx package.');
    const ctx = this.buildLoadContext(model, data);
    await this.ttsLoader.loadModelFromData(ctx);
    logger.info(`TTS model loaded: ${model.id}`);
  }

  /**
   * Load a VAD model via the pluggable loader.
   * All sherpa-onnx FS operations are handled by the loader.
   */
  private async loadVADModel(model: ManagedModel, data: Uint8Array): Promise<void> {
    if (!this.vadLoader) throw new Error('No VAD loader registered. Register the @runanywhere/web-onnx package.');
    const ctx = this.buildLoadContext(model, data);
    await this.vadLoader.loadModelFromData(ctx);
    logger.info(`VAD model loaded: ${model.id}`);
  }

  /** Unload the currently loaded model for a specific category */
  private async unloadModelByCategory(category: ModelCategory): Promise<void> {
    const modelId = this.loadedByCategory.get(category);
    if (!modelId) return;

    logger.info(`Unloading ${category} model: ${modelId}`);

    try {
      if (category === ModelCategory.SpeechRecognition) {
        await this.sttLoader?.unloadModel();
      } else if (category === ModelCategory.SpeechSynthesis) {
        await this.ttsLoader?.unloadVoice();
      } else if (category === ModelCategory.Audio) {
        this.vadLoader?.cleanup();
      } else if (category === ModelCategory.Multimodal) {
        await this.vlmLoader?.unloadModel();
      } else {
        // LLM: delegate unload + FS cleanup to the backend loader
        if (this.llmLoader?.unloadAndCleanup) {
          await this.llmLoader.unloadAndCleanup(modelId);
        } else {
          await this.llmLoader?.unloadModel();
        }
      }
    } catch (err) {
      logger.warning(`Error during unload of ${modelId}: ${err instanceof Error ? err.message : String(err)}`);
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Downloaded });
    this.loadedByCategory.delete(category);
    EventBus.shared.emit('model.unloaded', SDKEventType.Model, { modelId, category });
  }
}

export const ModelManager = new ModelManagerImpl();
