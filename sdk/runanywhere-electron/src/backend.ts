// The contract between the shared v3 namespaces and whichever host owns the
// native addon.
//
// Two implementations exist: NativeBackend (in-process, holds the addon and its
// native handles) and RpcBackend (a renderer talking to the utility host over a
// MessagePort). Every operation takes and returns serialized protos as bytes,
// plus at most one proto-byte chunk callback for streams. Because bytes and the
// few scalar values here are all structured-cloneable, the RPC implementation is
// a mechanical forward and both public surfaces are the same code.
//
// The namespaces own the typed protos (built and parsed with @runanywhere/proto-ts);
// this boundary is deliberately the serialization seam, so no native handle and
// no rich object ever crosses a process boundary. Each method documents the
// runanywhere.v1 request -> response proto and the commons rac_* symbol the
// NativeBackend maps it to.
//
// Loading is registry-first, exactly as the other SDKs do it: register the model
// (registerModel / registerModelFromUrl), then loadModel by id, then call the
// modality inference op. commons tracks one lifecycle-owned model per component,
// which is why the inference ops take no handle.

/** Encoded protobuf message. */
export type ProtoBytes = Uint8Array;

/** Receives one encoded event/chunk proto per stream item. */
export type ProtoSink = (eventBytes: ProtoBytes) => void;

/** Executes one tool: a serialized ToolCall in, a serialized ToolResult out. */
export type ToolExecutor = (toolCall: ProtoBytes) => ProtoBytes | Promise<ProtoBytes>;

/**
 * Inputs for the desktop control plane (telemetry + auth). Scalar config plus the
 * two serialized init requests the caller builds; the whole two-phase init runs in
 * one worker. `environment` is a rac_environment_t (0=dev, 2=prod); the phase bytes
 * are SdkInit{Phase1,Phase2}Request.
 */
export interface ControlPlaneRequest {
  environment: number;
  apiKey: string;
  baseUrl: string;
  deviceId: string;
  platform: string;
  sdkVersion: string;
  sdkBinding: string;
  appIdentifier: string;
  appName: string;
  appVersion: string;
  phase1Bytes: ProtoBytes;
  phase2Bytes: ProtoBytes;
}

export interface RaBackend {
  // lifecycle + control plane
  /** Bundled commons version. */
  version(): Promise<string>;
  /** Core bring-up: platform adapter, rac_init, backend registration. Enables local inference. */
  initialize(opts: { baseDir?: string; secureDir?: string }): Promise<void>;
  /** Desktop control plane, two-phase init in one worker. ControlPlaneRequest -> SdkInitResult bytes. */
  configureControlPlane(request: ControlPlaneRequest): Promise<ProtoBytes>;
  /** Tear down commons (models unloaded, state cleared). rac_shutdown */
  shutdown(): Promise<void>;
  /** Whether this build carries the desktop control plane (libcurl transport). */
  hasControlPlane(): Promise<boolean>;
  /** Persistent per-device id commons mints. rac_device_get_or_create_persistent_id */
  devicePersistentId(): Promise<string>;
  /** Baked staging base URL for keyless development, or "". */
  devStagingBaseUrl(): Promise<string>;

  // capabilities + model registry
  /** Frameworks that can serve a component. FrameworksForCapabilityRequest -> FrameworksForCapabilityResponse. rac_router_frameworks_for_capability_proto */
  frameworksForCapability(request: ProtoBytes): Promise<ProtoBytes>;
  /** The GPU backend the addon was compiled with (metal/cuda/webgpu/cpu). Compile-time DeviceType, not a runtime probe. */
  deviceType(): Promise<string>;
  /** Register a model so it can be loaded by id. ModelRegistration -> result. rac_model_registry_register_proto */
  registerModel(request: ProtoBytes): Promise<ProtoBytes>;
  /** Register a model from a URL (single call). request -> result. rac_register_model_from_url_proto */
  registerModelFromUrl(request: ProtoBytes): Promise<ProtoBytes>;
  /** List registered models. ModelQuery? -> model list. rac_model_registry_list_proto */
  modelRegistryList(request?: ProtoBytes): Promise<ProtoBytes>;
  /** Query registered models. ModelQuery -> model list. rac_model_registry_query_proto */
  modelRegistryQuery(request: ProtoBytes): Promise<ProtoBytes>;
  /** Register a multi-file model (model + companions). RegisterMultiFileModelRequest -> ModelInfo. rac_register_multi_file_model_proto */
  registerMultiFile(request: ProtoBytes): Promise<ProtoBytes>;
  /** List models with filters + counts. ModelListRequest -> ModelListResult. rac_model_registry_list_models_proto */
  modelList(request: ProtoBytes): Promise<ProtoBytes>;
  /** Get one model by id. ModelGetRequest -> ModelGetResult. rac_model_registry_get_model_proto */
  modelGet(request: ProtoBytes): Promise<ProtoBytes>;
  /** Remove a model from the registry (metadata). rac_model_registry_remove_proto */
  deleteModel(modelId: string): Promise<void>;

