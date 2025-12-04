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
   * @returns Promise that resolves to true if backend was created successfully
   */
  createBackend(name: string): Promise<boolean>;

  /**
   * Initialize the backend with optional configuration.
   * @param configJson Optional JSON configuration string
   * @returns Promise that resolves to true if initialization succeeded
   */
  initialize(configJson: string | null): Promise<boolean>;

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
   * @returns Promise that resolves to JSON string with backend info
   */
  getBackendInfo(): Promise<string>;

  // ============================================================================
  // Capability Query
  // ============================================================================

  /**
   * Check if the backend supports a specific capability.
   * @param capability Capability type (from CapabilityType enum)
   * @returns Promise that resolves to true if supported
   */
  supportsCapability(capability: number): Promise<boolean>;

  /**
   * Get all supported capabilities.
   * @returns Promise that resolves to array of capability type numbers
   */
  getCapabilities(): Promise<number[]>;

  /**
   * Get the device type being used for inference.
   * @returns Promise that resolves to device type number (from DeviceType enum)
   */
  getDeviceType(): Promise<number>;

  /**
   * Get current memory usage in bytes.
   * @returns Promise that resolves to memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /**
   * Load a text generation model.
   * @param path Path to the model file
   * @param configJson Optional JSON configuration
   * @returns Promise that resolves to true if model loaded successfully
   */
  loadTextModel(path: string, configJson: string | null): Promise<boolean>;

  /**
   * Check if a text model is loaded.
   * @returns Promise that resolves to true if loaded
   */
  isTextModelLoaded(): Promise<boolean>;

  /**
   * Unload the current text model.
   * @returns Promise that resolves to true if unloaded successfully
   */
  unloadTextModel(): Promise<boolean>;

  /**
   * Generate text synchronously.
   * @param prompt The input prompt
   * @param systemPrompt Optional system prompt
   * @param maxTokens Maximum tokens to generate
   * @param temperature Sampling temperature
   * @returns Promise that resolves to JSON string with generation result
   */
  generate(
    prompt: string,
    systemPrompt: string | null,
    maxTokens: number,
    temperature: number
  ): Promise<string>;

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
   * @returns Promise that resolves to true if model loaded successfully
   */
  loadSTTModel(path: string, modelType: string, configJson: string | null): Promise<boolean>;

  /**
   * Check if an STT model is loaded.
   * @returns Promise that resolves to true if loaded
   */
  isSTTModelLoaded(): Promise<boolean>;

  /**
   * Unload the current STT model.
   * @returns Promise that resolves to true if unloaded successfully
   */
  unloadSTTModel(): Promise<boolean>;

  /**
   * Transcribe audio data (batch mode).
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate (e.g., 16000)
   * @param language Optional language code (e.g., "en")
   * @returns Promise that resolves to JSON string with transcription result
   */
  transcribe(audioBase64: string, sampleRate: number, language: string | null): Promise<string>;

  /**
   * Transcribe audio from a file path.
   * Automatically handles format conversion to 16kHz mono PCM.
   * Supports various audio formats (M4A, AAC, WAV, CAF, etc.)
   * @param filePath Path to the audio file
   * @param language Optional language code (e.g., "en")
   * @returns Promise that resolves to JSON string with transcription result
   */
  transcribeFile(filePath: string, language: string | null): Promise<string>;

  /**
   * Check if STT supports streaming.
   * @returns Promise that resolves to true if streaming is supported
   */
  supportsSTTStreaming(): Promise<boolean>;

  /**
   * Create a new STT stream for real-time transcription.
   * @param configJson Optional JSON configuration
   * @returns Promise that resolves to stream handle ID (or -1 on error)
   */
  createSTTStream(configJson: string | null): Promise<number>;

  /**
   * Feed audio data to an STT stream.
   * @param streamHandle Stream handle from createSTTStream
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @returns Promise that resolves to true if audio was fed successfully
   */
  feedSTTAudio(streamHandle: number, audioBase64: string, sampleRate: number): Promise<boolean>;

  /**
   * Decode current STT stream state.
   * @param streamHandle Stream handle
   * @returns Promise that resolves to JSON string with partial transcription
   */
  decodeSTT(streamHandle: number): Promise<string>;

  /**
   * Check if STT stream is ready to decode.
   * @param streamHandle Stream handle
   * @returns Promise that resolves to true if ready
   */
  isSTTReady(streamHandle: number): Promise<boolean>;

  /**
   * Check if STT stream detected end of speech.
   * @param streamHandle Stream handle
   * @returns Promise that resolves to true if endpoint detected
   */
  isSTTEndpoint(streamHandle: number): Promise<boolean>;

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
   * @returns Promise that resolves to true if model loaded successfully
   */
  loadTTSModel(path: string, modelType: string, configJson: string | null): Promise<boolean>;

  /**
   * Check if a TTS model is loaded.
   * @returns Promise that resolves to true if loaded
   */
  isTTSModelLoaded(): Promise<boolean>;

  /**
   * Unload the current TTS model.
   * @returns Promise that resolves to true if unloaded successfully
   */
  unloadTTSModel(): Promise<boolean>;

  /**
   * Synthesize speech from text.
   * @param text Text to synthesize
   * @param voiceId Optional voice ID
   * @param speedRate Speed rate (1.0 = normal)
   * @param pitchShift Pitch shift in semitones
   * @returns Promise that resolves to JSON with base64 audio and metadata
   */
  synthesize(
    text: string,
    voiceId: string | null,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;

  /**
   * Check if TTS supports streaming.
   * @returns Promise that resolves to true if streaming is supported
   */
  supportsTTSStreaming(): Promise<boolean>;

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
   * @returns Promise that resolves to JSON array of voice info objects
   */
  getTTSVoices(): Promise<string>;

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
   * @returns Promise that resolves to true if model loaded successfully
   */
  loadVADModel(path: string, configJson: string | null): Promise<boolean>;

  /**
   * Check if a VAD model is loaded.
   * @returns Promise that resolves to true if loaded
   */
  isVADModelLoaded(): Promise<boolean>;

  /**
   * Unload the current VAD model.
   * @returns Promise that resolves to true if unloaded successfully
   */
  unloadVADModel(): Promise<boolean>;

  /**
   * Process audio chunk for voice activity.
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @returns Promise that resolves to JSON with {isSpeech: boolean, probability: number}
   */
  processVAD(audioBase64: string, sampleRate: number): Promise<string>;

  /**
   * Detect speech segments in audio.
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @returns Promise that resolves to JSON array of {startMs, endMs} segments
   */
  detectVADSegments(audioBase64: string, sampleRate: number): Promise<string>;

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
   * @returns Promise that resolves to true if model loaded successfully
   */
  loadEmbeddingsModel(path: string, configJson: string | null): Promise<boolean>;

  /**
   * Check if an embeddings model is loaded.
   * @returns Promise that resolves to true if loaded
   */
  isEmbeddingsModelLoaded(): Promise<boolean>;

  /**
   * Unload the current embeddings model.
   * @returns Promise that resolves to true if unloaded successfully
   */
  unloadEmbeddingsModel(): Promise<boolean>;

  /**
   * Generate embedding for a single text.
   * @param text Input text
   * @returns Promise that resolves to JSON with embedding array
   */
  embedText(text: string): Promise<string>;

  /**
   * Generate embeddings for multiple texts.
   * @param texts Array of input texts
   * @returns Promise that resolves to JSON with array of embeddings
   */
  embedBatch(texts: string[]): Promise<string>;

  /**
   * Get the embedding dimension.
   * @returns Promise that resolves to number of dimensions
   */
  getEmbeddingDimensions(): Promise<number>;

  // ============================================================================
  // Speaker Diarization
  // ============================================================================

  /**
   * Load a diarization model.
   * @param path Path to the model file
   * @param configJson Optional JSON configuration
   * @returns Promise that resolves to true if model loaded successfully
   */
  loadDiarizationModel(path: string, configJson: string | null): Promise<boolean>;

  /**
   * Check if a diarization model is loaded.
   * @returns Promise that resolves to true if loaded
   */
  isDiarizationModelLoaded(): Promise<boolean>;

  /**
   * Unload the current diarization model.
   * @returns Promise that resolves to true if unloaded successfully
   */
  unloadDiarizationModel(): Promise<boolean>;

  /**
   * Perform speaker diarization on audio.
   * @param audioBase64 Base64-encoded float32 audio samples
   * @param sampleRate Audio sample rate
   * @param minSpeakers Minimum expected speakers (0 for auto)
   * @param maxSpeakers Maximum expected speakers (0 for auto)
   * @returns Promise that resolves to JSON with speaker segments
   */
  diarize(
    audioBase64: string,
    sampleRate: number,
    minSpeakers: number,
    maxSpeakers: number
  ): Promise<string>;

  /**
   * Cancel ongoing diarization.
   */
  cancelDiarization(): void;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get the last error message.
   * @returns Promise that resolves to error message string
   */
  getLastError(): Promise<string>;

  /**
   * Get the library version.
   * @returns Promise that resolves to version string
   */
  getVersion(): Promise<string>;

  /**
   * Extract an archive to a directory.
   * @param archivePath Path to the archive file
   * @param destDir Destination directory
   * @returns Promise that resolves to true if extraction succeeded
   */
  extractArchive(archivePath: string, destDir: string): Promise<boolean>;

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

  /**
   * Poll for queued events from native.
   * Returns a JSON array of pending events.
   * This is called from JavaScript to retrieve events that were queued
   * by native operations (e.g., streaming generation, STT streams).
   * @returns Promise that resolves to JSON array string of events
   */
  pollEvents(): Promise<string>;

  /**
   * Clear all pending events in the queue.
   * Useful for cleanup during component unmount or when switching operations.
   */
  clearEventQueue(): void;
}

// Export the native module with enforced type safety
export default TurboModuleRegistry.getEnforcing<Spec>('RunAnywhere');
