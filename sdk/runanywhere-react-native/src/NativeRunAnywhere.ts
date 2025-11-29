/**
 * NativeRunAnywhere.ts
 *
 * TurboModule codegen spec for the RunAnywhere React Native SDK.
 * This file defines the interface between TypeScript and the C++ native module.
 *
 * The C++ implementation directly calls runanywhere-core C API functions.
 */

import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

/**
 * Capability types matching runanywhere-core ra_capability_type enum
 */
export enum CapabilityType {
  TEXT_GENERATION = 0,
  EMBEDDINGS = 1,
  STT = 2,
  TTS = 3,
  VAD = 4,
  DIARIZATION = 5,
}

/**
 * Device types matching runanywhere-core ra_device_type enum
 */
export enum DeviceType {
  CPU = 0,
  GPU = 1,
  NEURAL_ENGINE = 2,
  METAL = 3,
  CUDA = 4,
  NNAPI = 5,
  COREML = 6,
  VULKAN = 7,
  UNKNOWN = 99,
}

/**
 * Result codes matching runanywhere-core ra_result_code enum
 */
export enum ResultCode {
  SUCCESS = 0,
  ERROR_INIT_FAILED = -1,
  ERROR_MODEL_LOAD_FAILED = -2,
  ERROR_INFERENCE_FAILED = -3,
  ERROR_INVALID_HANDLE = -4,
  ERROR_INVALID_PARAMS = -5,
  ERROR_OUT_OF_MEMORY = -6,
  ERROR_NOT_IMPLEMENTED = -7,
  ERROR_CANCELLED = -8,
  ERROR_TIMEOUT = -9,
  ERROR_IO = -10,
  ERROR_UNKNOWN = -99,
}

/**
 * TurboModule specification for RunAnywhere native module.
 *
 * This interface is used by React Native's codegen to generate
 * the C++ header file (NativeRunAnywhereModuleSpec.h) that the
 * C++ implementation must conform to.
 */
export interface Spec extends TurboModule {
  // ============================================================================
  // Backend Lifecycle
  // ============================================================================

  /**
   * Create a new backend instance.
   * @param name Backend name (e.g., "onnx", "llamacpp", "coreml")
   * @returns true if backend was created successfully
   */
  createBackend(name: string): boolean;

  /**
   * Initialize the backend with optional configuration.
   * @param configJson Optional JSON configuration string
   * @returns true if initialization succeeded
   */
  initialize(configJson: string | null): boolean;

  /**
   * Destroy the backend and release all resources.
   */
  destroy(): void;

  /**
   * Check if the backend is initialized.
   * @returns true if initialized
   */
  isInitialized(): boolean;

  /**
   * Get backend information as JSON.
   * @returns JSON string with backend info
   */
  getBackendInfo(): string;

  // ============================================================================
  // Capability Query
  // ============================================================================

  /**
   * Check if the backend supports a specific capability.
   * @param capability Capability type (from CapabilityType enum)
   * @returns true if supported
   */
  supportsCapability(capability: number): boolean;

  /**
   * Get all supported capabilities.
   * @returns Array of capability type numbers
   */
  getCapabilities(): number[];

  /**
   * Get the device type being used for inference.
   * @returns Device type number (from DeviceType enum)
   */
  getDeviceType(): number;

  /**
   * Get current memory usage in bytes.
   * @returns Memory usage in bytes
   */
  getMemoryUsage(): number;

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /**
   * Load a text generation model.
   * @param path Path to the model file
   * @param configJson Optional JSON configuration
   * @returns true if model loaded successfully
   */
  loadTextModel(path: string, configJson: string | null): boolean;

  /**
   * Check if a text model is loaded.
   * @returns true if loaded
   */
  isTextModelLoaded(): boolean;

  /**
   * Unload the current text model.
   * @returns true if unloaded successfully
   */
  unloadTextModel(): boolean;

  /**
   * Generate text synchronously.
   * @param prompt The input prompt
   * @param systemPrompt Optional system prompt
   * @param maxTokens Maximum tokens to generate
   * @param temperature Sampling temperature
   * @returns JSON string with generation result
   */
  generate(
    prompt: string,
    systemPrompt: string | null,
    maxTokens: number,
    temperature: number
  ): string;