  // model lifecycle (generic, one model per component)
  /** Load a registered model. ModelLoadRequest -> ModelLoadResult. rac_model_lifecycle_load_proto */
  loadModel(request: ProtoBytes): Promise<ProtoBytes>;
  /** Resolve artifact paths without loading. ModelLoadRequest -> ModelLoadResult. rac_model_lifecycle_resolve_paths_proto */
  resolveModelPaths(request: ProtoBytes): Promise<ProtoBytes>;
  /** Unload a component's current model. ModelUnloadRequest -> ModelUnloadResult. rac_model_lifecycle_unload_proto */
  unloadModel(request: ProtoBytes): Promise<ProtoBytes>;
  /** The model currently loaded for a component. CurrentModelRequest -> CurrentModelResult. rac_model_lifecycle_current_model_proto */
  currentModel(request: ProtoBytes): Promise<ProtoBytes>;

  // download orchestration (commons-driven; the addon provides the HTTP transport)
  /** Plan a download. DownloadPlanRequest -> DownloadPlanResult. rac_download_plan_proto */
  downloadPlan(request: ProtoBytes): Promise<ProtoBytes>;
  /** Start a planned download (proceeds in commons; poll progress). DownloadStartRequest -> DownloadStartResult. rac_download_start_proto */
  downloadStart(request: ProtoBytes): Promise<ProtoBytes>;
  /** Cancel a download. DownloadCancelRequest -> DownloadCancelResult. rac_download_cancel_proto */
  downloadCancel(request: ProtoBytes): Promise<ProtoBytes>;
  /** Resume a download. DownloadResumeRequest -> DownloadResumeResult. rac_download_resume_proto */
  downloadResume(request: ProtoBytes): Promise<ProtoBytes>;
  /** Poll download progress. DownloadSubscribeRequest -> DownloadProgress. rac_download_progress_poll_proto */
  downloadProgressPoll(request: ProtoBytes): Promise<ProtoBytes>;

  // llm
  /** LLMGenerateRequest -> LLMGenerationResult. rac_llm_generate_proto */
  llmGenerate(request: ProtoBytes): Promise<ProtoBytes>;
  /** LLMGenerateRequest -> stream LLMStreamEvent. rac_llm_generate_stream_proto */
  llmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  /** Cancel the in-flight generation. () -> SDKEvent(cancellation). rac_llm_cancel_proto */
  llmCancel(): Promise<void>;
  /** Inject a JSON schema into the prompt. StructuredOutputOptions -> prepared request. rac_structured_output_prepare_prompt_proto */
  structuredPreparePrompt(request: ProtoBytes): Promise<ProtoBytes>;
  /** Parse + validate generated text against a schema. StructuredOutputParse -> StructuredOutputResult. rac_structured_output_parse_proto */
  structuredParse(request: ProtoBytes): Promise<ProtoBytes>;
  /** Run the commons tool-calling loop; onExecute runs each tool (ToolCall bytes -> ToolResult bytes). ToolCallingSessionCreateRequest -> ToolCallingResult. rac_tool_calling_run_loop_proto */
  toolRunLoop(request: ProtoBytes, onExecute: ToolExecutor): Promise<ProtoBytes>;
  /** Cancel the running tool-calling loop. rac_tool_calling_run_loop_cancel_proto */
  toolCancel(): Promise<void>;

  // vlm
  /** VLMGenerationRequest -> VLMResult. rac_vlm_generate_proto */
  vlmGenerate(request: ProtoBytes): Promise<ProtoBytes>;
  /** VLMGenerationRequest -> stream VLMStreamEvent. rac_vlm_stream_proto */
  vlmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  /** rac_vlm_cancel_lifecycle_proto */
  vlmCancel(): Promise<void>;

