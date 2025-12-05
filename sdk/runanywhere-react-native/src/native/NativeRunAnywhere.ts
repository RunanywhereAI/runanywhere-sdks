/**
 * RunAnywhere React Native SDK - Native Module Interface
 *
 * Type definitions for the native module bridge.
 * These types define the interface between JS and native code.
 *
 * IMPORTANT: This interface must match the methods exposed in:
 * - ios/RunAnywhere.mm (RCT_EXPORT_METHOD declarations)
 * - cpp/RunAnywhereModule.cpp (TurboModule get() method)
 */

// No longer needed - using codegen-generated module directly
// import { NativeModules, Platform, TurboModuleRegistry } from 'react-native';

/**
 * Native module interface
 * Defines all methods exposed by the native module
 *
 * These match the C API functions in runanywhere-core
 */
export interface NativeRunAnywhereModule {
  // ============================================================================
  // Backend Lifecycle
  // ============================================================================

  /**
   * Create a backend (e.g., 'onnx', 'llamacpp')
   * @returns true if backend was created successfully
   */
  createBackend(name: string): Promise<boolean>;

  /**
   * Initialize the SDK with JSON config string
   * @param configJson JSON string containing apiKey, baseURL, environment
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
  // Capability Query
  // ============================================================================

  /**
   * Check if a capability is supported
   * @param capability - Capability type enum value
   */
  supportsCapability(capability: number): Promise<boolean>;

  /**
   * Get list of supported capabilities
   * @returns Array of capability type enum values
   */
  getCapabilities(): Promise<number[]>;

  /**
   * Get device type (CPU, GPU, NPU, etc.)
   */
  getDeviceType(): Promise<number>;

  /**
   * Get current memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /**
   * Load a text generation model
   * @param path - Path to the model file
   * @param configJson - Optional JSON configuration
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
   * Generate text (synchronous, returns full result)
   * @param prompt - Input prompt
   * @param systemPrompt - Optional system prompt
   * @param maxTokens - Maximum tokens to generate
   * @param temperature - Sampling temperature
   * @returns JSON string with generation result
   */
  generate(
    prompt: string,
    systemPrompt: string | null,
    maxTokens: number,
    temperature: number
  ): Promise<string>;

  /**
   * Start streaming text generation
   * Tokens are delivered via events (onToken, onGenerationComplete, onGenerationError)
   */
  generateStream(
    prompt: string,
    systemPrompt: string | null,
    maxTokens: number,
    temperature: number
  ): void;

  /**
   * Cancel ongoing text generation
   */
  cancelGeneration(): void;

  // ============================================================================
  // Speech-to-Text (STT)
  // ============================================================================

  /**
   * Load an STT model
   * @param path - Path to the model file
   * @param modelType - Model type (e.g., 'whisper', 'sherpa')
   * @param configJson - Optional JSON configuration
   */
  loadSTTModel(path: string, modelType: string, configJson?: string): Promise<boolean>;

  /**
   * Check if an STT model is loaded
   */
  isSTTModelLoaded(): Promise<boolean>;

  /**
   * Unload the current STT model
   */
  unloadSTTModel(): Promise<boolean>;

  /**
   * Transcribe audio (batch mode)
   * @param audioBase64 - Base64 encoded float32 audio samples
   * @param sampleRate - Audio sample rate
   * @param language - Optional language code
   * @returns JSON string with transcription result
   */
  transcribe(audioBase64: string, sampleRate: number, language?: string): Promise<string>;

  /**
   * Transcribe audio from a file path.
   * Automatically handles format conversion to 16kHz mono PCM.
   * @param filePath - Path to the audio file
   * @param language - Optional language code (e.g., "en")
   * @returns JSON string with transcription result
   */
  transcribeFile(filePath: string, language: string | null): Promise<string>;

  /**
   * Check if STT streaming is supported
   */
  supportsSTTStreaming(): Promise<boolean>;

  /**
   * Create an STT streaming session
   * @param configJson - Optional JSON configuration
   * @returns Stream handle ID (-1 if failed)
   */
  createSTTStream(configJson?: string): Promise<number>;

  /**
   * Feed audio to an STT stream
   * @param streamHandle - Stream handle from createSTTStream
   * @param audioBase64 - Base64 encoded float32 audio samples
   * @param sampleRate - Audio sample rate
   */
  feedSTTAudio(streamHandle: number, audioBase64: string, sampleRate: number): Promise<boolean>;