  /**
   * Start streaming text generation.
   * Tokens are emitted via the 'onToken' event.
   * @param prompt The input prompt
   * @param systemPrompt Optional system prompt
   * @param maxTokens Maximum tokens to generate
   * @param temperature Sampling temperature
   */
  generateStream(
    prompt: string,
    systemPrompt: string | null,
    maxTokens: number,
    temperature: number
  ): void;

  /**
   * Cancel ongoing text generation.
   */
  cancelGeneration(): void;

  // ============================================================================
  // Speech-to-Text (STT)
  // ============================================================================

  /**
   * Load an STT model.
   * @param path Path to the model directory
   * @param modelType Model type ("whisper", "zipformer", "paraformer")
   * @param configJson Optional JSON configuration
   * @returns true if model loaded successfully
   */
  loadSTTModel(path: string, modelType: string, configJson: string | null): boolean;

  /**
   * Check if an STT model is loaded.
   * @returns true if loaded
   */
  isSTTModelLoaded(): boolean;

  /**
   * Unload the current STT model.
   * @returns true if unloaded successfully
   */
  unloadSTTModel(): boolean;

  /**
   * Transcribe audio data (batch mode).
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate (e.g., 16000)
   * @param language Optional language code (e.g., "en")
   * @returns JSON string with transcription result
   */
  transcribe(audioBase64: string, sampleRate: number, language: string | null): string;

  /**
   * Check if STT supports streaming.
   * @returns true if streaming is supported
   */
  supportsSTTStreaming(): boolean;

  /**
   * Create a new STT stream for real-time transcription.
   * @param configJson Optional JSON configuration
   * @returns Stream handle ID (or -1 on error)
   */
  createSTTStream(configJson: string | null): number;

  /**
   * Feed audio data to an STT stream.
   * @param streamHandle Stream handle from createSTTStream
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @returns true if audio was fed successfully
   */
  feedSTTAudio(streamHandle: number, audioBase64: string, sampleRate: number): boolean;

  /**
   * Decode current STT stream state.
   * @param streamHandle Stream handle
   * @returns JSON string with partial transcription
   */
  decodeSTT(streamHandle: number): string;

  /**
   * Check if STT stream is ready to decode.
   * @param streamHandle Stream handle
   * @returns true if ready
   */
  isSTTReady(streamHandle: number): boolean;

  /**
   * Check if STT stream detected end of speech.
   * @param streamHandle Stream handle
   * @returns true if endpoint detected
   */
  isSTTEndpoint(streamHandle: number): boolean;

  /**
   * Signal that audio input is finished.
   * @param streamHandle Stream handle
   */
  finishSTTInput(streamHandle: number): void;

  /**
   * Reset an STT stream for new audio.
   * @param streamHandle Stream handle
   */
  resetSTTStream(streamHandle: number): void;

  /**
   * Destroy an STT stream.
   * @param streamHandle Stream handle
   */
  destroySTTStream(streamHandle: number): void;

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  /**
   * Load a TTS model.
   * @param path Path to the model directory
   * @param modelType Model type ("piper", "coqui", "bark")
   * @param configJson Optional JSON configuration
   * @returns true if model loaded successfully
   */
  loadTTSModel(path: string, modelType: string, configJson: string | null): boolean;

  /**
   * Check if a TTS model is loaded.
   * @returns true if loaded
   */
  isTTSModelLoaded(): boolean;

  /**
   * Unload the current TTS model.
   * @returns true if unloaded successfully
   */
  unloadTTSModel(): boolean;

  /**
   * Synthesize speech from text.
   * @param text Text to synthesize
   * @param voiceId Optional voice ID
   * @param speedRate Speed rate (1.0 = normal)
   * @param pitchShift Pitch shift in semitones
   * @returns JSON with base64 audio and metadata
   */
  synthesize(
    text: string,
    voiceId: string | null,
    speedRate: number,
    pitchShift: number
  ): string;

  /**
   * Check if TTS supports streaming.
   * @returns true if streaming is supported
   */
  supportsTTSStreaming(): boolean;

  /**
   * Start streaming TTS synthesis.
   * Audio chunks are emitted via the 'onTTSAudio' event.
   * @param text Text to synthesize
   * @param voiceId Optional voice ID
   * @param speedRate Speed rate
   * @param pitchShift Pitch shift
   */
  synthesizeStream(
    text: string,
    voiceId: string | null,
    speedRate: number,
    pitchShift: number
  ): void;

