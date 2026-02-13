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
import { TextGeneration } from '../Public/Extensions/RunAnywhere+TextGeneration';
import { STT, STTModelType } from '../Public/Extensions/RunAnywhere+STT';
import { TTS } from '../Public/Extensions/RunAnywhere+TTS';
import { ModelCategory, LLMFramework, ModelStatus, DownloadStage, SDKEventType } from '../types/enums';
import { OPFSStorage } from './OPFSStorage';
import { ModelRegistry } from './ModelRegistry';
import { ModelDownloader } from './ModelDownloader';
import type {
  ManagedModel,
  CompactModelDef,
  DownloadProgress,
  ModelFileDescriptor,
  ModelChangeCallback,
} from './ModelRegistry';

// Re-export types so existing imports from './Infrastructure/ModelManager' still work
export { ModelCategory, LLMFramework, ModelStatus, DownloadStage };
export type { ManagedModel, CompactModelDef, DownloadProgress, ModelFileDescriptor };

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

class ModelManagerImpl {
  private readonly registry = new ModelRegistry();
  private readonly storage = new OPFSStorage();
  private readonly downloader: ModelDownloader;

  /**
   * Tracks loaded models per category — allows STT + LLM + TTS simultaneously
   * for the voice pipeline. Key = ModelCategory, Value = model id.
   */
  private loadedByCategory: Map<ModelCategory, string> = new Map();

  /** Pluggable VLM loader (set by the app via setVLMLoader) */
  private vlmLoader: VLMLoader | null = null;

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

  // --- Internal init ---

  /** Request persistent storage to prevent browser from evicting cached models */
  private async requestPersistentStorage(): Promise<void> {
    try {
      if (navigator.storage?.persist) {
        const persisted = await navigator.storage.persist();
        console.log(`[ModelManager] Persistent storage: ${persisted ? 'granted' : 'denied'}`);
      }
    } catch {
      // Not supported or denied — non-critical
    }
  }

