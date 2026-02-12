/**
 * Model Manager - Download, store (OPFS), and load models
 *
 * Mirrors iOS ModelManager: download from URL -> OPFS persistence ->
 * mount into Emscripten FS -> load via backend.
 *
 * Supports single-file models (GGUF) and multi-file models with
 * additional companion files (mmproj for VLM, decoder/tokens for STT, etc.).
 *
 * The app registers its model catalog via `ModelManager.registerModels()`.
 * VLM (vision) loading is pluggable via `ModelManager.setVLMLoader()`.
 */

import { WASMBridge } from '../Foundation/WASMBridge';
import { SherpaONNXBridge } from '../Foundation/SherpaONNXBridge';
import { EventBus } from '../Foundation/EventBus';
import { TextGeneration } from '../Public/Extensions/RunAnywhere+TextGeneration';
import { STT } from '../Public/Extensions/RunAnywhere+STT';
import { TTS } from '../Public/Extensions/RunAnywhere+TTS';
import { ModelCategory, LLMFramework, ModelStatus, DownloadStage, SDKEventType } from '../types/enums';

// Re-export SDK enums for convenience (consumers can import from either location)
export { ModelCategory, LLMFramework, ModelStatus, DownloadStage };

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * For multi-file models (VLM, STT, TTS), describes additional files
 * that need to be downloaded alongside the main URL.
 */
export interface ModelFileDescriptor {
  /** Download URL */
  url: string;
  /** Filename to store as (used for OPFS key and FS path) */
  filename: string;
  /** Optional: size in bytes (for progress estimation) */
  sizeBytes?: number;
}

/**
 * A model being managed by the ModelManager.
 * Tracks download state, load state, and file locations.
 *
 * Named `ManagedModel` to avoid collision with the SDK's existing
 * `ModelInfo` type in types/models.ts (which describes C++ bridge models).
 */
export interface ManagedModel {
  id: string;
  name: string;
  /** Primary download URL (single file models) or archive URL */
  url: string;
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
  status: ModelStatus;
  downloadProgress?: number;
  error?: string;
  sizeBytes?: number;

  /**
   * For multi-file models: additional files to download.
   * The main 'url' is still the primary file; these are extras.
   * For VLM: includes the mmproj file.
   * For STT/TTS: encoder/decoder/tokens files.
   */
  additionalFiles?: ModelFileDescriptor[];

  /**
   * Whether the main URL is an archive (tar.gz) that needs extraction.
   * STT and TTS models from sherpa-onnx are typically tar.gz archives.
   */
  isArchive?: boolean;

  /**
   * Paths of extracted files after download (populated after extraction).
   * Maps logical name -> filesystem path.
   */
  extractedPaths?: Record<string, string>;
}

type ModelChangeCallback = (models: ManagedModel[]) => void;

// ---------------------------------------------------------------------------
// Download Progress (mirrors iOS DownloadProgress)
// ---------------------------------------------------------------------------

/** Structured download progress with stage information. */
export interface DownloadProgress {
  modelId: string;
  stage: DownloadStage;
  /** Overall progress 0-1 */
  progress: number;
  bytesDownloaded: number;
  totalBytes: number;
  /** Filename currently being downloaded (for multi-file models) */
  currentFile?: string;
  /** Number of files completed so far */
  filesCompleted?: number;
  /** Total number of files to download */
  filesTotal?: number;
}

// ---------------------------------------------------------------------------
// Compact Model Definition & Resolver
// ---------------------------------------------------------------------------

const HF_BASE = 'https://huggingface.co';

/** Compact model definition for the registry. */
export interface CompactModelDef {
  id: string;
  name: string;
  /** HuggingFace repo path (e.g., 'LiquidAI/LFM2-VL-450M-GGUF'). */
  repo?: string;
  /** Direct URL override for non-HuggingFace sources (e.g., GitHub). */
  url?: string;
  /** Filenames in the repo. First = primary model file, rest = companions. */
  files: string[];
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
}

