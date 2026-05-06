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
export interface RunAnywhereCore extends HybridObject<{
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
   * Get all registered models as serialized runanywhere.v1.ModelInfoList bytes.
   */
  getAvailableModelsProto(): Promise<ArrayBuffer>;

  /**
   * Get one registered model as serialized runanywhere.v1.ModelInfo bytes.
   * Returns an empty buffer when the model does not exist.
   */
  getModelInfoProto(modelId: string): Promise<ArrayBuffer>;

  /**
   * Register a model from serialized runanywhere.v1.ModelInfo bytes.
   */
  registerModelProto(modelInfoBytes: ArrayBuffer): Promise<boolean>;

  /**
   * Update an existing model from serialized runanywhere.v1.ModelInfo bytes.
   */
  updateModelProto(modelInfoBytes: ArrayBuffer): Promise<boolean>;

  /**
   * Remove a model registry entry by ID through the proto-byte C ABI.
   */
  removeModelProto(modelId: string): Promise<boolean>;

  /**
   * Query registered models from serialized runanywhere.v1.ModelQuery bytes.
   * Returns serialized runanywhere.v1.ModelInfoList bytes.
   */
  queryModelsProto(queryBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Get downloaded registered models as serialized runanywhere.v1.ModelInfoList bytes.
   */
  getDownloadedModelsProto(): Promise<ArrayBuffer>;

  /**
   * Refresh the model registry — T4.9 unified cross-SDK surface.
   *
   * Routes to `rac_model_registry_refresh` in commons. Each flag is
   * independent and interpreted by the native registry implementation.
   *
   * @param includeRemoteCatalog Fetch the backend model assignment catalog.
   * @param rescanLocal Request a local filesystem rescan in native commons.
   * @param pruneOrphans Request orphan pruning in native commons.
   * @returns `true` if the refresh returned `RAC_SUCCESS`.
   */
  refreshModelRegistry(
    includeRemoteCatalog: boolean,
    rescanLocal: boolean,
    pruneOrphans: boolean
  ): Promise<boolean>;

  // ============================================================================
  // Download Service
  // Backed by `rac_download_*_proto` (commons) which routes through the
  // platform HTTP transport registered by the RN core (OkHttp on Android,
  // URLSession on iOS). Requests, results, progress, cancellation, and resume
  // state are serialized `runanywhere.v1.*` proto bytes.
  // ============================================================================

  /**
   * Plan a download from serialized runanywhere.v1.DownloadPlanRequest bytes.
   * Returns serialized runanywhere.v1.DownloadPlanResult bytes.
   */
  downloadPlanProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Start a native download from serialized runanywhere.v1.DownloadStartRequest bytes.
   * Returns serialized runanywhere.v1.DownloadStartResult bytes.
   */
  downloadStartProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Cancel a native download from serialized runanywhere.v1.DownloadCancelRequest bytes.
   * Returns serialized runanywhere.v1.DownloadCancelResult bytes.
   */
  downloadCancelProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Resume a native download from serialized runanywhere.v1.DownloadResumeRequest bytes.
   * Returns serialized runanywhere.v1.DownloadResumeResult bytes.
   */
  downloadResumeProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Poll native download progress from serialized runanywhere.v1.DownloadSubscribeRequest bytes.
   * Returns serialized runanywhere.v1.DownloadProgress bytes, or an empty buffer if no task exists.
   */
  downloadProgressPollProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Register a process-wide native DownloadProgress proto callback.
   */
  setDownloadProgressCallbackProto(
    onProgressBytes: (progressBytes: ArrayBuffer) => void
  ): Promise<boolean>;

  /**
   * Clear the process-wide native DownloadProgress proto callback.
   */
  clearDownloadProgressCallbackProto(): Promise<boolean>;

  // ============================================================================
  // Storage
  // Matches Swift: RunAnywhere+Storage.swift
  // ============================================================================

  /**
   * Clear model cache
   * @returns true if cleared successfully
   */
  clearCache(): Promise<boolean>;

  /**
   * Analyze storage from serialized runanywhere.v1.StorageInfoRequest bytes.
   * Returns serialized runanywhere.v1.StorageInfoResult bytes.
   */
  storageInfoProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Check storage availability from serialized runanywhere.v1.StorageAvailabilityRequest bytes.
   * Returns serialized runanywhere.v1.StorageAvailabilityResult bytes.
   */
  storageAvailabilityProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Build a delete plan from serialized runanywhere.v1.StorageDeletePlanRequest bytes.
   * Returns serialized runanywhere.v1.StorageDeletePlan bytes.
   */
  storageDeletePlanProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Execute or dry-run delete from serialized runanywhere.v1.StorageDeleteRequest bytes.
   * Returns serialized runanywhere.v1.StorageDeleteResult bytes.
   */
  storageDeleteProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  // ============================================================================
  // Hardware
  // Matches commons rac_hardware_profile_get proto ABI
  // ============================================================================

  /**
   * Get serialized runanywhere.v1.HardwareProfileResult bytes.
   */
  hardwareProfileProto(): Promise<ArrayBuffer>;

  // ============================================================================
  // Events
  // Matches Swift: CppBridge+Events.swift
  // ============================================================================

  /**
   * Subscribe to serialized runanywhere.v1.SDKEvent bytes.
   * Returns a native subscription id.
   */
  subscribeSDKEventsProto(
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<number>;

  /**
   * Unsubscribe from a native SDKEvent proto stream.
   */
  unsubscribeSDKEventsProto(subscriptionId: number): Promise<void>;

  /**
   * Publish serialized runanywhere.v1.SDKEvent bytes.
   */
  publishSDKEventProto(eventBytes: ArrayBuffer): Promise<boolean>;

  /**
   * Poll the next queued serialized runanywhere.v1.SDKEvent bytes.
   * Returns an empty buffer when no event is queued.
   */
  pollSDKEventProto(): Promise<ArrayBuffer>;

  /**
   * Publish a canonical failure SDKEvent through native commons.
   */
  publishSDKFailureProto(
    errorCode: number,
    message: string,
    component: string,
    operation: string,
    recoverable: boolean
  ): Promise<boolean>;

  // ============================================================================
  // Model Lifecycle
  // ============================================================================

  /**
   * Load a model from serialized runanywhere.v1.ModelLoadRequest bytes.
   * Returns serialized runanywhere.v1.ModelLoadResult bytes.
   */
  modelLifecycleLoadProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Unload model(s) from serialized runanywhere.v1.ModelUnloadRequest bytes.
   * Returns serialized runanywhere.v1.ModelUnloadResult bytes.
   */
  modelLifecycleUnloadProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Query current model from serialized runanywhere.v1.CurrentModelRequest bytes.
   * Returns serialized runanywhere.v1.CurrentModelResult bytes.
   */
  currentModelProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Snapshot one component lifecycle state.
   * Returns serialized runanywhere.v1.ComponentLifecycleSnapshot bytes.
   */
  componentLifecycleSnapshotProto(component: number): Promise<ArrayBuffer>;

  // ============================================================================
  // HTTP Client (libcurl-backed — rac_http_client_*)
  // Matches Swift: HTTPClientAdapter.swift / Kotlin: CppBridgeHTTP.kt
  // ============================================================================

  /**
   * Configure HTTP client base URL / API key for downstream C++ consumers
   * (DeviceBridge etc.). TypeScript callers use `httpRequest` directly.
   * @returns true if configured successfully
   */
  configureHttp(baseUrl: string, apiKey: string): Promise<boolean>;

  /**
   * Perform a synchronous HTTP request via the native curl-backed client.
   * Returns a JSON string `{"status": number, "body": string, "headersJson":
   * string}` on any HTTP response (including 4xx/5xx). Rejects the promise
   * only on transport-level failures (DNS / TLS / timeout / cancellation).
   *
   * @param method HTTP method (uppercase: GET / POST / PUT / DELETE / PATCH / HEAD)
   * @param url Absolute URL (http:// or https://)
   * @param headersJson Request headers serialized as `{"Name": "Value", ...}`
   *        (empty string or `{}` for none)
   * @param bodyJson Request body as string (ignored for GET/HEAD)
   * @param timeoutMs Request timeout in ms (0 = no timeout)
   */
  httpRequest(
    method: string,
    url: string,
    headersJson: string,
    bodyJson: string,
    timeoutMs: number
  ): Promise<string>;

  /**
   * Authenticate with the RunAnywhere backend and store the resulting JWT
   * access/refresh tokens in the C++ AuthBridge. The native implementation
   * builds the request JSON, executes the POST via rac_http_client_*, and
   * calls AuthBridge::setAuth on success so subsequent native HTTP calls
   * (device registration, telemetry) pick up the access token automatically.
   *
   * @returns The full auth response body (`{access_token, refresh_token,
   *   expires_in, device_id, organization_id, user_id, token_type}`) as a
   *   JSON string. Rejects when the backend returns a non-2xx response.
   */
  authAuthenticate(
    apiKey: string,
    baseURL: string,
    deviceId: string,
    platform: string,
    sdkVersion: string
  ): Promise<string>;

  /**
   * Refresh the stored JWT access token using the refresh token currently
   * held by AuthBridge. Rejects when no refresh token is present or the
   * backend rejects the refresh.
   *
   * @returns The new auth response body as a JSON string.
   */
  authRefreshToken(baseURL: string): Promise<string>;

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
   * Check if a text model is loaded
   */
  isTextModelLoaded(): Promise<boolean>;

  /**
   * Unload the current text model
   */
  unloadTextModel(): Promise<boolean>;

  /**
   * Get the native LLM-component handle as a JS number. Pass to
   * `LLM.subscribeProtoEvents(handle, ...)` to subscribe to streaming
   * events. Mirrors `getVoiceAgentHandle()` — exposes the underlying
   * `rac_llm_handle_t` so the `LLMStreamAdapter` pattern works.
   *
   * @returns handle as number (0 if LLM component not yet allocated).
   */
  getLLMHandle(): Promise<number>;

  /**
   * Cancel ongoing text generation
   */
  cancelGeneration(): Promise<boolean>;

  llmGenerateProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  llmGenerateStreamProto(
    requestBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<void>;
  llmCancelProto(): Promise<ArrayBuffer>;

  // ============================================================================
  // LLM Thinking (<think>...</think> parsing)
  // Matches Swift: ThinkingContentParser + CppBridge+LLMThinking.swift
  // Kotlin: CppBridgeLlmThinking / Dart: LlmThinking
  // Wraps rac_llm_thinking.h — byte-for-byte identical across all 5 SDKs.
  // v3-readiness Phase A10 / GAP 08 #6.
  // ============================================================================

  /**
   * Split a full LLM response into (response, thinking) on the FIRST
   * `<think>...</think>` block.
   *
   * @param text Full LLM response text
   * @returns JSON: `{ "response": string, "thinking": string | null }`.
   *   Response is never null (empty string when input is only a think
   *   block). Returns an empty JSON object `"{}"` on error.
   */
  llmExtractThinking(text: string): Promise<string>;

  /**
   * Remove ALL `<think>...</think>` blocks (and trailing unclosed
   * `<think>`) from text.
   *
   * @param text Full LLM response text
   * @returns The trimmed remainder. Empty string on error.
   */
  llmStripThinking(text: string): Promise<string>;

  /**
   * Apportion a total token count between thinking + response segments
   * proportionally by character length.
   *
   * @param totalCompletionTokens Total tokens reported by the LLM
   * @param responseText Pass empty string when absent
   * @param thinkingText Pass empty string when absent (returns (0, total))
   * @returns JSON: `{ "thinking": int, "response": int }`. Guarantees
   *   `thinking + response == total` on success.
   */
  llmSplitThinkingTokens(
    totalCompletionTokens: number,
    responseText: string,
    thinkingText: string
  ): Promise<string>;

  // ============================================================================
  // STT Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+STT.swift - calls rac_stt_component_* APIs
  // Requires a backend (e.g., @runanywhere/onnx) to be registered
  // ============================================================================

  /**
   * Check if an STT model is loaded
   */
  isSTTModelLoaded(): Promise<boolean>;

  /**
   * Unload the current STT model
   */
  unloadSTTModel(): Promise<boolean>;

  sttTranscribeProto(
    audioBytes: ArrayBuffer,
    optionsBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;
  sttTranscribeStreamProto(
    audioBytes: ArrayBuffer,
    optionsBytes: ArrayBuffer,
    onPartialBytes: (partialBytes: ArrayBuffer) => void
  ): Promise<void>;

  // ============================================================================
  // TTS Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+TTS.swift - calls rac_tts_component_* APIs
  // Requires a backend (e.g., @runanywhere/onnx) to be registered
  // ============================================================================

  /**
   * Check if a TTS model is loaded
   */
  isTTSModelLoaded(): Promise<boolean>;

  /**
   * Unload the current TTS model
   */
  unloadTTSModel(): Promise<boolean>;

  ttsListVoicesProto(
    onVoiceBytes: (voiceBytes: ArrayBuffer) => void
  ): Promise<boolean>;
  ttsSynthesizeProto(
    text: string,
    optionsBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;
  ttsSynthesizeStreamProto(
    text: string,
    optionsBytes: ArrayBuffer,
    onChunkBytes: (chunkBytes: ArrayBuffer) => void
  ): Promise<void>;

  // ============================================================================
  // VAD Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+VAD.swift - calls rac_vad_component_* APIs
  // Requires a backend (e.g., @runanywhere/onnx) to be registered
  // ============================================================================

  /**
   * Check if a VAD model is loaded
   */
  isVADModelLoaded(): Promise<boolean>;

  /**
   * Unload the current VAD model
   */
  unloadVADModel(): Promise<boolean>;

  /**
   * Reset VAD state
   */
  resetVAD(): Promise<void>;

  vadConfigureProto(configBytes: ArrayBuffer): Promise<boolean>;
  vadProcessProto(
    samplesBytes: ArrayBuffer,
    optionsBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;
  vadGetStatisticsProto(): Promise<ArrayBuffer>;
  vadSetActivityCallbackProto(
    onActivityBytes: (activityBytes: ArrayBuffer) => void
  ): Promise<boolean>;

  // ============================================================================
  // VLM Capability (Backend-Agnostic)
  // Uses commons VLM service lifecycle plus rac_vlm_*_proto request/result ABI.
  // Backend packages register providers only; core owns public VLM calls.
  // ============================================================================

  /**
   * Load a VLM model from lifecycle-resolved role artifacts.
   */
  loadVLMModelFromArtifacts(
    primaryModelPath: string,
    visionProjectorPath: string,
    modelId: string
  ): Promise<boolean>;

  /**
   * Check whether the process-wide VLM service handle is loaded.
   */
  isVLMModelLoaded(): Promise<boolean>;

  /**
   * Unload and destroy the process-wide VLM service handle.
   */
  unloadVLMModel(): Promise<boolean>;

  /**
   * Process one image from serialized runanywhere.v1.VLMImage bytes plus
   * serialized runanywhere.v1.VLMGenerationOptions bytes. Returns serialized
   * runanywhere.v1.VLMResult bytes.
   */
  vlmProcessProto(
    imageBytes: ArrayBuffer,
    optionsBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

  /**
   * Stream VLM SDKEvent proto bytes while returning the final serialized
   * runanywhere.v1.VLMResult bytes.
   */
  vlmProcessStreamProto(
    imageBytes: ArrayBuffer,
    optionsBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<ArrayBuffer>;

  /**
   * Cancel ongoing VLM generation through commons cancellation ABI.
   */
  vlmCancelProto(): Promise<boolean>;

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
   * Store a string value securely (semantic alias for secureStorageSet)
   * @param key Storage key
   * @param value String value to store
   */
  secureStorageStore(key: string, value: string): Promise<void>;

  /**
   * Retrieve a string value from secure storage (semantic alias for secureStorageGet)
   * @param key Storage key
   * @returns Stored value or null if not found
   */
  secureStorageRetrieve(key: string): Promise<string | null>;

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
   * Initialize voice agent using already loaded models
   * @returns true if initialized successfully
   */
  initializeVoiceAgentWithLoadedModels(): Promise<boolean>;

  /**
   * Get the native voice-agent handle as a JS number. Pass to
   * `VoiceAgent.subscribeProtoEvents(handle, ...)` to subscribe to
   * streaming events. v3.1 addition — exposes the underlying
   * `rac_voice_agent_handle_t` so the adapter pattern works.
   *
   * @returns handle as number (0 if voice agent not yet initialized).
   */
  getVoiceAgentHandle(): Promise<number>;

  /**
   * Check if voice agent is ready
   */
  isVoiceAgentReady(): Promise<boolean>;

  /**
   * Transcribe audio using the voice-agent STT component via the commons
   * `rac_voice_agent_transcribe_proto` ABI. Input is a serialized
   * `runanywhere.v1.VoiceAgentTranscribeProtoRequest`; the output is a
   * serialized `runanywhere.v1.STTOutput`.
   */
  voiceAgentTranscribeProto(
    audioBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

  /**
   * Synthesize speech using the voice-agent TTS component via the commons
   * `rac_voice_agent_synthesize_speech_proto` ABI. Input is a UTF-8 text
   * string; the output is a serialized `runanywhere.v1.TTSOutput`.
   */
  voiceAgentSynthesizeSpeechProto(text: string): Promise<ArrayBuffer>;

  /**
   * Cleanup voice agent resources
   */
  cleanupVoiceAgent(): Promise<void>;

  voiceAgentInitializeProto(configBytes: ArrayBuffer): Promise<ArrayBuffer>;
  voiceAgentComponentStatesProto(): Promise<ArrayBuffer>;
  voiceAgentProcessTurnProto(audioBytes: ArrayBuffer): Promise<ArrayBuffer>;

  // ============================================================================
  // Tool Calling Capability
  //
  // ARCHITECTURE:
  // - C++ commons C ABI: Parses <tool_call> tags from
  //   LLM output and formats prompts. This is the SINGLE SOURCE OF TRUTH for
  //   portable parsing and prompt text semantics.
  //
  // - TypeScript (RunAnywhere+ToolCalling.ts): Handles tool registry, executor
  //   storage and orchestration. Executors MUST stay in
  //   TypeScript because they need JavaScript APIs (fetch, device APIs, etc.).
  //
  // C++ implements: toolParseProto, toolFormatPromptProto, and
  // toolValidateProto. TypeScript handles: tool registry, executor storage
  // (needs JS APIs like fetch), orchestration.
  // ============================================================================

  /**
   * Parse LLM output for tool calls from serialized runanywhere.v1.ToolParseRequest bytes.
   *
   * Returns serialized runanywhere.v1.ToolParseResult bytes. JS owns generated
   * proto-ts encode/decode only; parsing semantics stay in native C++ commons.
   *
   * @param requestBytes Serialized ToolParseRequest bytes
   * @returns Serialized ToolParseResult bytes
   */
  toolParseProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Format tool prompts from serialized runanywhere.v1.ToolPromptFormatRequest bytes.
   *
   * Returns serialized runanywhere.v1.ToolPromptFormatResult bytes. JS owns
   * generated proto-ts encode/decode only; prompt semantics stay in native
   * C++ commons. Host tool execution remains in JS/app code.
   *
   * @param requestBytes Serialized ToolPromptFormatRequest bytes
   * @returns Serialized ToolPromptFormatResult bytes
   */
  toolFormatPromptProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Validate a tool call from serialized
   * runanywhere.v1.ToolCallValidationRequest bytes.
   *
   * Returns serialized runanywhere.v1.ToolCallValidationResult bytes.
   */
  toolValidateProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Parse/extract structured output from serialized
   * runanywhere.v1.StructuredOutputParseRequest bytes.
   *
   * Returns serialized runanywhere.v1.StructuredOutputResult bytes.
   */
  structuredOutputParseProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Prepare a structured-output prompt from serialized
   * runanywhere.v1.StructuredOutputRequest bytes.
   *
   * Returns serialized runanywhere.v1.StructuredOutputPromptResult bytes.
   */
  structuredOutputPreparePromptProto(
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

  /**
   * Validate structured output from serialized
   * runanywhere.v1.StructuredOutputValidationRequest bytes.
   *
   * Returns serialized runanywhere.v1.StructuredOutputValidation bytes.
   */
  structuredOutputValidateProto(
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

  // ===========================================================================
  // RAG Pipeline (Retrieval-Augmented Generation)
  // ===========================================================================

  ragCreatePipelineProto(configBytes: ArrayBuffer): Promise<boolean>;
  ragDestroyPipelineProto(): Promise<boolean>;
  ragIngestProto(documentBytes: ArrayBuffer): Promise<ArrayBuffer>;
  ragQueryProto(queryBytes: ArrayBuffer): Promise<ArrayBuffer>;
  ragClearProto(): Promise<ArrayBuffer>;
  ragStatsProto(): Promise<ArrayBuffer>;

  embeddingsCreateProto(modelId: string, configJson?: string): Promise<number>;
  embeddingsEmbedBatchProto(
    handle: number,
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;
  embeddingsDestroyProto(handle: number): Promise<void>;

  loraApplyProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  loraRemoveProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  loraListProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  loraStateProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  loraCompatibilityProto(configBytes: ArrayBuffer): Promise<ArrayBuffer>;
  /**
   * Register a LoRA catalog entry from serialized
   * runanywhere.v1.LoraAdapterCatalogEntry bytes.
   *
   * Returns serialized runanywhere.v1.LoraAdapterCatalogEntry bytes on
   * success. Catalog metadata/state semantics are owned by commons; native
   * platform layers still own byte downloads and file permission handling.
   */
  loraRegisterCatalogEntryProto(entryBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * List LoRA catalog entries from serialized
   * runanywhere.v1.LoraAdapterCatalogListRequest bytes.
   *
   * Returns serialized runanywhere.v1.LoraAdapterCatalogListResult bytes.
   */
  loraCatalogListProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Query LoRA catalog entries from serialized
   * runanywhere.v1.LoraAdapterCatalogQuery bytes.
   *
   * Returns serialized runanywhere.v1.LoraAdapterCatalogListResult bytes.
   */
  loraCatalogQueryProto(queryBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Fetch one LoRA catalog entry from serialized
   * runanywhere.v1.LoraAdapterCatalogGetRequest bytes.
   *
   * Returns serialized runanywhere.v1.LoraAdapterCatalogGetResult bytes.
   */
  loraCatalogGetProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Persist platform-reported LoRA artifact completion state from serialized
   * runanywhere.v1.LoraAdapterDownloadCompletedRequest bytes.
   *
   * Returns serialized runanywhere.v1.LoraAdapterDownloadCompletedResult bytes.
   */
  loraCatalogMarkDownloadCompletedProto(
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

  // ===========================================================================
  // Solutions Runtime (rac/solutions/rac_solution.h) — T4.7 / T4.8
  //
  // Proto-byte / YAML driven L5 solution runtime. Callers pass a serialized
  // `runanywhere.v1.SolutionConfig` (or PipelineSpec) protobuf or a YAML
  // document and receive an opaque handle that maps to the same
  // `rac_solution_handle_t` used by every other SDK.
  //
  // The handle is exposed to JS as a `double` — we pack the C pointer
  // into a 64-bit double (same trick the VoiceAgent / LLM capabilities
  // use for their native handles). Lifecycle verbs (start/stop/cancel/
  // feed/closeInput/destroy) take that handle back.
  // ===========================================================================

  /**
   * Construct a solution from a serialized `runanywhere.v1.SolutionConfig`
   * (or PipelineSpec) protobuf. The handle is returned in the **created**
   * state — call `solutionStart(handle)` to launch worker threads.
   *
   * @param configBytes Serialized SolutionConfig / PipelineSpec proto bytes.
   * @returns Native solution handle as a double (0 on failure).
   */
  solutionCreateFromProto(configBytes: ArrayBuffer): Promise<number>;

  /**
   * Construct a solution from a YAML document (SolutionConfig-shape or
   * PipelineSpec-shape — loader auto-disambiguates on `operators:`).
   *
   * @returns Native solution handle as a double (0 on failure).
   */
  solutionCreateFromYaml(yamlText: string): Promise<number>;

  /** Start the underlying scheduler (non-blocking). */
  solutionStart(handle: number): Promise<boolean>;

  /** Request a graceful shutdown (non-blocking). */
  solutionStop(handle: number): Promise<boolean>;

  /** Force-cancel the graph; returns once workers observe cancellation. */
  solutionCancel(handle: number): Promise<boolean>;

  /** Feed one UTF-8 item into the root input edge. */
  solutionFeed(handle: number, item: string): Promise<boolean>;

  /** Signal end-of-stream on the root input edge. */
  solutionCloseInput(handle: number): Promise<boolean>;

  /** Cancel, join, and release native resources. Idempotent. */
  solutionDestroy(handle: number): Promise<void>;
}
