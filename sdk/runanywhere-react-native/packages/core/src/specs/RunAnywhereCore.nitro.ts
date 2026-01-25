/**
 * RunAnywhereCore Nitrogen Spec
 *
 * Core SDK interface - includes:
 * - SDK Lifecycle (init, destroy)
 * - Authentication
 * - Device Registration
 * - Model Registry
 * - Download Service
 * - Storage
 * - Events
 * - HTTP Client
 * - Utilities
 * - LLM/STT/TTS/VAD capabilities (backend-agnostic via rac_*_component_* APIs)
 *
 * The capability methods (LLM, STT, TTS, VAD) are BACKEND-AGNOSTIC.
 * They call the C++ rac_*_component_* APIs which work with any registered backend.
 * Apps must install a backend package to register the actual implementation:
 * - @runanywhere/llamacpp registers the LLM backend
 * - @runanywhere/onnx registers the STT/TTS/VAD backends
 *
 * Matches Swift SDK: RunAnywhere.swift + CppBridge extensions
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Core RunAnywhere native interface
 *
 * This interface provides all SDK functionality using backend-agnostic C++ APIs.
 * Install backend packages to enable specific capabilities:
 * - @runanywhere/llamacpp for text generation (LLM)
 * - @runanywhere/onnx for speech processing (STT, TTS, VAD)
 */