  // stt
  /** STTTranscriptionRequest -> STTOutput. rac_stt_transcribe_lifecycle_proto */
  sttTranscribe(request: ProtoBytes): Promise<ProtoBytes>;
  /** STTTranscriptionRequest -> stream STTStreamEvent. rac_stt_transcribe_stream_lifecycle_proto */
  sttTranscribeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  /** Open a live stream session. STTOptions -> session id. rac_stt_stream_start_proto */
  sttStreamStart(request: ProtoBytes): Promise<string>;
  /** Feed PCM to a live session. rac_stt_stream_feed_audio_proto */
  sttStreamFeed(session: string, pcm: ProtoBytes): Promise<void>;
  /** Stop a live session (flush final). rac_stt_stream_stop_proto */
  sttStreamStop(session: string): Promise<void>;
  /** Cancel a live session. rac_stt_stream_cancel_proto */
  sttStreamCancel(session: string): Promise<void>;
  /** Subscribe to a live session's events (STTStreamEvent). */
  sttStreamEvents(session: string, onEvent: ProtoSink): Promise<void>;
  /** () -> STTServiceState. rac_stt_state_lifecycle_proto */
  sttState(): Promise<ProtoBytes>;

  // tts
  /** TTSSynthesisRequest -> TTSOutput. rac_tts_synthesize_lifecycle_proto */
  ttsSynthesize(request: ProtoBytes): Promise<ProtoBytes>;
  /** TTSSynthesisRequest -> stream TTSStreamEvent. rac_tts_synthesize_stream_lifecycle_proto */
  ttsSynthesizeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  /** () -> TTSServiceState. rac_tts_stop_lifecycle_proto */
  ttsStop(): Promise<ProtoBytes>;
  /** () -> TTSVoiceList. rac_tts_list_voices_lifecycle_proto */
  ttsListVoices(): Promise<ProtoBytes>;

  // vad
  /** VADConfiguration -> result. rac_vad_configure_lifecycle_proto */
  vadConfigure(request: ProtoBytes): Promise<ProtoBytes>;
  /** VADProcessRequest -> VADResult. rac_vad_process_lifecycle_proto */
  vadProcess(request: ProtoBytes): Promise<ProtoBytes>;
  /** rac_vad_start_lifecycle_proto */
  vadStart(): Promise<ProtoBytes>;
  /** rac_vad_stop_lifecycle_proto */
  vadStop(): Promise<ProtoBytes>;
  /** rac_vad_reset_lifecycle_proto */
  vadReset(): Promise<ProtoBytes>;

  // embeddings + rerank
  /** EmbeddingsRequest -> EmbeddingsResult. rac_embeddings_embed_batch_lifecycle_proto */
  embed(request: ProtoBytes): Promise<ProtoBytes>;
  /** RerankRequest -> RerankResult. rac_rerank_component_rerank_proto */
  rerank(request: ProtoBytes): Promise<ProtoBytes>;

  // diarization + segmentation
  /** DiarizationRequest -> DiarizationResult. rac_diarization_diarize_lifecycle_proto */
  diarize(request: ProtoBytes): Promise<ProtoBytes>;
  /** SegmentationRequest -> SegmentationResult. rac_segmentation_segment_lifecycle_proto */
  segment(request: ProtoBytes): Promise<ProtoBytes>;

  // lora + image generation
  /** LoRAApplyRequest -> LoRAApplyResult. rac_lora_apply_proto */
  loraApply(request: ProtoBytes): Promise<ProtoBytes>;
  /** LoRARemoveRequest -> LoRAState. rac_lora_remove_proto */
  loraRemove(request: ProtoBytes): Promise<ProtoBytes>;
  /** LoRAState -> LoRAState. rac_lora_list_proto */
  loraList(request: ProtoBytes): Promise<ProtoBytes>;
  /** LoRAState -> LoRAState. rac_lora_state_proto */
  loraState(request: ProtoBytes): Promise<ProtoBytes>;
  /** DiffusionGenerationRequest -> DiffusionResult. rac_diffusion_generate_lifecycle_proto */
  imageGenerate(request: ProtoBytes): Promise<ProtoBytes>;

