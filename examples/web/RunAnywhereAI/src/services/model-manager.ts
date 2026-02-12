/**
 * Model Manager - Download, store (OPFS), and load models
 *
 * Mirrors iOS ModelManager: download from URL -> OPFS persistence ->
 * mount into Emscripten FS -> load via backend.
 *
 * Supports single-file models (GGUF) and multi-file models (tar.gz archives
 * containing ONNX + tokens + data files for STT/TTS/VLM).
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ModelFramework = 'llamacpp' | 'onnx' | 'coreml';
export type ModelModality =
  | 'text'
  | 'multimodal'
  | 'speechRecognition'
  | 'speechSynthesis'
  | 'voiceActivity'
  | 'imageGeneration';
export type ModelStatus = 'registered' | 'downloading' | 'downloaded' | 'loading' | 'loaded' | 'error';

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

export interface ModelInfo {
  id: string;
  name: string;
  /** Primary download URL (single file models) or archive URL */
  url: string;
  framework: ModelFramework;
  modality?: ModelModality;
  memoryRequirement?: number;
  status: ModelStatus;
  downloadProgress?: number;
  error?: string;
  sizeBytes?: number;

  /**
   * For multi-file models: additional files to download.
   * The main 'url' is still the primary file; these are extras.
   * For VLM: includes the mmproj file.
   * For STT/TTS: the main URL is a tar.gz archive containing all files.
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

type ModelChangeCallback = (models: ModelInfo[]) => void;

// ---------------------------------------------------------------------------
// Registered Models (mirroring iOS RunAnywhereAIApp.swift)
// ---------------------------------------------------------------------------

const REGISTERED_MODELS: Omit<ModelInfo, 'status'>[] = [
  // =========================================================================
  // LLM models (llama.cpp GGUF)
  // =========================================================================
  {
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 500_000_000,
  },
  {
    id: 'qwen2.5-0.5b-instruct-q6_k',
    name: 'Qwen 2.5 0.5B Q6_K',
    url: 'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 600_000_000,
  },
  {
    id: 'lfm2-350m-q4_k_m',
    name: 'LFM2 350M Q4_K_M',
    url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 250_000_000,
  },
  {
    id: 'lfm2-350m-q8_0',
    name: 'LFM2 350M Q8_0',
    url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 400_000_000,
  },

  // =========================================================================
  // VLM models (llama.cpp + mmproj)
  // =========================================================================
  {
    id: 'smolvlm-500m-instruct-q8_0',
    name: 'SmolVLM 500M Instruct Q8_0',
    url: 'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf',
    framework: 'llamacpp',
    modality: 'multimodal',
    memoryRequirement: 600_000_000,
    additionalFiles: [
      {
        url: 'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-f16.gguf',
        filename: 'mmproj-SmolVLM-500M-Instruct-f16.gguf',
        sizeBytes: 199_000_000,
      },
    ],
  },
  {
    id: 'qwen2-vl-2b-instruct-q4_k_m',
    name: 'Qwen2-VL 2B Instruct Q4_K_M',
    url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
    framework: 'llamacpp',
    modality: 'multimodal',
    memoryRequirement: 1_800_000_000,
    additionalFiles: [
      {
        url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
        filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
      },
    ],
  },

  // =========================================================================
  // STT models (sherpa-onnx Whisper, individual ONNX files)
  // =========================================================================
  {
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Whisper Tiny English (ONNX)',
    url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-encoder.int8.onnx',
    framework: 'onnx',
    modality: 'speechRecognition',
    memoryRequirement: 105_000_000,
    additionalFiles: [
      {
        url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-decoder.int8.onnx',
        filename: 'tiny.en-decoder.int8.onnx',
        sizeBytes: 89_900_000,
      },
      {
        url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-tokens.txt',
        filename: 'tiny.en-tokens.txt',
        sizeBytes: 836_000,
      },
    ],
  },

  // =========================================================================
  // TTS models (sherpa-onnx Piper VITS, individual ONNX files)
  // =========================================================================
  {
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS US English (Lessac)',
    url: 'https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/en_US-lessac-medium.onnx',
    framework: 'onnx',
    modality: 'speechSynthesis',
    memoryRequirement: 65_000_000,
    additionalFiles: [
      {
        url: 'https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/tokens.txt',
        filename: 'tokens.txt',
        sizeBytes: 921,
      },
      {
        url: 'https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/en_US-lessac-medium.onnx.json',
        filename: 'en_US-lessac-medium.onnx.json',
        sizeBytes: 4_890,
      },
    ],
  },
  {
    id: 'vits-piper-en_GB-vctk-medium',
    name: 'Piper TTS British English (VCTK)',
    url: 'https://huggingface.co/csukuangfj/vits-piper-en_GB-vctk-medium/resolve/main/en_GB-vctk-medium.onnx',
    framework: 'onnx',
    modality: 'speechSynthesis',
    memoryRequirement: 77_000_000,
    additionalFiles: [
      {
        url: 'https://huggingface.co/csukuangfj/vits-piper-en_GB-vctk-medium/resolve/main/tokens.txt',
        filename: 'tokens.txt',
        sizeBytes: 921,
      },
      {
        url: 'https://huggingface.co/csukuangfj/vits-piper-en_GB-vctk-medium/resolve/main/en_GB-vctk-medium.onnx.json',
        filename: 'en_GB-vctk-medium.onnx.json',
        sizeBytes: 6_640,
      },
    ],
  },

  // =========================================================================
  // VAD model (Silero VAD, single ONNX file)
  // =========================================================================
  {
    id: 'silero-vad-v5',
    name: 'Silero VAD v5',
    url: 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
    framework: 'onnx',
    modality: 'voiceActivity',
    memoryRequirement: 5_000_000,
  },
];

// ---------------------------------------------------------------------------
// Model Manager Singleton
// ---------------------------------------------------------------------------

class ModelManagerImpl {
  private models: ModelInfo[] = [];
  private listeners: ModelChangeCallback[] = [];
  /**
   * Tracks loaded models per modality — allows STT + LLM + TTS simultaneously
   * for the voice pipeline. Key = ModelModality, Value = model id.
   */
  private loadedByModality: Map<ModelModality, string> = new Map();

  constructor() {
    this.models = REGISTERED_MODELS.map((m) => ({ ...m, status: 'registered' as ModelStatus }));
    // Request persistent storage so browser won't evict our cached models
    this.requestPersistentStorage();
    // Check OPFS for previously downloaded models (async, updates status when done)
    this.refreshDownloadStatus();
  }

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
      if (model.status !== 'registered') continue;
      try {
        const size = await this.getOPFSFileSize(model.id);
        if (size !== null && size > 0) {
          this.updateModel(model.id, { status: 'downloaded', sizeBytes: size });
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

  getModels(): ModelInfo[] {
    return [...this.models];
  }

  getModelsByModality(modality: ModelModality): ModelInfo[] {
    return this.models.filter((m) => m.modality === modality);
  }

  getModelsByFramework(framework: ModelFramework): ModelInfo[] {
    return this.models.filter((m) => m.framework === framework);
  }

  getLLMModels(): ModelInfo[] {
    return this.models.filter((m) => m.modality === 'text');
  }

  getVLMModels(): ModelInfo[] {
    return this.models.filter((m) => m.modality === 'multimodal');
  }

  getSTTModels(): ModelInfo[] {
    return this.models.filter((m) => m.modality === 'speechRecognition');
  }

  getTTSModels(): ModelInfo[] {
    return this.models.filter((m) => m.modality === 'speechSynthesis');
  }

  getVADModels(): ModelInfo[] {
    return this.models.filter((m) => m.modality === 'voiceActivity');
  }

  getLoadedModel(modality?: ModelModality): ModelInfo | null {
    if (modality) {
      const id = this.loadedByModality.get(modality);
      return id ? this.findModel(id) ?? null : null;
    }
    return this.models.find((m) => m.status === 'loaded') ?? null;
  }

  getLoadedModelId(modality?: ModelModality): string | null {
    if (modality) {
      return this.loadedByModality.get(modality) ?? null;
    }
    // Legacy: return first loaded model id
    return this.models.find((m) => m.status === 'loaded')?.id ?? null;
  }

  /** Check if models for all given modalities are loaded */
  areAllLoaded(modalities: ModelModality[]): boolean {
    return modalities.every((m) => this.loadedByModality.has(m));
  }

  // --- Model lifecycle ---

  /**
   * Download a model (and any additional files).
   * Handles both single-file and multi-file models.
   */
  async downloadModel(modelId: string): Promise<void> {
    const model = this.findModel(modelId);
    if (!model) return;

    this.updateModel(modelId, { status: 'downloading', downloadProgress: 0 });

    try {
      // Download the primary file
      const primaryData = await this.downloadFile(model.url, (progress) => {
        // Weight primary file as main progress (adjust for additional files)
        const totalFiles = 1 + (model.additionalFiles?.length ?? 0);
        this.updateModel(modelId, { downloadProgress: progress / totalFiles });
      });

      await this.storeInOPFS(modelId, primaryData);

      // Download additional files (e.g., mmproj for VLM)
      if (model.additionalFiles && model.additionalFiles.length > 0) {
        const totalFiles = 1 + model.additionalFiles.length;
        for (let i = 0; i < model.additionalFiles.length; i++) {
          const file = model.additionalFiles[i];
          const fileKey = this.additionalFileKey(modelId, file.filename);
          const fileData = await this.downloadFile(file.url, (progress) => {
            const baseProgress = (1 + i) / totalFiles;
            const fileProgress = progress / totalFiles;
            this.updateModel(modelId, { downloadProgress: baseProgress + fileProgress });
          });
          await this.storeInOPFS(fileKey, fileData);
        }
      }

      let totalSize = primaryData.length;
      if (model.additionalFiles) {
        for (const file of model.additionalFiles) {
          const fileKey = this.additionalFileKey(modelId, file.filename);
          const fileData = await this.loadFromOPFS(fileKey);
          if (fileData) totalSize += fileData.length;
        }
      }

      this.updateModel(modelId, {
        status: 'downloaded',
        downloadProgress: 1,
        sizeBytes: totalSize,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.updateModel(modelId, { status: 'error', error: message });
    }
  }

  async loadModel(modelId: string): Promise<boolean> {
    const model = this.findModel(modelId);
    if (!model || (model.status !== 'downloaded' && model.status !== 'registered')) return false;

    // Unload current model of the SAME modality only (allows STT + LLM + TTS simultaneously)
    const modality = model.modality ?? 'text';
    const currentlyLoadedId = this.loadedByModality.get(modality);
    if (currentlyLoadedId) {
      await this.unloadModelByModality(modality);
    }

    this.updateModel(modelId, { status: 'loading' });

    try {
      const data = await this.loadFromOPFS(modelId);
      if (!data) {
        throw new Error('Model not downloaded — please download the model first.');
      }

      if (model.modality === 'speechRecognition') {
        // STT models go to the sherpa-onnx Emscripten FS (separate from RACommons)
        await this.loadSTTModel(model, data);
      } else if (model.modality === 'speechSynthesis') {
        // TTS models go to the sherpa-onnx Emscripten FS
        await this.loadTTSModel(model, data);
      } else {
        // LLM/VLM models go to the RACommons Emscripten FS
        await this.loadLLMModel(model, modelId, data);
      }

      this.loadedByModality.set(modality, modelId);
      this.updateModel(modelId, { status: 'loaded' });
      return true;
    } catch (err) {
      const message = err instanceof Error
        ? err.message
        : (typeof err === 'object' ? JSON.stringify(err) : String(err));
      console.error(`[ModelManager] Failed to load model ${modelId}:`, message, err);
      this.updateModel(modelId, { status: 'error', error: message });
      return false;
    }
  }

  /**
   * Load an LLM/VLM model into the RACommons Emscripten FS.
   */
  private async loadLLMModel(model: ModelInfo, modelId: string, data: Uint8Array): Promise<void> {
    const fsDir = `/models`;
    const fsPath = `${fsDir}/${modelId}.gguf`;

    const { WASMBridge, TextGeneration, VLM } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );

    const bridge = WASMBridge.shared;
    if (!bridge.isLoaded) {
      throw new Error('WASM module not loaded — SDK not initialized.');
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const m = bridge.module as any;

    if (typeof m.FS_createPath !== 'function' || typeof m.FS_createDataFile !== 'function') {
      throw new Error('Emscripten FS helper functions not available on WASM module.');
    }

    // Ensure /models directory exists in Emscripten's virtual FS
    m.FS_createPath('/', 'models', true, true);

    // Remove existing file if present (FS_createDataFile throws if file exists)
    try {
      m.FS_unlink(fsPath);
    } catch {
      // File doesn't exist yet -- that's fine
    }

    // Write the model bytes into Emscripten FS
    console.log(`[ModelManager] Writing ${data.length} bytes to ${fsPath}`);
    m.FS_createDataFile('/models', `${modelId}.gguf`, data, true, true, true);
    console.log(`[ModelManager] Model file written to ${fsPath}`);

    if (model.modality === 'multimodal') {
      // VLM: also write the mmproj file to Emscripten FS, then load via VLM extension
      let mmprojFsPath: string | null = null;

      const mmprojFile = model.additionalFiles?.find((f) => f.filename.includes('mmproj'));
      if (mmprojFile) {
        const mmprojKey = this.additionalFileKey(modelId, mmprojFile.filename);
        let mmprojData = await this.loadFromOPFS(mmprojKey);

        // Fallback: re-download mmproj if not found in OPFS (handles migration
        // from old nested-key format where store silently failed).
        if (!mmprojData && mmprojFile.url) {
          console.log(`[ModelManager] mmproj not in OPFS, downloading on-demand: ${mmprojFile.filename}`);
          mmprojData = await this.downloadFile(mmprojFile.url);
          await this.storeInOPFS(mmprojKey, mmprojData);
        }

        if (mmprojData) {
          mmprojFsPath = `${fsDir}/${mmprojFile.filename}`;
          try {
            m.FS_unlink(mmprojFsPath);
          } catch {
            // File doesn't exist yet
          }
          console.log(`[ModelManager] Writing mmproj ${mmprojData.length} bytes to ${mmprojFsPath}`);
          m.FS_createDataFile('/models', mmprojFile.filename, mmprojData, true, true, true);
          console.log(`[ModelManager] mmproj file written to ${mmprojFsPath}`);
        } else {
          console.warn(`[ModelManager] mmproj file not found in OPFS for ${modelId}`);
        }
      }

      if (mmprojFsPath) {
        await VLM.loadModel(fsPath, mmprojFsPath, modelId, model.name);
        console.log(`[ModelManager] VLM model loaded: ${modelId}`);
      } else {
        // Fallback: load as text-only LLM if mmproj is missing
        console.warn(`[ModelManager] No mmproj found, loading as text-only LLM: ${modelId}`);
        await TextGeneration.loadModel(fsPath, modelId, model.name);
      }
    } else if (model.modality === 'text') {
      await TextGeneration.loadModel(fsPath, modelId, model.name);
      console.log(`[ModelManager] LLM model loaded via TextGeneration: ${modelId}`);
    }
  }

  /**
   * Load an STT model into sherpa-onnx.
   * Stages all model files into the sherpa-onnx Emscripten virtual FS,
   * then calls STT.loadModel() with the appropriate config.
   */
  private async loadSTTModel(model: ModelInfo, primaryData: Uint8Array): Promise<void> {
    const { SherpaONNXBridge, STT } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );

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
   * Core espeak-ng-data files needed for Piper VITS TTS models.
   * These files provide phoneme data for text-to-phoneme conversion.
   * We download them from the model's HuggingFace repo and cache in OPFS.
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
  private async ensureEspeakNgData(sherpa: Awaited<ReturnType<typeof import('../../../../../sdk/runanywhere-web/packages/core/src/index')>>['SherpaONNXBridge']['shared']): Promise<void> {
    if (this.espeakNgDataLoaded) return;

    const baseUrl = 'https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/';

    console.log('[ModelManager] Loading espeak-ng-data files for TTS...');

    for (const filePath of ModelManagerImpl.ESPEAK_NG_DATA_FILES) {
      // Derive FS path: 'espeak-ng-data/lang/gmw/en' → '/espeak-ng-data/lang/gmw/en'
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

  private async loadTTSModel(model: ModelInfo, primaryData: Uint8Array): Promise<void> {
    const { SherpaONNXBridge, TTS } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );

    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    // Ensure espeak-ng-data is available (required for Piper VITS models)
    await this.ensureEspeakNgData(sherpa);

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

  /** Unload the currently loaded model for a specific modality */
  private async unloadModelByModality(modality: ModelModality): Promise<void> {
    const modelId = this.loadedByModality.get(modality);
    if (!modelId) return;

    try {
      if (modality === 'speechRecognition') {
        const { STT } = await import(
          '../../../../../sdk/runanywhere-web/packages/core/src/index'
        );
        await STT.unloadModel();
      } else if (modality === 'speechSynthesis') {
        const { TTS } = await import(
          '../../../../../sdk/runanywhere-web/packages/core/src/index'
        );
        await TTS.unloadVoice();
      } else {
        const { TextGeneration } = await import(
          '../../../../../sdk/runanywhere-web/packages/core/src/index'
        );
        await TextGeneration.unloadModel();
      }
    } catch {
      // Ignore unload errors
    }

    this.updateModel(modelId, { status: 'downloaded' });
    this.loadedByModality.delete(modality);
  }

  async deleteModel(modelId: string): Promise<void> {
    // Remove from loaded tracking if this model is loaded
    for (const [modality, id] of this.loadedByModality) {
      if (id === modelId) {
        this.loadedByModality.delete(modality);
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

    this.updateModel(modelId, { status: 'registered', downloadProgress: undefined, sizeBytes: undefined });
  }

  // --- Download Helper ---

  private async downloadFile(
    url: string,
    onProgress?: (progress: number) => void,
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
      onProgress?.(progress);
    }

    const data = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) {
      data.set(chunk, offset);
      offset += chunk.length;
    }

    return data;
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

  private async storeInOPFS(key: string, data: Uint8Array): Promise<void> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models', { create: true });

      // Use the Uint8Array directly (NOT data.buffer — which could be a
      // larger ArrayBuffer if data is a view/slice).
      const writeData = data;

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

  private findModel(id: string): ModelInfo | undefined {
    return this.models.find((m) => m.id === id);
  }

  private updateModel(id: string, patch: Partial<ModelInfo>): void {
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