  /**
   * Decode current STT stream state
   * @param streamHandle - Stream handle
   * @returns JSON string with current transcription
   */
  decodeSTT(streamHandle: number): Promise<string>;

  /**
   * Check if STT stream has result ready
   */
  isSTTReady(streamHandle: number): Promise<boolean>;

  /**
   * Check if STT stream detected end of speech
   */
  isSTTEndpoint(streamHandle: number): Promise<boolean>;

  /**
   * Signal that input is finished for STT stream
   */
  finishSTTInput(streamHandle: number): void;

  /**
   * Reset STT stream state
   */
  resetSTTStream(streamHandle: number): void;

  /**
   * Destroy an STT stream
   */
  destroySTTStream(streamHandle: number): void;

  // ============================================================================
  // Streaming STT (AVAudioEngine-based, matching Swift SDK pattern)
  // ============================================================================

  /**
   * Start streaming speech-to-text transcription
   * Uses AVAudioEngine for real-time audio capture at 16kHz mono
   * Results are delivered via onSTTPartial and onSTTFinal events
   * @param language - Language code (e.g., "en")
   * @returns true if streaming started successfully
   */
  startStreamingSTT(language: string): Promise<boolean>;

  /**
   * Stop streaming speech-to-text transcription
   * Final transcription result (if any) will be emitted via onSTTFinal event
   * @returns true if streaming was stopped successfully
   */
  stopStreamingSTT(): Promise<boolean>;

  /**
   * Check if streaming STT is currently active
   * @returns true if streaming is active
   */
  isStreamingSTT(): Promise<boolean>;

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  /**
   * Load a TTS model
   * @param path - Path to the model file
   * @param modelType - Model type (e.g., 'piper', 'vits')
   * @param configJson - Optional JSON configuration
   */
  loadTTSModel(path: string, modelType: string, configJson?: string): Promise<boolean>;

  /**
   * Check if a TTS model is loaded
   */
  isTTSModelLoaded(): Promise<boolean>;

  /**
   * Unload the current TTS model
   */
  unloadTTSModel(): Promise<boolean>;

