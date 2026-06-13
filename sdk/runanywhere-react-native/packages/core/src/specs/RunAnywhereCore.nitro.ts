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
   * Complete deferred native service initialization.
   * Resolves to the serialized `RASdkInitResult` proto bytes so TS can read
   * `has_completed_http_setup` / `http_configured` / `http_applicable`. An
   * empty buffer means the packaged native lacks the phase-2 symbol (Phase 2
   * finished in offline/deferred mode), not that native services failed.
   * Matches Swift: RunAnywhere.completeServicesInitialization().
   */
  completeServicesInitialization(): Promise<ArrayBuffer>;

  /**
   * Retry HTTP/auth setup after an offline initialization via the commons
   * `rac_sdk_retry_http_proto` idempotency guard. Returns the serialized
   * `RASdkInitResult` proto bytes (empty buffer when the symbol is missing).
   * Matches Swift: CppBridge.SdkInit.retryHTTP().
   */
  retryHTTPSetupProto(): Promise<ArrayBuffer>;

  /**
   * Destroy the SDK and clean up resources
   */
  destroy(): Promise<void>;

  /**
   * Check if SDK is initialized
   */
  isInitialized(): Promise<boolean>;

  /**
   * Map a `rac_result_t` to serialized `runanywhere.v1.SDKError` bytes via
   * the canonical commons ABI `rac_result_to_proto_error` — the single
   * rac_result_t → proto-error translation shared by every SDK. Returns an
   * empty buffer for `RAC_SUCCESS` (or when the symbol is unavailable).
   * Mirrors Swift `RASDKError.from(rcResult:)` (RASDKError+Helpers.swift:52).
   */
  resultToProtoErrorProto(code: number): Promise<ArrayBuffer>;

  // ============================================================================
  // Plugin Loader
  // Matches Swift: RunAnywhere.pluginLoader backed by rac_registry_*.
  // ============================================================================

  pluginLoaderApiVersion(): Promise<number>;
  pluginLoaderRegisteredCount(): Promise<number>;
  pluginLoaderRegisteredNames(): Promise<string>;
  pluginLoaderListLoaded(): Promise<string>;
  pluginLoaderLoad(path: string): Promise<string>;
  pluginLoaderUnload(name: string): Promise<void>;

  // ============================================================================
  // Authentication
  // Matches Swift: CppBridge+Auth.swift
  // ============================================================================

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
   * Check if device is registered
   */
  isDeviceRegistered(): Promise<boolean>;

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
   * Human-readable display name for a runanywhere.v1.InferenceFramework proto
   * value. Backed by rac_inference_framework_display_name (sync table lookup).
   */
  frameworkDisplayName(frameworkProto: number): string;

  /**
   * Default runanywhere.v1.InferenceFramework proto value for a
   * runanywhere.v1.ModelCategory proto value. Backed by
   * rac_model_category_default_framework (sync table lookup).
   */
  modelCategoryDefaultFramework(categoryProto: number): number;

  /**
   * Infer the runanywhere.v1.ModelFileRole proto value for a filename in a
   * multi-file model. Backed by rac_infer_model_file_role (proto-valued both
   * ways; sync string matching). Mirrors Swift RunAnywhere.inferModelFileRole.
   */
  inferModelFileRole(filename: string, modalityProto: number): number;

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
   * Canonical single-call URL -> saved ModelInfo registration.
   *
   * Routes a serialized runanywhere.v1.RegisterModelFromUrlRequest through the
   * commons `rac_register_model_from_url_proto` C ABI, which owns
   * framework-aware defaulting, artifact-type-from-extension inference, and
   * stable id-from-URL derivation, then persists through the registry's proto
   * save path. Returns the saved runanywhere.v1.ModelInfo bytes (empty buffer
   * when the ABI is unavailable on the staged native artifact). Mirrors Swift
   * `RunAnywhere.registerModelFromUrl` and Kotlin
   * `CppBridgeModelRegistry.registerModelFromUrl`.
   */
  registerModelFromUrlProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Canonical multi-file registration (VLM gguf+mmproj pairs, embedding
   * model+vocab sets).
   *
   * Routes a serialized runanywhere.v1.RegisterMultiFileModelRequest through
   * the commons `rac_register_multi_file_model_proto` C ABI, which builds the
   * MultiFileArtifact ModelInfo (descriptors carry url/filename/size/
   * checksum/role) and persists it with merge-on-reseed semantics. Returns
   * the saved runanywhere.v1.ModelInfo bytes (empty buffer when the ABI is
   * unavailable on the staged native artifact). Mirrors Swift
   * `CppBridge.ModelRegistry.registerMultiFile` and Kotlin
   * `CppBridgeModelRegistry.registerMultiFileModel`.
   */
  registerMultiFileModelProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

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
   * Import a platform-normalized local model path into the registry.
   * Takes serialized runanywhere.v1.ModelImportRequest bytes and returns
   * serialized runanywhere.v1.ModelImportResult bytes.
   */
  importModelProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Refresh the model registry — unified cross-SDK surface.
   *
   * Routes to `rac_model_registry_refresh_proto` in commons (the flags are
   * encoded into a ModelRegistryRefreshRequest proto by the C++ bridge). Each
   * flag is independent and interpreted by the native registry implementation.
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
   * Clear the SDK's Cache directory only. Mirrors Swift `clearCache()` →
   * `CppBridge.FileManager.clearCache()`.
   * @returns true if cleared successfully
   */
  clearCache(): Promise<boolean>;

  /**
   * Clear the SDK's Temp directory only. Mirrors Swift `cleanTempFiles()` →
   * `CppBridge.FileManager.clearTemp()`.
   * @returns true if cleared successfully
   */
  cleanTempFiles(): Promise<boolean>;

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
   * `rac_llm_handle_t` so streaming consumers (e.g.
   * `RunAnywhere.generateStream`) can wire proto-byte callbacks directly.
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
  // STT Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+STT.swift - calls lifecycle proto APIs.
  // Requires a backend (e.g., @runanywhere/onnx) to be registered.
  // ============================================================================

  /**
   * Check if an STT model is loaded
   */
  isSTTModelLoaded(): Promise<boolean>;

  /**
   * Unload the current STT model
   */
  unloadSTTModel(): Promise<boolean>;

  sttTranscribeProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  sttTranscribeStreamProto(
    requestBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<void>;

  // ============================================================================
  // STT Streaming Session (live partials)
  // Mirrors Swift CppBridge+STT.swift `transcribeSessionStream`:
  // load model on the streaming handle, register the proto-byte callback,
  // start the session, feed audio frames, then stop (drain finals) or
  // cancel (immediate teardown). C ABI: rac_stt_stream.h.
  // ============================================================================

  /**
   * Load an STT model onto the global streaming STT component handle
   * (`rac_stt_component_load_model`). Same-model fast path: re-loading the
   * currently loaded modelId is a no-op. Rejects on load failure.
   */
  sttStreamLoadModel(
    modelPath: string,
    modelId: string,
    modelName: string
  ): Promise<boolean>;

  /**
   * Start a streaming transcription session. Registers `onEventBytes`
   * (serialized `runanywhere.v1.STTStreamEvent` per invocation) BEFORE
   * `rac_stt_stream_start_proto`. Only one concurrent session is supported
   * (the C ABI exposes a single callback slot per handle) — a second start
   * while a session is active rejects.
   *
   * @param optionsBytes Serialized `runanywhere.v1.STTOptions`.
   * @returns session id as a number (non-zero); failures reject.
   */
  sttStreamStart(
    optionsBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<number>;

  /**
   * Feed a PCM audio frame into an active session
   * (`rac_stt_stream_feed_audio_proto`). Rejects on feed failure.
   */
  sttStreamFeed(sessionId: number, audioBytes: ArrayBuffer): Promise<void>;

  /**
   * Stop a session (`rac_stt_stream_stop_proto`) — drains final events
   * through the still-registered callback, then tears down the callback
   * slot. Rejects if the native stop fails (after teardown).
   */
  sttStreamStop(sessionId: number): Promise<void>;

  /**
   * Cancel a session immediately (`rac_stt_stream_cancel_proto`) and tear
   * down the callback slot. Idempotent on unknown session ids.
   */
  sttStreamCancel(sessionId: number): Promise<void>;

  // ============================================================================
  // Hybrid STT Router (offline sherpa <-> cloud, registry-routed)
  //
  // THIN proto-byte / handle surface over the commons STT hybrid router
  // (rac_stt_hybrid_router_proto.h + rac_hybrid_device_state.h +
  // rac_hybrid_custom_filter.h). Mirrors the Kotlin RunAnywhereBridge JNI
  // quartet and the Swift CRACommons calls: commons owns the entire routing
  // decision (filter -> rank -> invoke -> fallback); these methods only create
  // the router + the two registry-routed STT services, marshal the policy
  // bytes, install the device-state + custom-filter callbacks, and drive
  // transcribe.
  //
  // Handles (router + per-side service) are opaque commons pointers surfaced to
  // JS as doubles (same packing the Solutions / VoiceAgent handles use).
  // ============================================================================

  /**
   * Allocate a native STT hybrid router (`rac_stt_hybrid_router_create`).
   * @returns router handle as a double (0 on failure).
   */
  hybridSttRouterCreate(): Promise<number>;

  /**
   * Destroy a router handle (`rac_stt_hybrid_router_destroy`). The wrapped
   * services are NOT destroyed — release those via
   * `hybridSttRouterDestroyService` first. Idempotent / 0-safe.
   */
  hybridSttRouterDestroy(routerHandle: number): Promise<void>;

  /**
   * Create one registry-routed `rac_stt_service_t` for the offline or online
   * side. Replicates the commons JNI `create_stt_service_via_registry` recipe:
   * `rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE, engine)` ->
   * `stt_ops->create` -> heap-wrap. The cloud provider (default "sarvam") rides
   * in `configJson`.
   *
   * @param engineHint    "sherpa" | "cloud" — pinned as preferred engine.
   * @param modelIdOrPath On-device model path for sherpa, "" for cloud.
   * @param configJson    Cloud `{provider,api_key,model,…}` JSON, "" for sherpa.
   * @returns service handle as a double (0 on failure).
   */
  hybridSttRouterCreateService(
    engineHint: string,
    modelIdOrPath: string,
    configJson: string
  ): Promise<number>;

  /**
   * Release a service handle from `hybridSttRouterCreateService` through
   * `rac_stt_destroy`. Idempotent / 0-safe.
   */
  hybridSttRouterDestroyService(serviceHandle: number): Promise<void>;

  /**
   * Attach (or clear when serviceHandle == 0) the offline-side service +
   * its serialized runanywhere.v1.HybridModelDescriptor bytes
   * (`rac_stt_hybrid_router_set_offline_service_proto`).
   * @returns native rac_result_t as a number (0 == RAC_SUCCESS).
   */
  hybridSttRouterSetOfflineService(
    routerHandle: number,
    serviceHandle: number,
    descriptorBytes: ArrayBuffer
  ): Promise<number>;

  /**
   * Symmetric to `hybridSttRouterSetOfflineService` for the online side
   * (`rac_stt_hybrid_router_set_online_service_proto`).
   */
  hybridSttRouterSetOnlineService(
    routerHandle: number,
    serviceHandle: number,
    descriptorBytes: ArrayBuffer
  ): Promise<number>;

  /**
   * Install / replace the routing policy from serialized
   * runanywhere.v1.HybridRoutingPolicy bytes
   * (`rac_stt_hybrid_router_set_policy_proto`).
   * @returns native rac_result_t as a number (0 == RAC_SUCCESS).
   */
  hybridSttRouterSetPolicy(
    routerHandle: number,
    policyBytes: ArrayBuffer
  ): Promise<number>;

  /**
   * Dispatch one transcribe request through the router
   * (`rac_stt_hybrid_router_transcribe_proto`). Input is serialized
   * runanywhere.v1.HybridSttTranscribeRequest; output is serialized
   * runanywhere.v1.HybridSttTranscribeResponse (empty buffer on native rc!=0).
   * Commons reads the device-state snapshot + custom-filter predicates while
   * routing.
   */
  hybridSttRouterTranscribe(
    routerHandle: number,
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

  /**
   * Best-effort cancel of an in-flight transcribe
   * (`rac_stt_hybrid_router_cancel`). No STT engine exposes a cancel op today,
   * so commons treats this as a no-op until one does.
   * @returns native rac_result_t as a number (0 == RAC_SUCCESS).
   */
  hybridSttRouterCancel(routerHandle: number): Promise<number>;

  /**
   * Register (or replace) a named custom-filter predicate with the cross-SDK
   * commons callback table (`rac_hybrid_register_custom_filter`). Commons
   * resolves it by name and invokes it once per candidate during the router's
   * filter phase — the predicate logic stays host-side, the decision stays in
   * commons. The native side blocks the (background) routing thread on the JS
   * promise, mirroring the synchronous JS-executor pattern used by
   * `toolRunLoopProto`.
   *
   * @param name      Wire identity (`CustomFilter.name`); non-empty, unique.
   * @param predicate `(candidateModelId) => Promise<boolean>` — true keeps the
   *                  candidate eligible.
   * @returns native rac_result_t as a number (0 == RAC_SUCCESS).
   */
  hybridRegisterCustomFilter(
    name: string,
    predicate: (candidateModelId: string) => Promise<boolean>
  ): Promise<number>;

  /**
   * Remove a named custom-filter predicate
   * (`rac_hybrid_unregister_custom_filter`). No-op when not registered.
   * @returns native rac_result_t as a number (0 == RAC_SUCCESS).
   */
  hybridUnregisterCustomFilter(name: string): Promise<number>;

  /**
   * Push a host device-state snapshot into the commons device-state vtable
   * (`rac_hybrid_set_device_state`) so the router's NETWORK / Battery hard
   * filters see live values on the next transcribe.
   *
   * RN cannot call JS synchronously from the commons routing thread (unlike the
   * Kotlin/Swift bindings, which install live `@convention(c)` / JNI callbacks),
   * so the binding pushes a snapshot of cached values instead; the installed
   * native vtable returns those cached values to commons. Call before
   * transcribe and whenever connectivity / battery changes.
   *
   * @returns true on RAC_SUCCESS.
   */
  hybridSetDeviceState(
    isOnline: boolean,
    batteryPercent: number,
    thermalThrottled: boolean
  ): Promise<boolean>;

  /**
   * Detach the host device-state vtable and restore the commons optimistic
   * default (always-online, 100% battery, not-throttled) via
   * `rac_hybrid_set_device_state(NULL)`.
   * @returns true on RAC_SUCCESS.
   */
  hybridClearDeviceState(): Promise<boolean>;

  /**
   * Register the generic "cloud" engine plugin with the commons registry
   * (`rac_backend_cloud_register`) so the hybrid router can route the
   * online side (hint "cloud"). Mirrors `ONNX.register()` /
   * `LlamaCPP.register()` and the Kotlin `CloudBridge.nativeRegister`.
   * Tolerant of already-registered. The concrete HTTP provider is data carried
   * per-service in the create config, not a distinct plugin.
   * @returns true on RAC_SUCCESS (or already-registered).
   */
  cloudRegister(): Promise<boolean>;

  /**
   * Unregister the "cloud" engine plugin
   * (`rac_backend_cloud_unregister`).
   * @returns true on RAC_SUCCESS.
   */
  cloudUnregister(): Promise<boolean>;

  /**
   * Register (or replace) a developer-defined cloud STT provider handler
   * (`rac_cloud_register_stt_provider`). The JS handler performs the whole
   * request host-side (build + HTTP + parse) and resolves the provider's
   * result JSON (`{"text", "language_code", "confidence", "error_code",
   * "error_message"}`). Invoked on the router's request thread; the native
   * side blocks on the returned promise like `toolRunLoopProto`'s executor.
   * Mirrors Swift `Cloud.registerProvider(_:_:)` (CloudSttProvider.swift:145).
   *
   * @param name         Provider name (ties to `CloudSTT.registerModel`'s
   *                     `provider` field). Built-in providers cannot be shadowed.
   * @param onTranscribe (configJson, audioBytes, audioFormat) → result JSON.
   * @returns true on RAC_SUCCESS.
   */
  cloudRegisterSttProvider(
    name: string,
    onTranscribe: (
      configJson: string,
      audioBytes: ArrayBuffer,
      audioFormat: number
    ) => Promise<string>
  ): Promise<boolean>;

  /**
   * Remove a developer-defined provider previously registered via
   * `cloudRegisterSttProvider` (`rac_cloud_unregister_stt_provider`).
   * Idempotent for unknown names. Mirrors Swift `Cloud.unregisterProvider(_:)`.
   */
  cloudUnregisterSttProvider(name: string): Promise<void>;

  /**
   * Whether the "cloud" plugin is currently registered for TRANSCRIBE
   * (`rac_backend_cloud_is_registered`).
   */
  cloudIsRegistered(): Promise<boolean>;

  // ============================================================================
  // TTS Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+TTS.swift - calls lifecycle proto APIs.
  // Requires a backend (e.g., @runanywhere/onnx) to be registered.
  // ============================================================================

  /**
   * Check if a TTS model is loaded
   */
  isTTSModelLoaded(): Promise<boolean>;

  /**
   * Unload the current TTS model
   */
  unloadTTSModel(): Promise<boolean>;

  ttsListVoicesProto(): Promise<ArrayBuffer>;
  ttsSynthesizeProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
  ttsSynthesizeStreamProto(
    requestBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<void>;
  ttsStopProto(): Promise<ArrayBuffer>;

  // ============================================================================
  // VAD Capability (Backend-Agnostic)
  // Matches Swift: CppBridge+VAD.swift - calls lifecycle proto APIs.
  // Requires a backend (e.g., @runanywhere/onnx) to be registered.
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

  vadConfigureProto(configBytes: ArrayBuffer): Promise<ArrayBuffer>;
  vadProcessProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;
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
   * Process one image from serialized runanywhere.v1.VLMGenerationRequest
   * bytes. Returns serialized runanywhere.v1.VLMResult bytes.
   */
  vlmProcessProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  /**
   * Stream VLMStreamEvent proto bytes from serialized
   * runanywhere.v1.VLMGenerationRequest bytes.
   */
  vlmProcessStreamProto(
    requestBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<void>;

  /**
   * Cancel ongoing VLM generation through commons cancellation ABI.
   */
  vlmCancelProto(): Promise<ArrayBuffer>;

  /**
   * Get persistent device UUID.
   * Survives app reinstalls (stored in Keychain/Keystore).
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
   * streaming events. Exposes the underlying
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
   * Run the complete native tool-calling loop from serialized
   * runanywhere.v1.ToolCallingSessionCreateRequest bytes.
   *
   * The callback receives serialized runanywhere.v1.ToolCall bytes and must
   * return serialized runanywhere.v1.ToolResult bytes. C++ owns prompt
   * formatting, generation, parsing, validation, follow-up prompts, and loop
   * termination; React Native owns only the JS executor registry.
   *
   * Implemented by HybridRunAnywhereCore+Tools.cpp with
   * rac_tool_calling_run_loop_proto. The native bridge waits on the Nitro
   * promise returned by the JS executor callback so commons can keep the
   * canonical synchronous run-loop ABI.
   */
  toolRunLoopProto(
    requestBytes: ArrayBuffer,
    onExecuteToolBytes: (toolCallBytes: ArrayBuffer) => Promise<ArrayBuffer>
  ): Promise<ArrayBuffer>;

  /**
   * Cancellation-aware variant of toolRunLoopProto.
   *
   * Backed by `rac_tool_calling_run_loop_with_handle_proto`. Commons publishes
   * an opaque `run_loop_handle` synchronously, before the iteration loop
   * begins; the bridge surfaces it to JS via `onHandle(handle)` so a fan-out
   * `AbortSignal.abort()` can call `toolRunLoopCancelProto(handle)` to
   * interrupt the in-flight loop from another thread.
   *
   * The handle is owned by commons and reclaimed when this Promise resolves;
   * callers MUST NOT use it past resolution. A handle of `0` indicates the
   * with-handle ABI is unavailable on this commons build.
   *
   * Mirrors Swift `generateWithToolsCancellable` in
   * `RunAnywhere+ToolCalling.swift`.
   */
  toolRunLoopProtoWithHandle(
    requestBytes: ArrayBuffer,
    onExecuteToolBytes: (toolCallBytes: ArrayBuffer) => Promise<ArrayBuffer>,
    onHandle: (runLoopHandle: number) => void
  ): Promise<ArrayBuffer>;

  /**
   * Cancel an in-flight tool-calling run loop started via
   * `toolRunLoopProtoWithHandle`.
   *
   * Backed by `rac_tool_calling_run_loop_cancel_proto`. Idempotent: safe to
   * call after the loop has already returned (the handle will be stale and
   * commons treats this as a no-op).
   */
  toolRunLoopCancelProto(runLoopHandle: number): Promise<boolean>;

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
  structuredOutputGenerateProto(
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;
  structuredOutputGenerateStreamProto(
    requestBytes: ArrayBuffer,
    onEventBytes: (eventBytes: ArrayBuffer) => void
  ): Promise<void>;
  structuredOutputSchemaToJsonProto(
    schemaBytes: ArrayBuffer
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

  /**
   * Generate embeddings via the commons embeddings lifecycle.
   * runanywhere.v1.EmbeddingsRequest bytes in, runanywhere.v1.EmbeddingsResult
   * bytes out. Backed by rac_embeddings_embed_batch_lifecycle_proto; the
   * lifecycle owns the component, so no handle is involved. Mirrors Swift
   * CppBridge.EmbeddingsProto.embedBatchLifecycle.
   */
  embeddingsEmbedBatchLifecycleProto(
    requestBytes: ArrayBuffer
  ): Promise<ArrayBuffer>;

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

  /**
   * Import a user-picked local LoRA adapter file from serialized
   * runanywhere.v1.LoraAdapterImportRequest bytes. Commons owns matching,
   * placement, artifact registration, and catalog completion.
   *
   * Returns serialized runanywhere.v1.LoraAdapterImportResult bytes.
   */
  loraAdapterImportProto(requestBytes: ArrayBuffer): Promise<ArrayBuffer>;

  // ===========================================================================
  // Solutions Runtime (rac/solutions/rac_solution.h)
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
