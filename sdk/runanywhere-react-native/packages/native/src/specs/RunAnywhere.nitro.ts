/**
 * RunAnywhere Nitrogen Spec
 *
 * Defines the native interface for the RunAnywhere SDK.
 * Nitrogen will generate C++ bridges from this TypeScript interface.
 *
 * This is implemented in C++ (HybridRunAnywhere.cpp) and works on both iOS and Android.
 *
 * API alignment with Swift SDK:
 * - RunAnywhere.swift (main entry point)
 * - CppBridge extensions (LLM, STT, TTS, VAD, VoiceAgent, etc.)
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Main RunAnywhere native interface
 *
 * All methods here are implemented in C++ and call runanywhere-commons/core APIs.
 */
export interface RunAnywhere
  extends HybridObject<{
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
  // Matches Swift: CppBridge+LLM.swift, RunAnywhere+TextGeneration.swift
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
  // Structured Output (LLM with JSON Schema)
  // Matches Swift: RunAnywhere+StructuredOutput.swift
  // ============================================================================

  /**
   * Generate structured output following a JSON schema
   * @param prompt The prompt text
   * @param schema JSON schema string defining the output structure
   * @param optionsJson Optional generation options
   * @returns JSON string with structured result
   */
  generateStructured(
    prompt: string,
    schema: string,
    optionsJson?: string
  ): Promise<string>;

  // ============================================================================
  // Speech-to-Text (STT)
  // Matches Swift: CppBridge+STT.swift, RunAnywhere+STT.swift
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
  // Matches Swift: CppBridge+TTS.swift, RunAnywhere+TTS.swift
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
  // Voice Activity Detection (VAD)
  // Matches Swift: CppBridge+VAD.swift, RunAnywhere+VAD.swift
  // ============================================================================

  /**
   * Load a VAD model
   * @param path Path to the VAD model
   * @param configJson Optional configuration JSON
   * @returns true if loaded successfully
   */
  loadVADModel(path: string, configJson?: string): Promise<boolean>;

  /**
   * Check if VAD model is loaded
   */
  isVADModelLoaded(): Promise<boolean>;

  /**
   * Unload the current VAD model
   */
  unloadVADModel(): Promise<boolean>;

  /**
   * Process audio for voice activity detection
   * @param audioBase64 Base64-encoded audio data
   * @param optionsJson Optional processing options
   * @returns JSON string with VAD result (speech probability, segments)
   */
  processVAD(audioBase64: string, optionsJson?: string): Promise<string>;

  /**
   * Reset VAD state (for continuous processing)
   */
  resetVAD(): Promise<void>;

  // ============================================================================
  // Voice Agent (Full Voice Pipeline)
  // Matches Swift: CppBridge+VoiceAgent.swift, RunAnywhere+VoiceAgent.swift
  // ============================================================================

  /**
   * Initialize voice agent with configuration
   * @param configJson Configuration JSON with STT/LLM/TTS model IDs
   * @returns true if initialized successfully
   */
  initializeVoiceAgent(configJson: string): Promise<boolean>;

  /**
   * Initialize voice agent using already-loaded models
   * Uses the current STT, LLM, and TTS models
   * @returns true if initialized successfully
   */
  initializeVoiceAgentWithLoadedModels(): Promise<boolean>;

  /**
   * Check if voice agent is ready (all components initialized)
   */
  isVoiceAgentReady(): Promise<boolean>;

  /**
   * Get voice agent component states
   * @returns JSON with STT/LLM/TTS load states
   */
  getVoiceAgentComponentStates(): Promise<string>;

  /**
   * Process a complete voice turn: audio -> transcription -> response -> speech
   * @param audioBase64 Base64-encoded audio input
   * @returns JSON with transcription, response, and synthesized audio
   */
  processVoiceTurn(audioBase64: string): Promise<string>;

  /**
   * Transcribe audio using voice agent (voice agent must be initialized)
   * @param audioBase64 Base64-encoded audio
   * @returns Transcription text
   */
  voiceAgentTranscribe(audioBase64: string): Promise<string>;

  /**
   * Generate response using voice agent LLM
   * @param prompt Input text
   * @returns Generated response text
   */
  voiceAgentGenerateResponse(prompt: string): Promise<string>;

  /**
   * Synthesize speech using voice agent TTS
   * @param text Text to synthesize
   * @returns Base64-encoded audio data
   */
  voiceAgentSynthesizeSpeech(text: string): Promise<string>;

  /**
   * Cleanup voice agent resources
   */
  cleanupVoiceAgent(): Promise<void>;

  // ============================================================================
  // Model Assignment
  // Matches Swift: CppBridge+ModelAssignment.swift
  // ============================================================================

  /**
   * Assign a model to a specific framework
   * @param modelId Model identifier
   * @param framework Framework to use (e.g., 'llamacpp', 'onnx')
   * @returns true if assignment successful
   */
  assignModel(modelId: string, framework: string): Promise<boolean>;

  /**
   * Get current framework assignment for a model
   * @param modelId Model identifier
   * @returns Framework name or empty if not assigned
   */
  getModelAssignment(modelId: string): Promise<string>;

  /**
   * Clear all model assignments
   */
  clearModelAssignments(): Promise<void>;

  // ============================================================================
  // Model Registry
  // Matches Swift: CppBridge+ModelRegistry.swift
  // ============================================================================

  /**
   * Get list of available models
   * @returns JSON array of model info
   */
  getAvailableModels(): Promise<string>;

  /**
   * Get info for a specific model
   * @param modelId Model identifier
   * @returns JSON with model info
   */
  getModelInfo(modelId: string): Promise<string>;

  /**
   * Check if a model is downloaded
   * @param modelId Model identifier
   * @returns true if model exists locally
   */
  isModelDownloaded(modelId: string): Promise<boolean>;

  /**
   * Get local path for a model
   * @param modelId Model identifier
   * @returns Local file path or empty if not downloaded
   */
  getModelPath(modelId: string): Promise<string>;

  // ============================================================================
  // Download Service
  // Matches Swift: CppBridge+Download.swift
  // ============================================================================

  /**
   * Download a model
   * @param modelId Model identifier
   * @param url Download URL
   * @param destPath Destination path
   * @returns true if download started successfully
   */
  downloadModel(
    modelId: string,
    url: string,
    destPath: string
  ): Promise<boolean>;

  /**
   * Cancel an ongoing download
   * @param modelId Model identifier
   * @returns true if cancelled
   */
  cancelDownload(modelId: string): Promise<boolean>;

  /**
   * Get download progress
   * @param modelId Model identifier
   * @returns JSON with progress info (bytes, total, percentage)
   */
  getDownloadProgress(modelId: string): Promise<string>;

  // ============================================================================
  // Authentication
  // Matches Swift: CppBridge+Auth.swift
  // ============================================================================

  /**
   * Authenticate with API key
   * @param apiKey API key
   * @returns true if authenticated successfully
   */
  authenticate(apiKey: string): Promise<boolean>;

  /**
   * Check if currently authenticated
   */
  isAuthenticated(): Promise<boolean>;

  /**
   * Get current user ID
   * @returns User ID or empty if not authenticated
   */
  getUserId(): Promise<string>;

  /**
   * Get current organization ID
   * @returns Organization ID or empty if not authenticated
   */
  getOrganizationId(): Promise<string>;

  // ============================================================================
  // Device Registration
  // Matches Swift: CppBridge+Device.swift
  // ============================================================================

  /**
   * Register device with backend
   * @param environmentJson Environment configuration JSON
   * @returns true if registered successfully
   */
  registerDevice(environmentJson: string): Promise<boolean>;

  /**
   * Check if device is registered
   */
  isDeviceRegistered(): Promise<boolean>;

  // ============================================================================
  // HTTP Client
  // Matches Swift: CppBridge+HTTP.swift
  // ============================================================================

  /**
   * Configure HTTP client
   * @param baseUrl Base URL for API
   * @param apiKey API key for authentication
   * @returns true if configured successfully
   */
  configureHttp(baseUrl: string, apiKey: string): Promise<boolean>;

  /**
   * Make HTTP POST request
   * @param path API path
   * @param bodyJson Request body JSON
   * @returns Response JSON
   */
  httpPost(path: string, bodyJson: string): Promise<string>;

  /**
   * Make HTTP GET request
   * @param path API path
   * @returns Response JSON
   */
  httpGet(path: string): Promise<string>;

  // ============================================================================
  // Events
  // Matches Swift: CppBridge+Events.swift
  // ============================================================================

  /**
   * Emit an event to the native event system
   * @param eventJson Event JSON with type, category, data
   */
  emitEvent(eventJson: string): Promise<void>;

  /**
   * Poll for pending events from native
   * @returns JSON array of events
   */
  pollEvents(): Promise<string>;

  // ============================================================================
  // Storage
  // Matches Swift: RunAnywhere+Storage.swift
  // ============================================================================

  /**
   * Get storage info (disk usage, available space)
   * @returns JSON with storage info
   */
  getStorageInfo(): Promise<string>;

  /**
   * Clear model cache
   * @returns true if cleared successfully
   */
  clearCache(): Promise<boolean>;

  /**
   * Delete a specific model
   * @param modelId Model identifier
   * @returns true if deleted successfully
   */
  deleteModel(modelId: string): Promise<boolean>;

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

  // ============================================================================
  // Backend Registration
  // Matches Swift: LlamaCPP.register(), ONNX.register()
  // ============================================================================

  /**
   * Register the LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() from runanywhere-core.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerLlamaCppBackend(): Promise<boolean>;

  /**
   * Unregister the LlamaCPP backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterLlamaCppBackend(): Promise<boolean>;

  /**
   * Register the ONNX backend with the C++ service registry.
   * Calls rac_backend_onnx_register() from runanywhere-core.
   * Registers STT, TTS, and VAD providers.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerONNXBackend(): Promise<boolean>;

  /**
   * Unregister the ONNX backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterONNXBackend(): Promise<boolean>;
}