  // rag (session handles are opaque string ids owned by the backend)
  /** RAGConfiguration -> session id. rac_rag_session_create_proto */
  ragOpen(config: ProtoBytes): Promise<string>;
  /** RAGDocument -> RAGStatistics. rac_rag_ingest_proto */
  ragIngest(session: string, document: ProtoBytes): Promise<ProtoBytes>;
  /** RAGQueryOptions -> RAGResult. rac_rag_query_proto */
  ragQuery(session: string, query: ProtoBytes): Promise<ProtoBytes>;
  /** RAGQueryOptions -> stream RAGStreamEvent. rac_rag_query_stream_proto */
  ragQueryStream(session: string, query: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  /** RAGSearchRequest -> RAGSearchResponse. rac_rag_search_proto */
  ragSearch(session: string, request: ProtoBytes): Promise<ProtoBytes>;
  /** () -> RAGStatistics. rac_rag_stats_proto */
  ragStats(session: string): Promise<ProtoBytes>;
  /** () -> RAGStatistics. rac_rag_clear_proto */
  ragClear(session: string): Promise<ProtoBytes>;
  /** rac_rag_cancel_proto */
  ragCancel(session: string): Promise<void>;
  /** rac_rag_session_destroy_proto */
  ragClose(session: string): Promise<void>;

  // secure store (platform IoC, not proto)
  secureSet(key: string, value: string): Promise<void>;
  secureGet(key: string): Promise<string | null>;
  secureDelete(key: string): Promise<void>;
}

/**
 * Backend operations whose last argument is a per-event proto sink. The RPC
 * transport needs to know which stream so it can wire the callback across the
 * MessagePort.
 */
export const BACKEND_STREAMING_METHODS: ReadonlySet<string> = new Set([
  'llmGenerateStream',
  'vlmGenerateStream',
  'sttTranscribeStream',
  'sttStreamEvents',
  'ttsSynthesizeStream',
  'ragQueryStream',
]);

/**
 * Every backend operation name. The RPC allowlist is derived from this set, so a
 * method that is not listed here cannot be dispatched across the boundary. The
 * `satisfies` clause makes tsc reject any entry that is not a real RaBackend
 * method; backend.test.ts adds the reverse check (every method is listed).
 */
export const BACKEND_METHODS = [
  'version',
  'initialize',
  'configureControlPlane',
  'shutdown',
  'hasControlPlane',
  'devicePersistentId',
  'devStagingBaseUrl',
  'frameworksForCapability',
  'deviceType',
  'registerModel',
  'registerModelFromUrl',
  'modelRegistryList',
  'modelRegistryQuery',
  'registerMultiFile',
  'modelList',
  'modelGet',
  'deleteModel',
  'loadModel',
  'resolveModelPaths',
  'unloadModel',
  'currentModel',
  'downloadPlan',
  'downloadStart',
  'downloadCancel',
  'downloadResume',
  'downloadProgressPoll',
  'llmGenerate',
  'llmGenerateStream',
  'llmCancel',
  'structuredPreparePrompt',
  'structuredParse',
  'toolRunLoop',
  'toolCancel',
  'vlmGenerate',
  'vlmGenerateStream',
  'vlmCancel',
  'sttTranscribe',
  'sttTranscribeStream',
  'sttStreamStart',
  'sttStreamFeed',
  'sttStreamStop',
  'sttStreamCancel',
  'sttStreamEvents',
  'sttState',
  'ttsSynthesize',
  'ttsSynthesizeStream',
  'ttsStop',
  'ttsListVoices',
  'vadConfigure',
  'vadProcess',
  'vadStart',
  'vadStop',
  'vadReset',
  'embed',
  'rerank',
  'diarize',
  'segment',
  'loraApply',
  'loraRemove',
  'loraList',
  'loraState',
  'imageGenerate',
  'ragOpen',
  'ragIngest',
  'ragQuery',
  'ragQueryStream',
  'ragSearch',
  'ragStats',
  'ragClear',
  'ragCancel',
  'ragClose',
  'secureSet',
  'secureGet',
  'secureDelete',
] as const satisfies readonly (keyof RaBackend)[];

/** RPC method name for a backend operation, namespaced so it cannot collide. */
export function rpcMethodFor(op: string): string {
  return `v3.${op}`;
}