  /**
   * Get available TTS voices.
   * @returns JSON array of voice info objects
   */
  getTTSVoices(): string;

  /**
   * Cancel ongoing TTS synthesis.
   */
  cancelTTS(): void;

  // ============================================================================
  // Voice Activity Detection (VAD)
  // ============================================================================

  /**
   * Load a VAD model.
   * @param path Path to the model file
   * @param configJson Optional JSON configuration
   * @returns true if model loaded successfully
   */
  loadVADModel(path: string, configJson: string | null): boolean;

  /**
   * Check if a VAD model is loaded.
   * @returns true if loaded
   */
  isVADModelLoaded(): boolean;

  /**
   * Unload the current VAD model.
   * @returns true if unloaded successfully
   */
  unloadVADModel(): boolean;

  /**
   * Process audio chunk for voice activity.
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @returns JSON with {isSpeech: boolean, probability: number}
   */
  processVAD(audioBase64: string, sampleRate: number): string;

  /**
   * Detect speech segments in audio.
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @returns JSON array of {startMs, endMs} segments
   */
  detectVADSegments(audioBase64: string, sampleRate: number): string;

  /**
   * Reset VAD state.
   */
  resetVAD(): void;

  // ============================================================================
  // Embeddings
  // ============================================================================

  /**
   * Load an embeddings model.
   * @param path Path to the model file
   * @param configJson Optional JSON configuration
   * @returns true if model loaded successfully
   */
  loadEmbeddingsModel(path: string, configJson: string | null): boolean;

  /**
   * Check if an embeddings model is loaded.
   * @returns true if loaded
   */
  isEmbeddingsModelLoaded(): boolean;

  /**
   * Unload the current embeddings model.
   * @returns true if unloaded successfully
   */
  unloadEmbeddingsModel(): boolean;

  /**
   * Generate embedding for a single text.
   * @param text Input text
   * @returns JSON with embedding array
   */
  embedText(text: string): string;

  /**
   * Generate embeddings for multiple texts.
   * @param texts Array of input texts
   * @returns JSON with array of embeddings
   */
  embedBatch(texts: string[]): string;

  /**
   * Get the embedding dimension.
   * @returns Number of dimensions
   */
  getEmbeddingDimensions(): number;

  // ============================================================================
  // Speaker Diarization
  // ============================================================================

  /**
   * Load a diarization model.
   * @param path Path to the model file
   * @param configJson Optional JSON configuration
   * @returns true if model loaded successfully
   */
  loadDiarizationModel(path: string, configJson: string | null): boolean;

  /**
   * Check if a diarization model is loaded.
   * @returns true if loaded
   */
  isDiarizationModelLoaded(): boolean;

  /**
   * Unload the current diarization model.
   * @returns true if unloaded successfully
   */
  unloadDiarizationModel(): boolean;

  /**
   * Perform speaker diarization on audio.
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @param minSpeakers Minimum expected speakers (0 for auto)
   * @param maxSpeakers Maximum expected speakers (0 for auto)
   * @returns JSON with speaker segments
   */
  diarize(
    audioBase64: string,
    sampleRate: number,
    minSpeakers: number,
    maxSpeakers: number
  ): string;

  /**
   * Cancel ongoing diarization.
   */
  cancelDiarization(): void;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get the last error message.
   * @returns Error message string
   */
  getLastError(): string;

  /**
   * Get the library version.
   * @returns Version string
   */
  getVersion(): string;

  /**
   * Extract an archive to a directory.
   * @param archivePath Path to the archive file
   * @param destDir Destination directory
   * @returns true if extraction succeeded
   */
  extractArchive(archivePath: string, destDir: string): boolean;

  // ============================================================================
  // Event Listener Registration (for New Architecture)
  // ============================================================================

  /**
   * Add event listener for native events.
   * Required for TurboModules that emit events.
   */
  addListener(eventName: string): void;

  /**
   * Remove event listeners.
   * Required for TurboModules that emit events.
   */
  removeListeners(count: number): void;
}

// Export the native module with enforced type safety
export default TurboModuleRegistry.getEnforcing<Spec>('RunAnywhere');
