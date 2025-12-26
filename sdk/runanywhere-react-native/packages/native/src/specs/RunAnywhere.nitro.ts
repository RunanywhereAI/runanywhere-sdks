/**
 * RunAnywhere Nitrogen Spec
 *
 * Defines the native interface for the RunAnywhere SDK.
 * Nitrogen will generate C++ bridges from this TypeScript interface.
 *
 * This is implemented in C++ (HybridRunAnywhere.cpp) and works on both iOS and Android.
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Main RunAnywhere native interface
 *
 * All methods here are implemented in C++ and call runanywhere-core APIs.
 */
export interface RunAnywhere extends HybridObject<{
  ios: 'c++';
  android: 'c++';
}> {
  // ============================================================================
  // Backend Lifecycle
  // ============================================================================

  /**
   * Create a backend (e.g., 'onnx', 'llamacpp')
   * @param name Backend name
   * @returns true if backend was created successfully
   */
  createBackend(name: string): Promise<boolean>;

  /**
   * Initialize the SDK with configuration
   * @param configJson JSON string with apiKey, baseURL, environment
   * @returns true if initialized successfully
   */
  initialize(configJson: string): Promise<boolean>;

  /**
   * Destroy the backend and clean up resources
   */
  destroy(): Promise<void>;

  /**
   * Check if SDK is initialized
   */
  isInitialized(): Promise<boolean>;

  /**
   * Get backend info as JSON string
   */
  getBackendInfo(): Promise<string>;

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /**
   * Load a text generation model
   * @param path Path to the model file (.gguf)
   * @param configJson Optional JSON configuration
   */
  loadTextModel(path: string, configJson?: string): Promise<boolean>;

  /**
   * Check if a text model is loaded
   */
  isTextModelLoaded(): Promise<boolean>;

  /**
   * Unload the current text model
   */
  unloadTextModel(): Promise<boolean>;

  /**
   * Generate text (non-streaming)
   * Matches Swift SDK: RunAnywhere.generate(_:options:)
   * @param prompt The prompt text
   * @param optionsJson JSON string with generation options (max_tokens, temperature, system_prompt)
   * @returns JSON string with generation result
   */
  generate(prompt: string, optionsJson?: string): Promise<string>;

  /**
   * Generate text with streaming callback
   * Matches Swift SDK: RunAnywhere.generateStream(_:options:)
   * @param prompt The prompt text
   * @param optionsJson JSON string with generation options
   * @param callback Called for each token
   */
  generateStream(
    prompt: string,
    optionsJson: string,
    callback: (token: string, isComplete: boolean) => void
  ): Promise<string>;

  /**
   * Cancel ongoing text generation
   */
  cancelGeneration(): Promise<boolean>;

  // ============================================================================
  // Speech-to-Text (STT)
  // ============================================================================

  /**
   * Load an STT model
   * @param path Path to the model directory
   * @param modelType Model type (e.g., 'whisper')
   * @param configJson Optional JSON configuration
   */
  loadSTTModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;

  /**
   * Check if an STT model is loaded
   */
  isSTTModelLoaded(): Promise<boolean>;

  /**
   * Unload the current STT model
   */
  unloadSTTModel(): Promise<boolean>;

  /**
   * Transcribe audio data
   * @param audioBase64 Base64-encoded float32 PCM audio
   * @param sampleRate Audio sample rate (e.g., 16000)
   * @param language Language code (e.g., 'en')
   * @returns JSON string with transcription result
   */
  transcribe(
    audioBase64: string,
    sampleRate: number,
    language?: string
  ): Promise<string>;

  /**
   * Transcribe audio from a file path
   * Native code handles M4A/WAV/CAF to PCM conversion
   * @param filePath Path to the audio file
   * @param language Language code (e.g., 'en')
   * @returns JSON string with transcription result
   */
  transcribeFile(filePath: string, language?: string): Promise<string>;

  /**
   * Check if STT supports streaming
   */
  supportsSTTStreaming(): Promise<boolean>;

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  /**
   * Load a TTS model
   * @param path Path to the model directory
   * @param modelType Model type (e.g., 'piper', 'vits')
   * @param configJson Optional JSON configuration
   */
  loadTTSModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;

  /**
   * Check if a TTS model is loaded
   */
  isTTSModelLoaded(): Promise<boolean>;

  /**
   * Unload the current TTS model
   */
  unloadTTSModel(): Promise<boolean>;

  /**
   * Synthesize speech from text
   * @param text Text to synthesize
   * @param voiceId Optional voice ID
   * @param speedRate Speed multiplier (1.0 = normal)
   * @param pitchShift Pitch adjustment
   * @returns JSON string with audio data (base64) and metadata
   */
  synthesize(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;

  /**
   * Get available TTS voices
   * @returns JSON string with voice list
   */
  getTTSVoices(): Promise<string>;

  // ============================================================================
  // Utility Functions
  // ============================================================================

  /**
   * Get the last error message
   */
  getLastError(): Promise<string>;

  /**
   * Extract an archive (tar.bz2, tar.gz, zip)
   * @param archivePath Path to the archive
   * @param destPath Destination directory
   */
  extractArchive(archivePath: string, destPath: string): Promise<boolean>;

  /**
   * Get device capabilities
   * @returns JSON string with device info
   */
  getDeviceCapabilities(): Promise<string>;

  /**
   * Get memory usage
   * @returns Current memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;
}