export interface RunAnywhereCore
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  // ============================================================================
  // SDK Lifecycle
  // Matches Swift: CppBridge+Init.swift
  // ============================================================================

  /**
   * Initialize the SDK with configuration
   * @param configJson JSON string with apiKey, baseURL, environment
   * @returns true if initialized successfully
   */
  initialize(configJson: string): Promise<boolean>;

  /**
   * Destroy the SDK and clean up resources
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

  /**
   * Set authentication tokens directly (after JS-side authentication)
   * This stores the tokens in C++ AuthBridge for use by telemetry/device registration
   * @param authResponseJson JSON string with access_token, refresh_token, expires_in, etc.
   * @returns true if tokens were set successfully
   */
  setAuthTokens(authResponseJson: string): Promise<boolean>;

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

  /**
   * Clear device registration flag (for testing)
   * Forces re-registration on next SDK init
   */
  clearDeviceRegistration(): Promise<boolean>;

  /**
   * Get the device ID
   * @returns Device ID or empty if not registered
   */
  getDeviceId(): Promise<string>;

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

  /**
   * Register a custom model with the registry
   * @param modelJson JSON with model definition
   * @returns true if registered successfully
   */
  registerModel(modelJson: string): Promise<boolean>;

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
  // LLM Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+LLM.swift - calls rac_llm_component_* APIs
  // Requires a backend (e.g., @runanywhere/llamacpp) to be registered
  // ============================================================================

  /**
   * Load a text generation model
   * @param modelPath Path to the model file
   * @param configJson Optional configuration JSON
   * @returns true if model loaded successfully
   */
  loadTextModel(modelPath: string, configJson?: string): Promise<boolean>;

  /**
   * Check if a text model is loaded
   */
  isTextModelLoaded(): Promise<boolean>;

  /**
   * Unload the current text model
   */
  unloadTextModel(): Promise<boolean>;

  /**
   * Generate text from a prompt
   * @param prompt Input prompt
   * @param optionsJson Generation options JSON
   * @returns Generated text result as JSON
   */
  generate(prompt: string, optionsJson?: string): Promise<string>;

  /**
   * Generate text with streaming (callback-based)
   * @param prompt Input prompt
   * @param optionsJson Generation options JSON
   * @param callback Token callback (token: string, isComplete: boolean) => void
   * @returns Final result as JSON
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

  /**
   * Generate structured output (JSON) from a prompt
   * @param prompt Input prompt
   * @param schema JSON schema for output
   * @param optionsJson Generation options JSON
   * @returns Structured output as JSON
   */
  generateStructured(
    prompt: string,
    schema: string,
    optionsJson?: string
  ): Promise<string>;

  // ============================================================================
  // STT Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+STT.swift - calls rac_stt_component_* APIs
  // Requires a backend (e.g., @runanywhere/onnx) to be registered
  // ============================================================================

  /**
   * Load a speech-to-text model
   * @param modelPath Path to the model file
   * @param modelType Model type identifier
   * @param configJson Optional configuration JSON
   * @returns true if model loaded successfully
   */
  loadSTTModel(
    modelPath: string,
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
   * @param audioBase64 Base64 encoded audio data
   * @param sampleRate Audio sample rate
   * @param language Language code (optional)
   * @returns Transcription result as JSON
   */
  transcribe(
    audioBase64: string,
    sampleRate: number,
    language?: string
  ): Promise<string>;

  /**
   * Transcribe an audio file
   * @param filePath Path to the audio file
   * @param language Language code (optional)
   * @returns Transcription result as JSON
   */
  transcribeFile(filePath: string, language?: string): Promise<string>;

  // ============================================================================
  // TTS Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+TTS.swift - calls rac_tts_component_* APIs
  // Requires a backend (e.g., @runanywhere/onnx) to be registered
  // ============================================================================

  /**
   * Load a text-to-speech model/voice
   * @param modelPath Path to the model file
   * @param modelType Model type identifier
   * @param configJson Optional configuration JSON
   * @returns true if model loaded successfully
   */
  loadTTSModel(
    modelPath: string,
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
   * @param voiceId Voice ID to use
   * @param speedRate Speech speed rate (1.0 = normal)
   * @param pitchShift Pitch shift (-1.0 to 1.0)
   * @returns Synthesized audio as base64 encoded JSON
   */
  synthesize(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;

  /**
   * Get available TTS voices
   * @returns JSON array of voice info
   */
  getTTSVoices(): Promise<string>;

  /**
   * Cancel ongoing TTS synthesis
   */
  cancelTTS(): Promise<boolean>;

  // ============================================================================
  // VAD Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+VAD.swift - calls rac_vad_component_* APIs
  // Requires a backend (e.g., @runanywhere/onnx) to be registered
  // ============================================================================

  /**
   * Load a voice activity detection model
   * @param modelPath Path to the model file
   * @param configJson Optional configuration JSON
   * @returns true if model loaded successfully
   */
  loadVADModel(modelPath: string, configJson?: string): Promise<boolean>;

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
   * @param audioBase64 Base64 encoded audio data
   * @param optionsJson VAD options JSON
   * @returns VAD result as JSON
   */
  processVAD(audioBase64: string, optionsJson?: string): Promise<string>;

  /**
   * Reset VAD state
   */
  resetVAD(): Promise<void>;

  // ============================================================================
  // Secure Storage
  // Matches Swift: KeychainManager.swift
  // Uses platform secure storage (Keychain on iOS, Keystore on Android)
  // ============================================================================

  /**
   * Store a string value securely
   * @param key Storage key (e.g., "com.runanywhere.sdk.apiKey")
   * @param value String value to store
   * @returns true if stored successfully
   */
  secureStorageSet(key: string, value: string): Promise<boolean>;

  /**
   * Retrieve a string value from secure storage
   * @param key Storage key
   * @returns Stored value or null if not found
   */
  secureStorageGet(key: string): Promise<string | null>;

  /**
   * Delete a value from secure storage
   * @param key Storage key
   * @returns true if deleted successfully
   */
  secureStorageDelete(key: string): Promise<boolean>;

  /**
   * Check if a key exists in secure storage
   * @param key Storage key
   * @returns true if key exists
   */
  secureStorageExists(key: string): Promise<boolean>;

  /**
   * Get persistent device UUID
   * This UUID survives app reinstalls (stored in Keychain/Keystore)
   * Matches Swift: DeviceIdentity.persistentUUID
   * @returns Persistent device UUID
   */
  getPersistentDeviceUUID(): Promise<string>;

  // ============================================================================
  // Telemetry
  // Matches Swift: CppBridge+Telemetry.swift
  // C++ handles all telemetry logic - batching, JSON building, routing
  // ============================================================================

  /**
   * Flush pending telemetry events immediately
   * Sends all queued events to the backend
   */
  flushTelemetry(): Promise<void>;

  /**
   * Check if telemetry is initialized
   */
  isTelemetryInitialized(): Promise<boolean>;

  // ============================================================================
  // Voice Agent Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+VoiceAgent.swift - calls rac_voice_agent_* APIs
  // Requires STT, LLM, and TTS backends to be registered
  // ============================================================================

  /**
   * Initialize voice agent with configuration
   * @param configJson Configuration JSON
   * @returns true if initialized successfully
   */
  initializeVoiceAgent(configJson: string): Promise<boolean>;

  /**
   * Initialize voice agent using already loaded models
   * @returns true if initialized successfully
   */
  initializeVoiceAgentWithLoadedModels(): Promise<boolean>;

  /**
   * Check if voice agent is ready
   */
  isVoiceAgentReady(): Promise<boolean>;

  /**
   * Get voice agent component states
   * @returns JSON with component states
   */
  getVoiceAgentComponentStates(): Promise<string>;

  /**
   * Process a voice turn (STT -> LLM -> TTS)
   * @param audioBase64 Base64 encoded audio input
   * @returns Voice agent result as JSON
   */
  processVoiceTurn(audioBase64: string): Promise<string>;

  /**
   * Transcribe audio using voice agent
   * @param audioBase64 Base64 encoded audio data
   * @returns Transcription text
   */
  voiceAgentTranscribe(audioBase64: string): Promise<string>;

  /**
   * Generate response using voice agent
   * @param prompt Text prompt
   * @returns Generated response text
   */
  voiceAgentGenerateResponse(prompt: string): Promise<string>;

  /**
   * Synthesize speech using voice agent
   * @param text Text to synthesize
   * @returns Synthesized audio as base64
   */
  voiceAgentSynthesizeSpeech(text: string): Promise<string>;

  /**
   * Cleanup voice agent resources
   */
  cleanupVoiceAgent(): Promise<void>;

  // ============================================================================
  // Tool Calling Capability (Backend-Agnostic)
  // Enables LLMs to request external actions (API calls, device functions, etc.)
  // C++ handles: tool registry, prompt formatting, parsing <tool_call> tags
  // Platform handles: actual tool execution (HTTP, device APIs, etc.)
  // ============================================================================

  /**
   * Register a tool definition
   * @param toolJson JSON with {name, description, parameters}
   * @returns true if registered successfully
   */
  registerToolDefinition(toolJson: string): Promise<boolean>;

  /**
   * Unregister a tool by name
   * @param toolName Tool name to unregister
   * @returns true if unregistered successfully
   */
  unregisterToolDefinition(toolName: string): Promise<boolean>;

  /**
   * Get all registered tool definitions
   * @returns JSON array of tool definitions
   */
  getRegisteredToolDefinitions(): Promise<string>;

  /**
   * Clear all registered tools
   * @returns true if cleared successfully
   */
  clearToolDefinitions(): Promise<boolean>;

  /**
   * Format tools for LLM system prompt
   * @returns Formatted string describing available tools
   */
  formatToolsPrompt(): Promise<string>;

  /**
   * Parse LLM output for tool call
   * @param llmOutput Raw LLM output text
   * @returns JSON with {text, toolCall} where toolCall is null if none found
   */
  parseToolCallFromOutput(llmOutput: string): Promise<string>;
}