/** Expand a compact definition into the full ManagedModel shape (minus status). */
function resolveModelDef(def: CompactModelDef): Omit<ManagedModel, 'status'> {
  const baseUrl = def.repo ? `${HF_BASE}/${def.repo}/resolve/main` : undefined;
  const primaryUrl = def.url ?? `${baseUrl}/${def.files[0]}`;

  const additionalFiles: ModelFileDescriptor[] = def.files.slice(1).map((filename) => ({
    url: baseUrl ? `${baseUrl}/${filename}` : filename,
    filename,
  }));

  return {
    id: def.id,
    name: def.name,
    url: primaryUrl,
    framework: def.framework,
    modality: def.modality,
    memoryRequirement: def.memoryRequirement,
    ...(additionalFiles.length > 0 ? { additionalFiles } : {}),
  };
}

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
  private models: ManagedModel[] = [];
  private listeners: ModelChangeCallback[] = [];
  /**
   * Tracks loaded models per category — allows STT + LLM + TTS simultaneously
   * for the voice pipeline. Key = ModelCategory, Value = model id.
   */
  private loadedByCategory: Map<ModelCategory, string> = new Map();

  /** Pluggable VLM loader (set by the app via setVLMLoader) */
  private vlmLoader: VLMLoader | null = null;

  constructor() {
    // Request persistent storage so browser won't evict our cached models
    this.requestPersistentStorage();
  }

  // --- Registration API (called by the app) ---

  /**
   * Register a catalog of models. Resolves compact definitions into full
   * ManagedModel entries and checks OPFS for previously downloaded files.
   */
  registerModels(models: CompactModelDef[]): void {
    const resolved = models.map(resolveModelDef);
    this.models = resolved.map((m) => ({ ...m, status: ModelStatus.Registered }));
    this.notifyListeners();
    EventBus.shared.emit('model.registered', SDKEventType.Model, { count: models.length });
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
    for (const model of this.models) {
      if (model.status !== ModelStatus.Registered) continue;
      try {
        const size = await this.getOPFSFileSize(model.id);
        if (size !== null && size > 0) {
          this.updateModel(model.id, { status: ModelStatus.Downloaded, sizeBytes: size });
        }
      } catch {
        // Not in OPFS, keep as registered
      }
    }
  }

  /** Check if a file exists in OPFS and return its size (without reading it) */
  private async getOPFSFileSize(key: string): Promise<number | null> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');

      if (key.includes('/')) {
        const parts = key.split('/');
        let dir = modelsDir;
        for (let i = 0; i < parts.length - 1; i++) {
          dir = await dir.getDirectoryHandle(parts[i]);
        }
        const fileHandle = await dir.getFileHandle(parts[parts.length - 1]);
        const file = await fileHandle.getFile();
        return file.size;
      } else {
        const fileHandle = await modelsDir.getFileHandle(key);
        const file = await fileHandle.getFile();
        return file.size;
      }
    } catch {
      return null;
    }
  }

  // --- Queries ---

  getModels(): ManagedModel[] {
    return [...this.models];
  }

  getModelsByCategory(category: ModelCategory): ManagedModel[] {
    return this.models.filter((m) => m.modality === category);
  }

  getModelsByFramework(framework: LLMFramework): ManagedModel[] {
    return this.models.filter((m) => m.framework === framework);
  }

  getLLMModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.Language);
  }

  getVLMModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.Multimodal);
  }

  getSTTModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.SpeechRecognition);
  }

  getTTSModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.SpeechSynthesis);
  }

  getVADModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.Audio);
  }

  getLoadedModel(category?: ModelCategory): ManagedModel | null {
    if (category) {
      const id = this.loadedByCategory.get(category);
      return id ? this.findModel(id) ?? null : null;
    }
    return this.models.find((m) => m.status === ModelStatus.Loaded) ?? null;
  }

  getLoadedModelId(category?: ModelCategory): string | null {
    if (category) {
      return this.loadedByCategory.get(category) ?? null;
    }
    // Legacy: return first loaded model id
    return this.models.find((m) => m.status === ModelStatus.Loaded)?.id ?? null;
  }

  /** Check if models for all given categories are loaded */
  areAllLoaded(categories: ModelCategory[]): boolean {
    return categories.every((c) => this.loadedByCategory.has(c));
  }

  // --- Model lifecycle ---

  /**
   * Download a model (and any additional files).
   * Handles both single-file and multi-file models.
   */
  async downloadModel(modelId: string): Promise<void> {
    const model = this.findModel(modelId);
    if (!model) return;

    this.updateModel(modelId, { status: ModelStatus.Downloading, downloadProgress: 0 });
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
        this.updateModel(modelId, { downloadProgress: overallProgress });
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
            this.updateModel(modelId, { downloadProgress: overallProgress });
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
          const fileData = await this.loadFromOPFS(fileKey);
          if (fileData) totalSize += fileData.length;
        }
      }

      this.updateModel(modelId, {
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
      this.updateModel(modelId, { status: ModelStatus.Error, error: message });
      EventBus.shared.emit('model.downloadFailed', SDKEventType.Model, { modelId, error: message });
    }
  }

  async loadModel(modelId: string): Promise<boolean> {
    const model = this.findModel(modelId);
    if (!model || (model.status !== ModelStatus.Downloaded && model.status !== ModelStatus.Registered)) return false;

    // Unload current model of the SAME category only (allows STT + LLM + TTS simultaneously)
    const category = model.modality ?? ModelCategory.Language;
    const currentlyLoadedId = this.loadedByCategory.get(category);
    if (currentlyLoadedId) {
      await this.unloadModelByCategory(category);
    }

    this.updateModel(modelId, { status: ModelStatus.Loading });
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, category });

    try {
      if (model.modality === ModelCategory.Multimodal) {
        // VLM: Worker reads from OPFS directly — skip reading 940MB+ into main thread memory.
        // Just verify the model file exists in OPFS.
        const exists = await this.existsInOPFS(modelId);
        if (!exists) {
          throw new Error('Model not downloaded — please download the model first.');
        }
        await this.loadLLMModel(model, modelId, new Uint8Array(0));
      } else {
        const data = await this.loadFromOPFS(modelId);
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
      this.updateModel(modelId, { status: ModelStatus.Loaded });
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, category });
      return true;
    } catch (err) {
      const message = err instanceof Error
        ? err.message
        : (typeof err === 'object' ? JSON.stringify(err) : String(err));
      console.error(`[ModelManager] Failed to load model ${modelId}:`, message, err);
      this.updateModel(modelId, { status: ModelStatus.Error, error: message });
      EventBus.shared.emit('model.loadFailed', SDKEventType.Model, { modelId, error: message });
      return false;
    }
  }

  /**
   * Load an LLM/VLM model into the RACommons Emscripten FS.
   */
  private async loadLLMModel(model: ManagedModel, modelId: string, data: Uint8Array): Promise<void> {
    const fsDir = `/models`;
    const fsPath = `${fsDir}/${modelId}.gguf`;

    if (model.modality === ModelCategory.Multimodal) {
      // VLM models are loaded in a dedicated Web Worker that reads from OPFS.
      // No need to write model data to the main-thread Emscripten FS.
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
      // VLM: load in a dedicated Web Worker so inference doesn't block the UI.
      // The Worker reads model files directly from OPFS (zero-copy, no transfer).
      const mmprojFile = model.additionalFiles?.find((f) => f.filename.includes('mmproj'));
      if (!mmprojFile) {
        console.warn(`[ModelManager] No mmproj found, loading as text-only LLM: ${modelId}`);
        await TextGeneration.loadModel(fsPath, modelId, model.name);
      } else {
        // Ensure mmproj is in OPFS (fallback download if missing)
        const mmprojKey = this.additionalFileKey(modelId, mmprojFile.filename);
        const mmprojExists = await this.existsInOPFS(mmprojKey);
        if (!mmprojExists && mmprojFile.url) {
          console.log(`[ModelManager] mmproj not in OPFS, downloading on-demand: ${mmprojFile.filename}`);
          const mmprojData = await this.downloadFile(mmprojFile.url);
          await this.storeInOPFS(mmprojKey, mmprojData);
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
   * Stages all model files into the sherpa-onnx Emscripten virtual FS,
   * then calls STT.loadModel() with the appropriate config.
   */
  private async loadSTTModel(model: ManagedModel, primaryData: Uint8Array): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${model.id}`;

    // Derive primary filename from the URL
    const primaryFilename = model.url.split('/').pop()!;
    const primaryPath = `${modelDir}/${primaryFilename}`;

    // Write primary file to sherpa FS
    console.log(`[ModelManager] Writing STT primary file to ${primaryPath} (${primaryData.length} bytes)`);
    sherpa.writeFile(primaryPath, primaryData);

    // Write additional files to sherpa FS (download on-demand if missing from OPFS)
    const additionalPaths: Record<string, string> = {};
    if (model.additionalFiles) {
      for (const file of model.additionalFiles) {
        const fileKey = this.additionalFileKey(model.id, file.filename);
        let fileData = await this.loadFromOPFS(fileKey);
        if (!fileData) {
          // Download missing additional file on-demand
          console.log(`[ModelManager] Additional file ${file.filename} not in OPFS, downloading...`);
          fileData = await this.downloadFile(file.url);
          await this.storeInOPFS(fileKey, fileData);
        }
        const filePath = `${modelDir}/${file.filename}`;
        console.log(`[ModelManager] Writing STT file to ${filePath} (${fileData.length} bytes)`);
        sherpa.writeFile(filePath, fileData);
        additionalPaths[file.filename] = filePath;
      }
    }

    // Determine model type and build config based on the model ID
    // sherpa-onnx-whisper-* models are Whisper type
    if (model.id.includes('whisper')) {
      // Whisper model: needs encoder, decoder, tokens
      const encoderPath = primaryPath; // Primary URL is the encoder
      const decoderFilename = model.additionalFiles?.find(f => f.filename.includes('decoder'))?.filename;
      const tokensFilename = model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;

      if (!decoderFilename || !tokensFilename) {
        throw new Error('Whisper model requires encoder, decoder, and tokens files');
      }

      await STT.loadModel({
        modelId: model.id,
        type: 'whisper',
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
        type: 'paraformer',
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
        type: 'zipformer',
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
   * Paths are relative to the HuggingFace repo root.
   * Includes core phoneme data AND language definition files for all
   * English variants (US, GB, etc.) so any Piper English model works.
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
    // (required for espeak-ng voice initialization in Piper models)
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
   * Downloads from HuggingFace and caches in OPFS for subsequent loads.
   */
  private async ensureEspeakNgData(): Promise<void> {
    if (this.espeakNgDataLoaded) return;

    const sherpa = SherpaONNXBridge.shared;
    const baseUrl = 'https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/';

    console.log('[ModelManager] Loading espeak-ng-data files for TTS...');

    for (const filePath of ModelManagerImpl.ESPEAK_NG_DATA_FILES) {
      // Derive FS path: 'espeak-ng-data/lang/gmw/en' -> '/espeak-ng-data/lang/gmw/en'
      const fsPath = `/${filePath}`;
      // Cache key preserves full relative path
      const cacheKey = filePath;

      let data = await this.loadFromOPFS(cacheKey);
      if (!data) {
        console.log(`[ModelManager] Downloading ${filePath}...`);
        data = await this.downloadFile(`${baseUrl}${filePath}`);
        await this.storeInOPFS(cacheKey, data);
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

    // Derive primary filename from the URL
    const primaryFilename = model.url.split('/').pop()!;
    const primaryPath = `${modelDir}/${primaryFilename}`;

    // Write primary model file to sherpa FS
    console.log(`[ModelManager] Writing TTS primary file to ${primaryPath} (${primaryData.length} bytes)`);
    sherpa.writeFile(primaryPath, primaryData);

    // Write additional files (tokens.txt, *.json, etc.)
    const additionalPaths: Record<string, string> = {};
    if (model.additionalFiles) {
      for (const file of model.additionalFiles) {
        const fileKey = this.additionalFileKey(model.id, file.filename);
        let fileData = await this.loadFromOPFS(fileKey);
        if (!fileData) {
          console.log(`[ModelManager] Additional file ${file.filename} not in OPFS, downloading...`);
          fileData = await this.downloadFile(file.url);
          await this.storeInOPFS(fileKey, fileData);
        }
        const filePath = `${modelDir}/${file.filename}`;
        console.log(`[ModelManager] Writing TTS file to ${filePath} (${fileData.length} bytes)`);
        sherpa.writeFile(filePath, fileData);
        additionalPaths[file.filename] = filePath;
      }
    }

    // Piper VITS models: need model.onnx + tokens.txt + espeak-ng-data
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

    this.updateModel(modelId, { status: ModelStatus.Downloaded });
    this.loadedByCategory.delete(category);
    EventBus.shared.emit('model.unloaded', SDKEventType.Model, { modelId, category });
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
    await this.deleteFromOPFS(modelId);

    // Delete additional files
    const model = this.findModel(modelId);
    if (model?.additionalFiles) {
      for (const file of model.additionalFiles) {
        await this.deleteFromOPFS(this.additionalFileKey(modelId, file.filename));
      }
    }

    this.updateModel(modelId, { status: ModelStatus.Registered, downloadProgress: undefined, sizeBytes: undefined });
  }

  // --- Download Helper ---

  private async downloadFile(
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

  /** Emit a structured download progress event via EventBus */
  private emitDownloadProgress(progress: DownloadProgress): void {
    EventBus.shared.emit('model.downloadProgress', SDKEventType.Model, progress as unknown as Record<string, unknown>);
  }

  // --- OPFS Storage ---

  /**
   * Build a flat OPFS key for additional files (e.g., mmproj).
   * Uses `__` separator instead of `/` to avoid name collisions between
   * a primary model FILE and a directory with the same name.
   */
  private additionalFileKey(modelId: string, filename: string): string {
    return `${modelId}__${filename}`;
  }

  private async getOPFSRoot(): Promise<FileSystemDirectoryHandle> {
    return navigator.storage.getDirectory();
  }

  /** Quick existence check without reading the full file into memory. */
  private async existsInOPFS(key: string): Promise<boolean> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');
      await modelsDir.getFileHandle(key);
      return true;
    } catch {
      return false;
    }
  }

  private async storeInOPFS(key: string, data: Uint8Array): Promise<void> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models', { create: true });

      // Assert the concrete ArrayBuffer type — the data always comes from
      // fetch / Uint8Array constructors which use a plain ArrayBuffer, never
      // SharedArrayBuffer.  The TS DOM lib for FileSystemWritableFileStream
      // requires ArrayBuffer (not ArrayBufferLike).
      const writeData = data as Uint8Array<ArrayBuffer>;

      // Handle nested keys (e.g., "modelId/filename.gguf")
      if (key.includes('/')) {
        const parts = key.split('/');
        let dir = modelsDir;
        for (let i = 0; i < parts.length - 1; i++) {
          dir = await dir.getDirectoryHandle(parts[i], { create: true });
        }
        const fileHandle = await dir.getFileHandle(parts[parts.length - 1], { create: true });
        const writable = await fileHandle.createWritable();
        await writable.write(writeData);
        await writable.close();
      } else {
        const fileHandle = await modelsDir.getFileHandle(key, { create: true });
        const writable = await fileHandle.createWritable();
        await writable.write(writeData);
        await writable.close();
      }
      console.log(`[ModelManager] Stored ${key} in OPFS (${(data.length / 1024 / 1024).toFixed(1)} MB)`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[ModelManager] OPFS store failed for "${key}": ${msg}`);
    }
  }

  private async loadFromOPFS(key: string): Promise<Uint8Array | null> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');

      let file: File;
      if (key.includes('/')) {
        const parts = key.split('/');
        let dir = modelsDir;
        for (let i = 0; i < parts.length - 1; i++) {
          dir = await dir.getDirectoryHandle(parts[i]);
        }
        const fileHandle = await dir.getFileHandle(parts[parts.length - 1]);
        file = await fileHandle.getFile();
      } else {
        const fileHandle = await modelsDir.getFileHandle(key);
        file = await fileHandle.getFile();
      }

      console.log(`[ModelManager] Loading ${key} from OPFS (${(file.size / 1024 / 1024).toFixed(1)} MB)`);
      const buffer = await file.arrayBuffer();
      return new Uint8Array(buffer);
    } catch (err) {
      // NotFoundError is expected for files that haven't been downloaded yet
      if (err instanceof DOMException && err.name === 'NotFoundError') {
        return null;
      }
      // Log unexpected errors
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[ModelManager] OPFS load failed for "${key}": ${msg}`);
      return null;
    }
  }

  private async deleteFromOPFS(key: string): Promise<void> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');

      if (key.includes('/')) {
        const parts = key.split('/');
        let dir = modelsDir;
        for (let i = 0; i < parts.length - 1; i++) {
          dir = await dir.getDirectoryHandle(parts[i]);
        }
        await dir.removeEntry(parts[parts.length - 1]);
      } else {
        await modelsDir.removeEntry(key);
      }
    } catch {
      // File may not exist
    }
  }

  async getStorageInfo(): Promise<{ modelCount: number; totalSize: number; available: number }> {
    let modelCount = 0;
    let totalSize = 0;
    try {
      const root = await this.getOPFSRoot();
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

  // --- Subscriptions ---

  onChange(callback: ModelChangeCallback): () => void {
    this.listeners.push(callback);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== callback);
    };
  }

  // --- Internals ---

  private findModel(id: string): ManagedModel | undefined {
    return this.models.find((m) => m.id === id);
  }

  private updateModel(id: string, patch: Partial<ManagedModel>): void {
    this.models = this.models.map((m) => (m.id === id ? { ...m, ...patch } : m));
    this.notifyListeners();
  }

  private notifyListeners(): void {
    for (const listener of this.listeners) {
      listener(this.getModels());
    }
  }
}

export const ModelManager = new ModelManagerImpl();