  /**
   * Synthesize text to speech
   * @param text - Text to synthesize
   * @param voiceId - Optional voice ID
   * @param speedRate - Speed rate (1.0 = normal)
   * @param pitchShift - Pitch shift (1.0 = normal)
   * @returns JSON string with {audio: base64, sampleRate: number, numSamples: number}
   */
  synthesize(
    text: string,
    voiceId: string | null,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;

  /**
   * Check if TTS streaming is supported
   */
  supportsTTSStreaming(): Promise<boolean>;

  /**
   * Get available TTS voices
   * @returns JSON string array of voice IDs
   */
  getTTSVoices(): Promise<string>;

  /**
   * Cancel ongoing TTS synthesis
   */
  cancelTTS(): void;

  // ============================================================================
  // Voice Activity Detection (VAD)
  // ============================================================================

  /**
   * Load a VAD model
   * @param path - Path to the model file
   * @param configJson - Optional JSON configuration
   */
  loadVADModel(path: string, configJson?: string): Promise<boolean>;

  /**
   * Check if a VAD model is loaded
   */
  isVADModelLoaded(): Promise<boolean>;

  /**
   * Unload the current VAD model
   */
  unloadVADModel(): Promise<boolean>;

  /**
   * Process audio for voice activity detection
   * @param audioBase64 - Base64 encoded float32 audio samples
   * @param sampleRate - Audio sample rate
   * @returns JSON string with {isSpeech: boolean, probability: number}
   */
  processVAD(audioBase64: string, sampleRate: number): Promise<string>;

  /**
   * Detect speech segments in audio
   * @returns JSON array of segments with start/end times
   */
  detectVADSegments(audioBase64: string, sampleRate: number): Promise<string>;

  /**
   * Reset VAD state
   */
  resetVAD(): void;

  // ============================================================================
  // Embeddings
  // ============================================================================

  /**
   * Load an embeddings model
   */
  loadEmbeddingsModel(path: string, configJson?: string): Promise<boolean>;

  /**
   * Check if an embeddings model is loaded
   */
  isEmbeddingsModelLoaded(): Promise<boolean>;

  /**
   * Unload the current embeddings model
   */
  unloadEmbeddingsModel(): Promise<boolean>;

  /**
   * Generate embeddings for text
   * @returns JSON string with {embedding: number[], dimensions: number}
   */
  embedText(text: string): Promise<string>;

  /**
   * Get embedding dimensions
   */
  getEmbeddingDimensions(): Promise<number>;

  // ============================================================================
  // Diarization
  // ============================================================================

  /**
   * Load a diarization model
   */
  loadDiarizationModel(path: string, configJson?: string): Promise<boolean>;

  /**
   * Check if a diarization model is loaded
   */
  isDiarizationModelLoaded(): Promise<boolean>;

  /**
   * Unload the current diarization model
   */
  unloadDiarizationModel(): Promise<boolean>;

  /**
   * Perform speaker diarization
   * @param audioBase64 - Base64 encoded audio
   * @param sampleRate - Audio sample rate
   * @param minSpeakers - Minimum expected speakers
   * @param maxSpeakers - Maximum expected speakers
   * @returns JSON string with speaker segments
   */
  diarize(
    audioBase64: string,
    sampleRate: number,
    minSpeakers: number,
    maxSpeakers: number
  ): Promise<string>;

  /**
   * Cancel ongoing diarization
   */
  cancelDiarization(): void;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get last error message
   */
  getLastError(): Promise<string>;

  /**
   * Get SDK/library version
   */
  getVersion(): Promise<string>;

  /**
   * Extract an archive file
   */
  extractArchive(archivePath: string, destDir: string): Promise<boolean>;

  // ============================================================================
  // Model Registry
  // ============================================================================

  /**
   * Get available models from the catalog
   * @returns JSON string array of model info objects
   */
  getAvailableModels(): Promise<string>;

  /**
   * Get info for a specific model
   * @param modelId - Model ID
   * @returns JSON string with model info or "null"
   */
  getModelInfo(modelId: string): Promise<string>;

  /**
   * Check if a model is downloaded
   * @param modelId - Model ID
   */
  isModelDownloaded(modelId: string): Promise<boolean>;

  /**
   * Get local path for a downloaded model
   * @param modelId - Model ID
   * @returns Path or null if not downloaded
   */
  getModelPath(modelId: string): Promise<string | null>;

  /**
   * Get list of downloaded models
   * @returns JSON string array of downloaded model info objects
   */
  getDownloadedModels(): Promise<string>;

  // ============================================================================
  // Model Download
  // ============================================================================

  /**
   * Download a model
   * Progress is delivered via onModelDownloadProgress event
   * Completion via onModelDownloadComplete or onModelDownloadError
   * @param modelId - Model ID to download
   * @returns Model ID (task ID)
   */
  downloadModel(modelId: string): Promise<string>;

  /**
   * Cancel an ongoing download
   * @param modelId - Model ID being downloaded
   */
  cancelDownload(modelId: string): Promise<boolean>;

  /**
   * Delete a downloaded model
   * @param modelId - Model ID to delete
   */
  deleteModel(modelId: string): Promise<boolean>;

  // ============================================================================
  // Event Listeners (for EventEmitter)
  // ============================================================================

  /**
   * Add event listener
   */
  addListener(eventName: string): void;

  /**
   * Remove event listeners
   */
  removeListeners(count: number): void;

  // ============================================================================
  // Authentication (TODO: Implement in native module)
  // ============================================================================

  /**
   * Authenticate with API key
   */
  authenticate(apiKey: string): Promise<boolean>;

  /**
   * Get access token
   */
  getAccessToken(): Promise<string | null>;

  /**
   * Refresh access token
   */
  refreshAccessToken(): Promise<string | null>;

  /**
   * Check if authenticated
   */
  isAuthenticated(): Promise<boolean>;

  /**
   * Clear authentication
   */
  clearAuthentication(): Promise<void>;

  /**
   * Load stored tokens
   */
  loadStoredTokens(): Promise<boolean>;

  /**
   * Get user ID
   */
  getUserId(): Promise<string | null>;

  /**
   * Get organization ID
   */
  getOrganizationId(): Promise<string | null>;

  /**
   * Get device ID
   */
  getDeviceId(): Promise<string | null>;

  /**
   * Register device
   */
  registerDevice(deviceInfo: string): Promise<boolean>;

  /**
   * Health check
   */
  healthCheck(): Promise<boolean>;

  // ============================================================================
  // Configuration (TODO: Implement in native module)
  // ============================================================================

  /**
   * Get configuration
   */
  getConfiguration(): Promise<string>;

  /**
   * Load configuration on launch
   */
  loadConfigurationOnLaunch(): Promise<string>;

  /**
   * Set consumer configuration
   */
  setConsumerConfiguration(configJson: string): Promise<void>;

  /**
   * Update configuration
   */
  updateConfiguration(configJson: string): Promise<void>;

  /**
   * Sync configuration to cloud
   */
  syncConfigurationToCloud(): Promise<void>;

  /**
   * Clear configuration cache
   */
  clearConfigurationCache(): Promise<void>;

  /**
   * Get current environment
   */
  getCurrentEnvironment(): Promise<string>;

  // ============================================================================
  // Extended Download Operations (TODO: Implement in native module)
  // ============================================================================

  /**
   * Start model download (alias for downloadModel)
   */
  startModelDownload(modelId: string): Promise<string>;

  /**
   * Pause a download
   */
  pauseDownload(modelId: string): Promise<void>;

  /**
   * Resume a paused download
   */
  resumeDownload(modelId: string): Promise<void>;

  /**
   * Pause all downloads
   */
  pauseAllDownloads(): Promise<void>;

  /**
   * Resume all downloads
   */
  resumeAllDownloads(): Promise<void>;

  /**
   * Cancel all downloads
   */
  cancelAllDownloads(): Promise<void>;

  /**
   * Get download progress
   */
  getDownloadProgress(modelId: string): Promise<number>;

  /**
   * Configure download service
   */
  configureDownloadService(configJson: string): Promise<void>;

  /**
   * Check download service health
   */
  isDownloadServiceHealthy(): Promise<boolean>;

  /**
   * Get download resume data
   */
  getDownloadResumeData(modelId: string): Promise<string | null>;

  /**
   * Resume download with data
   */
  resumeDownloadWithData(modelId: string, resumeData: string): Promise<string>;

  // ============================================================================
  // Model Registry Extended (TODO: Implement in native module)
  // ============================================================================

  /**
   * Initialize registry
   */
  initializeRegistry(): Promise<void>;

  /**
   * Discover models
   */
  discoverModels(): Promise<string>;

  /**
   * Register model
   */
  registerModel(modelInfoJson: string): Promise<void>;

  /**
   * Register model persistently
   */
  registerModelPersistently(modelInfoJson: string): Promise<void>;

  /**
   * Get model by ID
   */
  getModel(modelId: string): Promise<string | null>;

  /**
   * Filter models
   */
  filterModels(filterJson: string): Promise<string>;

  /**
   * Update model
   */
  updateModel(modelId: string, updateJson: string): Promise<void>;

  /**
   * Remove model
   */
  removeModel(modelId: string): Promise<void>;

  /**
   * Add model from URL
   */
  addModelFromURL(url: string, metadataJson: string): Promise<string>;

  /**
   * Get available models (alternative name)
   */
  availableModels(): Promise<string>;
}

// Import the codegen-generated TurboModule
import CodegenNativeModule from '../NativeRunAnywhere';

/**
 * Native module instance
 * Uses the codegen-generated TurboModule for React Native New Architecture
 */
let nativeModule: NativeRunAnywhereModule | null = null;

try {
  nativeModule = CodegenNativeModule as unknown as NativeRunAnywhereModule;
  console.log('[NativeRunAnywhere] Successfully loaded codegen module:', nativeModule ? 'YES' : 'NO');

  // Debug: Log what methods are available
  if (nativeModule) {
    console.log('[NativeRunAnywhere] Module has createBackend?', typeof nativeModule.createBackend);
    console.log('[NativeRunAnywhere] Module has initialize?', typeof nativeModule.initialize);
    console.log('[NativeRunAnywhere] Available methods:', Object.keys(nativeModule).filter(k => typeof nativeModule[k as keyof typeof nativeModule] === 'function'));
  }
} catch (error) {
  console.error('[NativeRunAnywhere] Failed to load codegen module:', error);
  nativeModule = null;
}

export const NativeRunAnywhere = nativeModule;

/**
 * Check if native module is available
 */
export function isNativeModuleAvailable(): boolean {
  return NativeRunAnywhere !== null;
}

/**
 * Require native module (throws if not available)
 */
export function requireNativeModule(): NativeRunAnywhereModule {
  if (!NativeRunAnywhere) {
    throw new Error(
      '[RunAnywhere] Native module is not available. ' +
        'Make sure the native module is properly linked and you are running on a device or simulator.'
    );
  }
  return NativeRunAnywhere;
}