  /**
   * Check OPFS for models that were downloaded in a previous session.
   * Updates their status from 'registered' to 'downloaded'.
   * Only checks file existence + size — does NOT read file contents into memory.
   */
  private async refreshDownloadStatus(): Promise<void> {
    for (const model of this.registry.getModels()) {
      if (model.status !== ModelStatus.Registered) continue;
      try {
        const size = await this.downloader.getOPFSFileSize(model.id);
        if (size !== null && size > 0) {
          this.registry.updateModel(model.id, { status: ModelStatus.Downloaded, sizeBytes: size });
        }
      } catch {
        // Not in OPFS, keep as registered
      }
    }
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
   */
  async ensureLoaded(category: ModelCategory): Promise<ManagedModel | null> {
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
    await this.loadModel(downloaded.id);
    return this.getLoadedModel(category);
  }

  // --- Download (delegated to downloader) ---

  async downloadModel(modelId: string): Promise<void> {
    return this.downloader.downloadModel(modelId);
  }

  // --- Model loading orchestration ---

  async loadModel(modelId: string): Promise<boolean> {
    const model = this.registry.getModel(modelId);
    if (!model || (model.status !== ModelStatus.Downloaded && model.status !== ModelStatus.Registered)) return false;

    // Unload current model of the SAME category only (allows STT + LLM + TTS simultaneously)
    const category = model.modality ?? ModelCategory.Language;
    const currentlyLoadedId = this.loadedByCategory.get(category);
    if (currentlyLoadedId) {
      await this.unloadModelByCategory(category);
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Loading });
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, category });

    try {
      if (model.modality === ModelCategory.Multimodal) {
        // VLM: Worker reads from OPFS directly — skip reading 940MB+ into main thread memory.
        const exists = await this.downloader.existsInOPFS(modelId);
        if (!exists) {
          throw new Error('Model not downloaded — please download the model first.');
        }
        await this.loadLLMModel(model, modelId, new Uint8Array(0));
      } else {
        const data = await this.downloader.loadFromOPFS(modelId);
        if (!data) {
          throw new Error('Model not downloaded — please download the model first.');
        }

        if (model.modality === ModelCategory.SpeechRecognition) {
          await this.loadSTTModel(model, data);
        } else if (model.modality === ModelCategory.SpeechSynthesis) {
          await this.loadTTSModel(model, data);
        } else {
          await this.loadLLMModel(model, modelId, data);
        }
      }

      this.loadedByCategory.set(category, modelId);
      this.registry.updateModel(modelId, { status: ModelStatus.Loaded });
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, category });
      return true;
    } catch (err) {
      const message = err instanceof Error
        ? err.message
        : (typeof err === 'object' ? JSON.stringify(err) : String(err));
      console.error(`[ModelManager] Failed to load model ${modelId}:`, message, err);
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
      console.log(`[ModelManager] Writing ${data.length} bytes to ${fsPath}`);
      m.FS_createDataFile('/models', `${modelId}.gguf`, data, true, true, true);
      console.log(`[ModelManager] Model file written to ${fsPath}`);
    }

    if (model.modality === ModelCategory.Multimodal) {
      const mmprojFile = model.additionalFiles?.find((f) => f.filename.includes('mmproj'));
      if (!mmprojFile) {
        console.warn(`[ModelManager] No mmproj found, loading as text-only LLM: ${modelId}`);
        await TextGeneration.loadModel(fsPath, modelId, model.name);
      } else {
        // Ensure mmproj is in OPFS (fallback download if missing)
        const mmprojKey = this.downloader.additionalFileKey(modelId, mmprojFile.filename);
        const mmprojExists = await this.downloader.existsInOPFS(mmprojKey);
        if (!mmprojExists && mmprojFile.url) {
          console.log(`[ModelManager] mmproj not in OPFS, downloading on-demand: ${mmprojFile.filename}`);
          const mmprojData = await this.downloader.downloadFile(mmprojFile.url);
          await this.downloader.storeInOPFS(mmprojKey, mmprojData);
        }

        if (!this.vlmLoader) {
          throw new Error('No VLM loader registered. Call ModelManager.setVLMLoader() first.');
        }

        // Initialize the Worker (loads its own WASM instance)
        if (!this.vlmLoader.isInitialized) {
          console.log('[ModelManager] Initializing VLM loader...');
          await this.vlmLoader.init();
        }

        // Load model via the pluggable VLM loader
        console.log(`[ModelManager] Loading VLM model: ${modelId}`);
        await this.vlmLoader.loadModel({
          modelOpfsKey: modelId,
          modelFilename: `${modelId}.gguf`,
          mmprojOpfsKey: mmprojKey,
          mmprojFilename: mmprojFile.filename,
          modelId,
          modelName: model.name,
        });
        console.log(`[ModelManager] VLM model loaded: ${modelId}`);
      }
    } else if (model.modality === ModelCategory.Language) {
      await TextGeneration.loadModel(fsPath, modelId, model.name);
      console.log(`[ModelManager] LLM model loaded via TextGeneration: ${modelId}`);
    }
  }

  /**
   * Load an STT model into sherpa-onnx.
   */
  private async loadSTTModel(model: ManagedModel, primaryData: Uint8Array): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${model.id}`;
    const primaryFilename = model.url.split('/').pop()!;
    const primaryPath = `${modelDir}/${primaryFilename}`;

    console.log(`[ModelManager] Writing STT primary file to ${primaryPath} (${primaryData.length} bytes)`);
    sherpa.writeFile(primaryPath, primaryData);

    // Write additional files to sherpa FS (download on-demand if missing from OPFS)
    const additionalPaths: Record<string, string> = {};
    if (model.additionalFiles) {
      for (const file of model.additionalFiles) {
        const fileKey = this.downloader.additionalFileKey(model.id, file.filename);
        let fileData = await this.downloader.loadFromOPFS(fileKey);
        if (!fileData) {
          console.log(`[ModelManager] Additional file ${file.filename} not in OPFS, downloading...`);
          fileData = await this.downloader.downloadFile(file.url);
          await this.downloader.storeInOPFS(fileKey, fileData);
        }
        const filePath = `${modelDir}/${file.filename}`;
        console.log(`[ModelManager] Writing STT file to ${filePath} (${fileData.length} bytes)`);
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

      await STT.loadModel({
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
      await STT.loadModel({
        modelId: model.id,
        type: STTModelType.Paraformer,
        modelFiles: {
          model: primaryPath,
          tokens: `${modelDir}/${tokensFilename}`,
        },
        sampleRate: 16000,
      });
    } else if (model.id.includes('zipformer')) {
      const decoderFilename = model.additionalFiles?.find(f => f.filename.includes('decoder'))?.filename;
      const joinerFilename = model.additionalFiles?.find(f => f.filename.includes('joiner'))?.filename;
      const tokensFilename = model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;
      if (!decoderFilename || !joinerFilename || !tokensFilename) {
        throw new Error('Zipformer model requires encoder, decoder, joiner, and tokens files');
      }
      await STT.loadModel({
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

    console.log(`[ModelManager] STT model loaded via sherpa-onnx: ${model.id}`);
  }

  /**
   * Load a TTS model into the sherpa-onnx Emscripten FS and initialise the TTS engine.
   */

  /**
   * espeak-ng-data files needed for Piper VITS TTS.
   */
  private static readonly ESPEAK_NG_DATA_FILES = [
    // Core phoneme data
    'espeak-ng-data/phondata',
    'espeak-ng-data/phonindex',
    'espeak-ng-data/phontab',
    'espeak-ng-data/intonations',
    'espeak-ng-data/phondata-manifest',
    // English dictionary
    'espeak-ng-data/en_dict',
    // Language definition files for all English variants
    'espeak-ng-data/lang/gmw/en',
    'espeak-ng-data/lang/gmw/en-US',
    'espeak-ng-data/lang/gmw/en-029',
    'espeak-ng-data/lang/gmw/en-GB-scotland',
    'espeak-ng-data/lang/gmw/en-GB-x-gbclan',
    'espeak-ng-data/lang/gmw/en-GB-x-gbcwmd',
    'espeak-ng-data/lang/gmw/en-GB-x-rp',
    'espeak-ng-data/lang/gmw/en-US-nyc',
  ];

  private espeakNgDataLoaded = false;

  /**
   * Ensure espeak-ng-data files are available in the sherpa FS.
   */
  private async ensureEspeakNgData(): Promise<void> {
    if (this.espeakNgDataLoaded) return;

    const sherpa = SherpaONNXBridge.shared;
    const baseUrl = 'https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/';

    console.log('[ModelManager] Loading espeak-ng-data files for TTS...');

    for (const filePath of ModelManagerImpl.ESPEAK_NG_DATA_FILES) {
      const fsPath = `/${filePath}`;
      const cacheKey = filePath;

      let data = await this.downloader.loadFromOPFS(cacheKey);
      if (!data) {
        console.log(`[ModelManager] Downloading ${filePath}...`);
        data = await this.downloader.downloadFile(`${baseUrl}${filePath}`);
        await this.downloader.storeInOPFS(cacheKey, data);
      }
      console.log(`[ModelManager] Writing ${fsPath} (${data.length} bytes)`);
      sherpa.writeFile(fsPath, data);
    }

    this.espeakNgDataLoaded = true;
    console.log('[ModelManager] espeak-ng-data files loaded');
  }

  private async loadTTSModel(model: ManagedModel, primaryData: Uint8Array): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    // Ensure espeak-ng-data is available (required for Piper VITS models)
    await this.ensureEspeakNgData();

    const modelDir = `/models/${model.id}`;
    const primaryFilename = model.url.split('/').pop()!;
    const primaryPath = `${modelDir}/${primaryFilename}`;

    console.log(`[ModelManager] Writing TTS primary file to ${primaryPath} (${primaryData.length} bytes)`);
    sherpa.writeFile(primaryPath, primaryData);

    // Write additional files (tokens.txt, *.json, etc.)
    const additionalPaths: Record<string, string> = {};
    if (model.additionalFiles) {
      for (const file of model.additionalFiles) {
        const fileKey = this.downloader.additionalFileKey(model.id, file.filename);
        let fileData = await this.downloader.loadFromOPFS(fileKey);
        if (!fileData) {
          console.log(`[ModelManager] Additional file ${file.filename} not in OPFS, downloading...`);
          fileData = await this.downloader.downloadFile(file.url);
          await this.downloader.storeInOPFS(fileKey, fileData);
        }
        const filePath = `${modelDir}/${file.filename}`;
        console.log(`[ModelManager] Writing TTS file to ${filePath} (${fileData.length} bytes)`);
        sherpa.writeFile(filePath, fileData);
        additionalPaths[file.filename] = filePath;
      }
    }

    const tokensPath = additionalPaths['tokens.txt'];
    if (!tokensPath) {
      throw new Error('TTS model requires tokens.txt file');
    }

    await TTS.loadVoice({
      voiceId: model.id,
      modelPath: primaryPath,
      tokensPath,
      dataDir: '/espeak-ng-data',
      numThreads: 1,
    });

    console.log(`[ModelManager] TTS model loaded via sherpa-onnx: ${model.id}`);
  }

  /** Unload the currently loaded model for a specific category */
  private async unloadModelByCategory(category: ModelCategory): Promise<void> {
    const modelId = this.loadedByCategory.get(category);
    if (!modelId) return;

    try {
      if (category === ModelCategory.SpeechRecognition) {
        await STT.unloadModel();
      } else if (category === ModelCategory.SpeechSynthesis) {
        await TTS.unloadVoice();
      } else if (category === ModelCategory.Multimodal) {
        if (this.vlmLoader) {
          await this.vlmLoader.unloadModel();
        }
      } else {
        await TextGeneration.unloadModel();
      }
    } catch {
      // Ignore unload errors
    }

    this.registry.updateModel(modelId, { status: ModelStatus.Downloaded });
    this.loadedByCategory.delete(category);
    EventBus.shared.emit('model.unloaded', SDKEventType.Model, { modelId, category });
  }
}

export const ModelManager = new ModelManagerImpl();
