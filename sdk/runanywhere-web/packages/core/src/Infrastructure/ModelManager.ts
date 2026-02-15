/**
 * Model Manager - Thin orchestrator for model lifecycle
 *
 * Composes ModelRegistry (catalog) + ModelDownloader (downloads) and adds
 * model-loading orchestration (STT / TTS / LLM / VLM routing).
 *
 * The public API is unchanged — `ModelManager` is still a singleton that
 * exposes `registerModels()`, `downloadModel()`, `loadModel()`, `onChange()`, etc.
 * Internally it delegates catalog operations to the Registry and download
 * operations to the Downloader.
 */

import { WASMBridge } from '../Foundation/WASMBridge';
import { SherpaONNXBridge } from '../Foundation/SherpaONNXBridge';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger } from '../Foundation/SDKLogger';
import { STTModelType } from '../Public/Extensions/STTTypes';
import { ModelCategory, LLMFramework, ModelStatus, DownloadStage, SDKEventType } from '../types/enums';
import type { LLMModelLoader, STTModelLoader, TTSModelLoader, VADModelLoader } from './ModelLoaderTypes';
import { OPFSStorage } from './OPFSStorage';
import type { MetadataMap } from './OPFSStorage';
import { ModelRegistry } from './ModelRegistry';
import { ModelDownloader } from './ModelDownloader';
import { extractTarGz } from './ArchiveUtility';
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
  /**
   * Optional: raw model data to transfer to the Worker when OPFS doesn't
   * have the file (memory-cache fallback for quota-exceeded scenarios).
   * Transferred via postMessage (zero-copy).
   */
  modelData?: ArrayBuffer;
  /** Optional: raw mmproj data (same fallback). */
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

  /** Pluggable model loaders — registered by the Public layer during init */
  private llmLoader: LLMModelLoader | null = null;
  private sttLoader: STTModelLoader | null = null;
  private ttsLoader: TTSModelLoader | null = null;
  private vadLoader: VADModelLoader | null = null;

  constructor() {
    this.downloader = new ModelDownloader(this.registry, this.storage);
    // Initialize OPFS storage (non-blocking)
    this.initStorage();
    // Request persistent storage so browser won't evict our cached models
    this.requestPersistentStorage();
  }

  private async initStorage(): Promise<void> {
    await this.storage.initialize();
  }

  // --- Registration API (called by the app) ---

  /**
   * Register a catalog of models. Resolves compact definitions into full
   * ManagedModel entries and checks OPFS for previously downloaded files.
   */
  registerModels(models: CompactModelDef[]): void {
    this.registry.registerModels(models);
    // Check OPFS for previously downloaded models (async, updates status when done)
    this.refreshDownloadStatus();
  }

  /**
   * Set the VLM loader implementation. Called by the app to plug in
   * worker-based VLM loading (the SDK doesn't create Web Workers directly).
   */
  setVLMLoader(loader: VLMLoader): void {
    this.vlmLoader = loader;
  }

  /** Register the LLM model loader (text generation extension). */
  setLLMLoader(loader: LLMModelLoader): void { this.llmLoader = loader; }

  /** Register the STT model loader (speech-to-text extension). */
  setSTTLoader(loader: STTModelLoader): void { this.sttLoader = loader; }

  /** Register the TTS model loader (text-to-speech extension). */
  setTTSLoader(loader: TTSModelLoader): void { this.ttsLoader = loader; }

  /** Register the VAD model loader (voice activity detection extension). */
  setVADLoader(loader: VADModelLoader): void { this.vadLoader = loader; }

  // --- Internal init ---

  /** Request persistent storage to prevent browser from evicting cached models */
  private async requestPersistentStorage(): Promise<void> {
    try {
      if (navigator.storage?.persist) {
        const persisted = await navigator.storage.persist();
        logger.info(`Persistent storage: ${persisted ? 'granted' : 'denied'}`);
      }
    } catch {
      // Not supported or denied — non-critical
    }
  }

  /**
   * Check OPFS for models that were downloaded in a previous session.
   * Updates their status from 'registered' to 'downloaded'.
   * Also loads persisted LRU metadata for each model.
   * Only checks file existence + size — does NOT read file contents into memory.
   */
  private async refreshDownloadStatus(): Promise<void> {
    // Load persisted metadata (lastUsedAt timestamps)
    this.metadata = await this.storage.loadMetadata();

    for (const model of this.registry.getModels()) {
      if (model.status !== ModelStatus.Registered) continue;
      try {
        const size = await this.downloader.getOPFSFileSize(model.id);
        if (size !== null && size > 0) {
          this.registry.updateModel(model.id, { status: ModelStatus.Downloaded, sizeBytes: size });

          // Ensure metadata entry exists — use persisted value or fall back to OPFS lastModified
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

    // Persist any newly created metadata entries
    await this.storage.saveMetadata(this.metadata);
  }

  // --- Queries (delegated to registry) ---

  getModels(): ManagedModel[] {
    return this.registry.getModels();
  }

  getModelsByCategory(category: ModelCategory): ManagedModel[] {
    return this.registry.getModelsByCategory(category);
  }

  getModelsByFramework(framework: LLMFramework): ManagedModel[] {
    return this.registry.getModelsByFramework(framework);
  }

  getLLMModels(): ManagedModel[] {
    return this.registry.getLLMModels();
  }

  getVLMModels(): ManagedModel[] {
    return this.registry.getVLMModels();
  }

  getSTTModels(): ManagedModel[] {
    return this.registry.getSTTModels();
  }

  getTTSModels(): ManagedModel[] {
    return this.registry.getTTSModels();
  }

  getVADModels(): ManagedModel[] {
    return this.registry.getVADModels();
  }

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
    // Legacy: return first loaded model id
    return this.registry.getModels().find((m) => m.status === ModelStatus.Loaded)?.id ?? null;
  }

  /** Check if models for all given categories are loaded */
  areAllLoaded(categories: ModelCategory[]): boolean {
    return categories.every((c) => this.loadedByCategory.has(c));
  }

  /**
   * Ensure a model is loaded for the given category.
   * If already loaded, returns the loaded model. If a downloaded model exists,
   * loads it automatically. Returns null if no suitable model is available.
   *
   * @param options.coexist  Forwarded to `loadModel()`. When true, only swaps
   *   models of the same category instead of unloading everything.
   */
  async ensureLoaded(category: ModelCategory, options?: { coexist?: boolean }): Promise<ManagedModel | null> {
    // Check if already loaded
    const loaded = this.getLoadedModel(category);
    if (loaded) return loaded;

    // Find a downloaded model for this category
    const models = this.getModels();
    const downloaded = models.find(
      m => m.modality === category && m.status === ModelStatus.Downloaded
    );
    if (!downloaded) return null;

    // Load it
    await this.loadModel(downloaded.id, options);
    return this.getLoadedModel(category);
  }

  // --- Download (delegated to downloader) ---

  /**
   * Check whether downloading a model will fit in OPFS without eviction.
   * Returns a result indicating whether it fits and which models could be
   * evicted if not. Does NOT perform any mutations.
   */
  async checkDownloadFit(modelId: string): Promise<import('./ModelDownloader').QuotaCheckResult> {
    const model = this.registry.getModel(modelId);
    if (!model) return { fits: true, availableBytes: 0, neededBytes: 0, evictionCandidates: [] };

    // Find the currently loaded model for the same category (excluded from eviction)
    const loadedId = this.loadedByCategory.get(model.modality ?? ModelCategory.Language);
    return this.downloader.checkStorageQuota(model, this.metadata, loadedId ?? undefined);
  }

  async downloadModel(modelId: string): Promise<void> {
    return this.downloader.downloadModel(modelId);
  }

  // --- Model loading orchestration ---

  /**
   * Load a model by ID.
   *
   * @param options.coexist  When `true`, only unload the model of the **same
   *   category** (swap) rather than unloading ALL loaded models. Use this for
   *   multi-model pipelines like Voice (STT + LLM + TTS).
   *   Default is `false` — unloads everything to reclaim memory.
   */
  async loadModel(modelId: string, options?: { coexist?: boolean }): Promise<boolean> {
    const model = this.registry.getModel(modelId);
    if (!model || (model.status !== ModelStatus.Downloaded && model.status !== ModelStatus.Registered)) return false;

    const category = model.modality ?? ModelCategory.Language;

    if (options?.coexist) {
      // Pipeline mode: only unload models of the SAME category (swap).
      // Other categories remain loaded for multi-model workflows.
      const currentId = this.loadedByCategory.get(category);
      if (currentId && currentId !== modelId) {
        logger.info(`Swapping ${category} model: ${currentId} → ${modelId}`);
        await this.unloadModelByCategory(category);
      }
    } else {
      // Default: Unload ALL currently loaded models before loading the new one.
      //
      // In a browser environment, memory is limited (WASM linear memory +
      // WebGPU buffers). The user interacts with one feature at a time
      // (chat, vision, transcribe, etc.), so there's no need to keep models
      // from other categories resident.
      await this.unloadAll(modelId);
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Loading });
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, category });

    try {
      if (model.modality === ModelCategory.Multimodal) {
        // VLM: Worker reads from OPFS directly when possible.
        // When OPFS quota is exceeded, models live only in the main-thread
        // memory cache — we must read and transfer them to the Worker.
        const exists = await this.downloader.existsInOPFS(modelId);
        if (!exists) {
          throw new Error('Model not downloaded — please download the model first.');
        }

        const inActualOPFS = await this.downloader.existsInActualOPFS(modelId);
        if (inActualOPFS) {
          // Worker can read from OPFS directly (optimal: avoids main-thread copy)
          await this.loadLLMModel(model, modelId, new Uint8Array(0));
        } else {
          // Model is in memory cache only (OPFS quota exceeded) — read and transfer to Worker
          logger.debug(`VLM model ${modelId} not in OPFS, reading from memory cache to transfer to Worker`);
          const data = await this.downloader.loadFromOPFS(modelId);
          if (!data) throw new Error('Model not downloaded — please download the model first.');
          await this.loadLLMModel(model, modelId, data);
        }
      } else {
        const data = await this.downloader.loadFromOPFS(modelId);
        if (!data) {
          throw new Error('Model not downloaded — please download the model first.');
        }

        if (model.modality === ModelCategory.SpeechRecognition) {
          await this.loadSTTModel(model, data);
        } else if (model.modality === ModelCategory.SpeechSynthesis) {
          await this.loadTTSModel(model, data);
        } else if (model.modality === ModelCategory.Audio) {
          await this.loadVADModel(model, data);
        } else {
          await this.loadLLMModel(model, modelId, data);
        }
      }

      this.loadedByCategory.set(category, modelId);
      this.registry.updateModel(modelId, { status: ModelStatus.Loaded });
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, category });

      // Update LRU metadata
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

  /**
   * Unload ALL currently loaded models.
   *
   * Called automatically before loading a new model, and can also be called
   * explicitly by app code (e.g. on tab switch) to release all resources.
   *
   * @param exceptModelId - Optional model ID to skip (the model about to be loaded).
   *                        Avoids redundant unload+reload of the same model.
   */
  async unloadAll(exceptModelId?: string): Promise<void> {
    // Snapshot categories to avoid mutation during iteration
    const loaded = [...this.loadedByCategory.entries()];
    if (loaded.length === 0) return;

    for (const [category, loadedId] of loaded) {
      if (exceptModelId && loadedId === exceptModelId) continue;
      logger.info(`Unloading ${category} model (${loadedId}) — freeing resources`);
      await this.unloadModelByCategory(category);
    }
  }

  async deleteModel(modelId: string): Promise<void> {
    // Remove from loaded tracking if this model is loaded
    for (const [category, id] of this.loadedByCategory) {
      if (id === modelId) {
        this.loadedByCategory.delete(category);
        break;
      }
    }

    // Delete primary file
    await this.downloader.deleteFromOPFS(modelId);

    // Delete additional files
    const model = this.registry.getModel(modelId);
    if (model?.additionalFiles) {
      for (const file of model.additionalFiles) {
        await this.downloader.deleteFromOPFS(this.downloader.additionalFileKey(modelId, file.filename));
      }
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Registered, downloadProgress: undefined, sizeBytes: undefined });
    this.removeMetadata(modelId);
  }

  /** Clear all models from OPFS and reset registry statuses. */
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
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      for await (const entry of (modelsDir as any).values()) {
        if (entry.kind === 'file') {
          modelCount++;
          const file = await entry.getFile();
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

  /** Get the last-used timestamp for a model (0 if never recorded). */
  getModelLastUsedAt(modelId: string): number {
    return this.metadata[modelId]?.lastUsedAt ?? 0;
  }

  /** Update lastUsedAt for a model and persist to OPFS (fire-and-forget). */
  private touchLastUsed(modelId: string, sizeBytes: number): void {
    this.metadata[modelId] = { lastUsedAt: Date.now(), sizeBytes };
    // Persist asynchronously — don't block the caller
    this.storage.saveMetadata(this.metadata).catch(() => { /* non-critical */ });
  }

  /** Remove metadata entry when a model is deleted. */
  private removeMetadata(modelId: string): void {
    delete this.metadata[modelId];
    this.storage.saveMetadata(this.metadata).catch(() => { /* non-critical */ });
  }

  // --- Subscriptions (delegated to registry) ---

  onChange(callback: ModelChangeCallback): () => void {
    return this.registry.onChange(callback);
  }

  // ---------------------------------------------------------------------------
  // Private — model loading by modality
  // ---------------------------------------------------------------------------

  /**
   * Load an LLM/VLM model into the RACommons Emscripten FS.
   */
  private async loadLLMModel(model: ManagedModel, modelId: string, data: Uint8Array): Promise<void> {
    const fsDir = `/models`;
    const fsPath = `${fsDir}/${modelId}.gguf`;

    if (model.modality === ModelCategory.Multimodal) {
      // VLM models are loaded in a dedicated Web Worker that reads from OPFS.
    } else {
      // Text-only LLM: write to main-thread Emscripten FS as before
      const bridge = WASMBridge.shared;
      if (!bridge.isLoaded) {
        throw new Error('WASM module not loaded — SDK not initialized.');
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const m = bridge.module as any;

      if (typeof m.FS_createPath !== 'function' || typeof m.FS_createDataFile !== 'function') {
        throw new Error('Emscripten FS helper functions not available on WASM module.');
      }

      m.FS_createPath('/', 'models', true, true);
      try { m.FS_unlink(fsPath); } catch { /* File doesn't exist yet */ }
      logger.debug(`Writing ${data.length} bytes to ${fsPath}`);
      m.FS_createDataFile('/models', `${modelId}.gguf`, data, true, true, true);
      logger.debug(`Model file written to ${fsPath}`);
    }

    if (model.modality === ModelCategory.Multimodal) {
      const mmprojFile = model.additionalFiles?.find((f) => f.filename.includes('mmproj'));
      if (!mmprojFile) {
        logger.warning(`No mmproj found, loading as text-only LLM: ${modelId}`);
        if (!this.llmLoader) throw new Error('No LLM loader registered. Call ModelManager.setLLMLoader() first.');
        await this.llmLoader.loadModel(fsPath, modelId, model.name);
      } else {
        // Ensure mmproj is in OPFS or memory cache (fallback download if missing)
        const mmprojKey = this.downloader.additionalFileKey(modelId, mmprojFile.filename);
        const mmprojExists = await this.downloader.existsInOPFS(mmprojKey);
        if (!mmprojExists && mmprojFile.url) {
          logger.debug(`mmproj not in OPFS, downloading on-demand: ${mmprojFile.filename}`);
          const mmprojDownload = await this.downloader.downloadFile(mmprojFile.url);
          await this.downloader.storeInOPFS(mmprojKey, mmprojDownload);
        }

        if (!this.vlmLoader) {
          throw new Error('No VLM loader registered. Call ModelManager.setVLMLoader() first.');
        }

        // Initialize the Worker (loads its own WASM instance)
        if (!this.vlmLoader.isInitialized) {
          logger.info('Initializing VLM loader...');
          await this.vlmLoader.init();
        }

        // When model/mmproj are only in memory cache (OPFS quota exceeded),
        // we need to read and transfer the data to the Worker.
        let modelDataBuf: ArrayBuffer | undefined;
        let mmprojDataBuf: ArrayBuffer | undefined;

        const modelInOPFS = await this.downloader.existsInActualOPFS(modelId);
        if (!modelInOPFS && data.length > 0) {
          // data was already read from memory cache in the caller
          modelDataBuf = new ArrayBuffer(data.byteLength);
          new Uint8Array(modelDataBuf).set(data);
          logger.debug(`Transferring model data to VLM Worker (${(data.length / 1024 / 1024).toFixed(1)} MB)`);
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

        // Load model via the pluggable VLM loader
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
    } else if (model.modality === ModelCategory.Language) {
      if (!this.llmLoader) throw new Error('No LLM loader registered. Call ModelManager.setLLMLoader() first.');
      await this.llmLoader.loadModel(fsPath, modelId, model.name);
      logger.info(`LLM model loaded via TextGeneration: ${modelId}`);
    }
  }

  /**
   * Load an STT model into sherpa-onnx.
   *
   * Supports two modes:
   *  1. **Archive** (isArchive=true): Download is a .tar.gz that bundles encoder,
   *     decoder, tokens, etc. Matches the Swift SDK approach.
   *  2. **Individual files**: Separate encoder/decoder/tokens downloads.
   */
  private async loadSTTModel(model: ManagedModel, primaryData: Uint8Array): Promise<void> {
    if (!this.sttLoader) throw new Error('No STT loader registered. Call ModelManager.setSTTLoader() first.');

    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${model.id}`;

    if (model.isArchive) {
      await this.loadSTTFromArchive(model, primaryData, sherpa, modelDir);
    } else {
      await this.loadSTTFromIndividualFiles(model, primaryData, sherpa, modelDir);
    }

    logger.info(`STT model loaded via sherpa-onnx: ${model.id}`);
  }

  /**
   * Load an STT model from a .tar.gz archive (matching Swift SDK approach).
   * Extracts encoder, decoder, and tokens from the archive automatically.
   */
  private async loadSTTFromArchive(
    model: ManagedModel,
    archiveData: Uint8Array,
    sherpa: SherpaONNXBridge,
    modelDir: string,
  ): Promise<void> {
    logger.debug(`Extracting STT archive for ${model.id} (${archiveData.length} bytes)...`);

    const entries = await extractTarGz(archiveData);
    logger.debug(`Extracted ${entries.length} files from STT archive`);

    const prefix = this.findArchivePrefix(entries.map(e => e.path));

    // Write all files and auto-discover key paths
    let encoderPath: string | null = null;
    let decoderPath: string | null = null;
    let tokensPath: string | null = null;
    let joinerPath: string | null = null;
    let modelPath: string | null = null;

    for (const entry of entries) {
      const relativePath = prefix ? entry.path.slice(prefix.length) : entry.path;
      const fsPath = `${modelDir}/${relativePath}`;
      sherpa.writeFile(fsPath, entry.data);

      // Auto-discover by filename pattern
      if (relativePath.includes('encoder') && relativePath.endsWith('.onnx')) {
        encoderPath = fsPath;
      } else if (relativePath.includes('decoder') && relativePath.endsWith('.onnx')) {
        decoderPath = fsPath;
      } else if (relativePath.includes('joiner') && relativePath.endsWith('.onnx')) {
        joinerPath = fsPath;
      } else if (relativePath.includes('tokens') && relativePath.endsWith('.txt')) {
        tokensPath = fsPath;
      } else if (relativePath.endsWith('.onnx') && !relativePath.includes('encoder') && !relativePath.includes('decoder') && !relativePath.includes('joiner')) {
        modelPath = fsPath;
      }
    }

    // Route to the appropriate STT model type
    if (model.id.includes('whisper')) {
      if (!encoderPath || !decoderPath || !tokensPath) {
        throw new Error(`Whisper archive for '${model.id}' missing encoder/decoder/tokens`);
      }
      await this.sttLoader!.loadModel({
        modelId: model.id,
        type: STTModelType.Whisper,
        modelFiles: { encoder: encoderPath, decoder: decoderPath, tokens: tokensPath },
        sampleRate: 16000,
        language: 'en',
      });
    } else if (model.id.includes('paraformer')) {
      if (!modelPath || !tokensPath) {
        throw new Error(`Paraformer archive for '${model.id}' missing model/tokens`);
      }
      await this.sttLoader!.loadModel({
        modelId: model.id,
        type: STTModelType.Paraformer,
        modelFiles: { model: modelPath, tokens: tokensPath },
        sampleRate: 16000,
      });
    } else if (model.id.includes('zipformer')) {
      if (!encoderPath || !decoderPath || !joinerPath || !tokensPath) {
        throw new Error(`Zipformer archive for '${model.id}' missing encoder/decoder/joiner/tokens`);
      }
      await this.sttLoader!.loadModel({
        modelId: model.id,
        type: STTModelType.Zipformer,
        modelFiles: { encoder: encoderPath, decoder: decoderPath, joiner: joinerPath, tokens: tokensPath },
        sampleRate: 16000,
      });
    } else {
      throw new Error(`Unknown STT model type for model: ${model.id}`);
    }
  }

  /**
   * Load an STT model from individual downloaded files (legacy path).
   */
  private async loadSTTFromIndividualFiles(
    model: ManagedModel,
    primaryData: Uint8Array,
    sherpa: SherpaONNXBridge,
    modelDir: string,
  ): Promise<void> {
    const primaryFilename = model.url.split('/').pop()!;
    const primaryPath = `${modelDir}/${primaryFilename}`;

    logger.debug(`Writing STT primary file to ${primaryPath} (${primaryData.length} bytes)`);
    sherpa.writeFile(primaryPath, primaryData);

    // Write additional files to sherpa FS (download on-demand if missing from OPFS)
    const additionalPaths: Record<string, string> = {};
    if (model.additionalFiles) {
      for (const file of model.additionalFiles) {
        const fileKey = this.downloader.additionalFileKey(model.id, file.filename);
        let fileData = await this.downloader.loadFromOPFS(fileKey);
        if (!fileData) {
          logger.debug(`Additional file ${file.filename} not in OPFS, downloading...`);
          fileData = await this.downloader.downloadFile(file.url);
          await this.downloader.storeInOPFS(fileKey, fileData);
        }
        const filePath = `${modelDir}/${file.filename}`;
        logger.debug(`Writing STT file to ${filePath} (${fileData.length} bytes)`);
        sherpa.writeFile(filePath, fileData);
        additionalPaths[file.filename] = filePath;
      }
    }

    // Determine model type and build config based on the model ID
    if (model.id.includes('whisper')) {
      const encoderPath = primaryPath;
      const decoderFilename = model.additionalFiles?.find(f => f.filename.includes('decoder'))?.filename;
      const tokensFilename = model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;

      if (!decoderFilename || !tokensFilename) {
        throw new Error('Whisper model requires encoder, decoder, and tokens files');
      }

      await this.sttLoader!.loadModel({
        modelId: model.id,
        type: STTModelType.Whisper,
        modelFiles: {
          encoder: encoderPath,
          decoder: `${modelDir}/${decoderFilename}`,
          tokens: `${modelDir}/${tokensFilename}`,
        },
        sampleRate: 16000,
        language: 'en',
      });
    } else if (model.id.includes('paraformer')) {
      const tokensFilename = model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;
      if (!tokensFilename) {
        throw new Error('Paraformer model requires model and tokens files');
      }
      await this.sttLoader!.loadModel({
        modelId: model.id,
        type: STTModelType.Paraformer,
        modelFiles: { model: primaryPath, tokens: `${modelDir}/${tokensFilename}` },
        sampleRate: 16000,
      });
    } else if (model.id.includes('zipformer')) {
      const decoderFilename = model.additionalFiles?.find(f => f.filename.includes('decoder'))?.filename;
      const joinerFilename = model.additionalFiles?.find(f => f.filename.includes('joiner'))?.filename;
      const tokensFilename = model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;
      if (!decoderFilename || !joinerFilename || !tokensFilename) {
        throw new Error('Zipformer model requires encoder, decoder, joiner, and tokens files');
      }
      await this.sttLoader!.loadModel({
        modelId: model.id,
        type: STTModelType.Zipformer,
        modelFiles: {
          encoder: primaryPath,
          decoder: `${modelDir}/${decoderFilename}`,
          joiner: `${modelDir}/${joinerFilename}`,
          tokens: `${modelDir}/${tokensFilename}`,
        },
        sampleRate: 16000,
      });
    } else {
      throw new Error(`Unknown STT model type for model: ${model.id}`);
    }
  }

  /**
   * Load a TTS model into the sherpa-onnx Emscripten FS and initialise the TTS engine.
   *
   * Supports two modes:
   *  1. **Archive** (isArchive=true): Download is a .tar.gz that bundles model files +
   *     espeak-ng-data. Matches the Swift SDK approach — extract and write all files.
   *  2. **Individual files** (legacy): Separate model + companion file downloads.
   */
  private async loadTTSModel(model: ManagedModel, primaryData: Uint8Array): Promise<void> {
    if (!this.ttsLoader) throw new Error('No TTS loader registered. Call ModelManager.setTTSLoader() first.');

    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${model.id}`;

    if (model.isArchive) {
      await this.loadTTSFromArchive(model, primaryData, sherpa, modelDir);
    } else {
      await this.loadTTSFromIndividualFiles(model, primaryData, sherpa, modelDir);
    }

    logger.info(`TTS model loaded via sherpa-onnx: ${model.id}`);
  }

  /**
   * Load a TTS model from a .tar.gz archive (matching Swift SDK approach).
   *
   * The archive contains all necessary files in a nested directory:
   *   model.onnx, tokens.txt, espeak-ng-data/, etc.
   * We extract everything and write it to the sherpa virtual FS.
   */
  private async loadTTSFromArchive(
    model: ManagedModel,
    archiveData: Uint8Array,
    sherpa: SherpaONNXBridge,
    modelDir: string,
  ): Promise<void> {
    logger.debug(`Extracting TTS archive for ${model.id} (${archiveData.length} bytes)...`);

    const entries = await extractTarGz(archiveData);
    logger.debug(`Extracted ${entries.length} files from archive`);

    // Find the common prefix (nested directory) — archives typically contain
    // one top-level directory with all files inside it.
    const prefix = this.findArchivePrefix(entries.map(e => e.path));

    // Write all extracted files to the sherpa virtual FS
    let modelPath: string | null = null;
    let tokensPath: string | null = null;
    let dataDirPath: string | null = null;

    for (const entry of entries) {
      // Strip the nested directory prefix to get relative path
      const relativePath = prefix ? entry.path.slice(prefix.length) : entry.path;
      const fsPath = `${modelDir}/${relativePath}`;

      sherpa.writeFile(fsPath, entry.data);

      // Auto-discover key files
      if (relativePath.endsWith('.onnx') && !relativePath.includes('/')) {
        modelPath = fsPath;
      }
      if (relativePath === 'tokens.txt') {
        tokensPath = fsPath;
      }
      if (relativePath.startsWith('espeak-ng-data/') && !dataDirPath) {
        dataDirPath = `${modelDir}/espeak-ng-data`;
      }
    }

    if (!modelPath) {
      throw new Error(`TTS archive for '${model.id}' does not contain an .onnx model file`);
    }
    if (!tokensPath) {
      throw new Error(`TTS archive for '${model.id}' does not contain tokens.txt`);
    }

    logger.debug(`TTS archive extracted — model: ${modelPath}, tokens: ${tokensPath}, dataDir: ${dataDirPath ?? 'none'}`);

    await this.ttsLoader!.loadVoice({
      voiceId: model.id,
      modelPath,
      tokensPath,
      dataDir: dataDirPath ?? '',
      numThreads: 1,
    });
  }

  /**
   * Load a TTS model from individual downloaded files.
   * Used when models are registered with individual file URLs (e.g. HuggingFace)
   * rather than tar.gz archives. Downloads espeak-ng-data on-demand for Piper models.
   */
  private async loadTTSFromIndividualFiles(
    model: ManagedModel,
    primaryData: Uint8Array,
    sherpa: SherpaONNXBridge,
    modelDir: string,
  ): Promise<void> {
    const primaryFilename = model.url.split('/').pop()!;
    const primaryPath = `${modelDir}/${primaryFilename}`;

    logger.debug(`Writing TTS primary file to ${primaryPath} (${primaryData.length} bytes)`);
    sherpa.writeFile(primaryPath, primaryData);

    // Write additional files (tokens.txt, *.json, etc.)
    const additionalPaths: Record<string, string> = {};
    if (model.additionalFiles) {
      for (const file of model.additionalFiles) {
        const fileKey = this.downloader.additionalFileKey(model.id, file.filename);
        let fileData = await this.downloader.loadFromOPFS(fileKey);
        if (!fileData) {
          logger.debug(`Additional file ${file.filename} not in OPFS, downloading...`);
          fileData = await this.downloader.downloadFile(file.url);
          await this.downloader.storeInOPFS(fileKey, fileData);
        }
        const filePath = `${modelDir}/${file.filename}`;
        logger.debug(`Writing TTS file to ${filePath} (${fileData.length} bytes)`);
        sherpa.writeFile(filePath, fileData);
        additionalPaths[file.filename] = filePath;
      }
    }

    const tokensPath = additionalPaths['tokens.txt'];
    if (!tokensPath) {
      throw new Error('TTS model requires tokens.txt file');
    }

    await this.ttsLoader!.loadVoice({
      voiceId: model.id,
      modelPath: primaryPath,
      tokensPath,
      dataDir: '', // espeak-ng-data is bundled in archives; individual-file path doesn't include it
      numThreads: 1,
    });
  }

  /**
   * Load a VAD model (Silero) into the sherpa-onnx Emscripten FS.
   * The Silero VAD is a single ONNX file — write it to FS and initialise.
   */
  private async loadVADModel(model: ManagedModel, data: Uint8Array): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${model.id}`;
    const filename = model.url?.split('/').pop() ?? 'silero_vad.onnx';
    const fsPath = `${modelDir}/${filename}`;

    logger.debug(`Writing VAD model to ${fsPath} (${data.length} bytes)`);
    sherpa.writeFile(fsPath, data);

    if (!this.vadLoader) throw new Error('No VAD loader registered. Call ModelManager.setVADLoader() first.');
    await this.vadLoader.loadModel({ modelPath: fsPath });
    logger.info(`VAD model loaded: ${model.id}`);
  }

  /**
   * Find the common directory prefix in archive entry paths.
   * Archives typically contain a single top-level directory (nested structure).
   * Returns the prefix including trailing '/', or empty string if no common prefix.
   */
  private findArchivePrefix(paths: string[]): string {
    if (paths.length === 0) return '';

    // Check if all paths share a common first directory component
    const firstSlash = paths[0].indexOf('/');
    if (firstSlash === -1) return '';

    const candidate = paths[0].slice(0, firstSlash + 1);
    const allMatch = paths.every(p => p.startsWith(candidate));
    return allMatch ? candidate : '';
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
        await this.llmLoader?.unloadModel();
      }

      // Clean up Emscripten FS model files to release WASM linear memory.
      // LLM models (Language) write .gguf files into the main-thread
      // Emscripten FS. VLM (Multimodal) models are handled by the Worker's
      // own WASM FS and don't need cleanup here.
      if (category === ModelCategory.Language) {
        try {
          const bridge = WASMBridge.shared;
          if (bridge.isLoaded) {
            const m = bridge.module as any;
            const fsPath = `/models/${modelId}.gguf`;
            try { m.FS_unlink(fsPath); } catch { /* file may not exist */ }
            logger.debug(`Cleaned up Emscripten FS: ${fsPath}`);
          }
        } catch {
          // Non-critical — FS cleanup is best-effort
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
