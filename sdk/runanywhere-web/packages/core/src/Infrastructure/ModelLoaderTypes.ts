/**
 * Model Loader Interfaces
 *
 * Defines the contracts that model-loading extensions must implement.
 * ModelManager depends on these interfaces (Infrastructure layer) rather
 * than on the concrete extension objects in the Public layer, keeping the
 * dependency flow correct: Public -> Infrastructure -> Foundation.
 *
 * Registrations are performed by backend provider packages during their
 * registration phase.
 *
 * The loader interfaces are self-contained: they receive raw model data
 * and a context object for fetching additional files. All backend-specific
 * logic (e.g. writing to sherpa-onnx FS, extracting archives) is handled
 * by the loader implementation in the backend package.
 */

import type { ManagedModel } from './ModelRegistry';

// ---------------------------------------------------------------------------
// Model Load Context
// ---------------------------------------------------------------------------

/**
 * Context passed to model loaders during the loading process.
 * Provides access to the raw model data and helpers for fetching
 * additional companion files.
 */
export interface ModelLoadContext {
  /** The model being loaded (metadata from the registry). */
  model: ManagedModel;

  /** Primary model file data (read from storage). */
  data: Uint8Array;

  /**
   * Download a file from a URL. Used for on-demand fetching of
   * companion files that aren't in storage yet.
   */
  downloadFile(url: string): Promise<Uint8Array>;

  /**
   * Load a companion file from storage (OPFS / local FS / memory cache).
   * Returns null if the file is not found.
   */
  loadFile(fileKey: string): Promise<Uint8Array | null>;

  /**
   * Store a companion file in storage.
   */
  storeFile(fileKey: string, data: Uint8Array): Promise<void>;

  /**
   * Build a storage key for a companion file.
   * @param modelId - The parent model ID
   * @param filename - The companion file name
   */
  additionalFileKey(modelId: string, filename: string): string;
}

// ---------------------------------------------------------------------------
// Loader Interfaces
// ---------------------------------------------------------------------------

/**
 * Loader for LLM text generation models.
 *
 * The implementation in @runanywhere/web-llamacpp handles:
 * - Loading the LlamaCpp WASM module
 * - Writing model files to the LlamaCpp Emscripten FS
 * - Calling the C API to load the model into inference engine
 */
export interface LLMModelLoader {
  /** Load an LLM model from raw data + context for additional files. */
  loadModelFromData(ctx: ModelLoadContext): Promise<void>;
  unloadModel(): Promise<void>;
  /** Unload model and clean up Emscripten FS. */
  unloadAndCleanup?(modelId: string): Promise<void>;
}

/**
 * Loader for STT models (speech-to-text).
 *
 * The implementation in @runanywhere/web-onnx handles:
 * - Loading the sherpa-onnx WASM module
 * - Writing model files to the sherpa virtual FS
 * - Extracting .tar.gz archives
 * - Creating the appropriate recognizer configuration
 */
export interface STTModelLoader {
  /** Load an STT model from raw data + context for additional files. */
  loadModelFromData(ctx: ModelLoadContext): Promise<void>;
  unloadModel(): Promise<void>;
}

/**
 * Loader for TTS voice models (text-to-speech).
 *
 * The implementation in @runanywhere/web-onnx handles:
 * - Loading the sherpa-onnx WASM module
 * - Writing model files to the sherpa virtual FS
 * - Extracting .tar.gz archives (including espeak-ng-data)
 * - Creating the TTS engine configuration
 */
export interface TTSModelLoader {
  /** Load a TTS model from raw data + context for additional files. */
  loadModelFromData(ctx: ModelLoadContext): Promise<void>;
  unloadVoice(): Promise<void>;
}

/**
 * Loader for VAD models (voice activity detection).
 *
 * The implementation in @runanywhere/web-onnx handles:
 * - Loading the sherpa-onnx WASM module
 * - Writing the Silero VAD model to the sherpa virtual FS
 */
export interface VADModelLoader {
  /** Load a VAD model from raw data + context. */
  loadModelFromData(ctx: ModelLoadContext): Promise<void>;
  cleanup(): void;
}
