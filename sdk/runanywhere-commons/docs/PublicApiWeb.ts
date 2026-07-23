/*
 * PUBLIC API SNAPSHOT — Web SDK (sdk/runanywhere-web/packages/core)
 * Audit reference only. NOT compilable. Compare against PublicApiSwift.swift (same 16 areas).
 * Entry: `RunAnywhere` object (Public/RunAnywhere.ts) + spread ...flatFacade (RunAnywhere+FlatFacade.ts).
 * Emscripten WASM + TS. Streaming is AsyncIterable; LLM stream returns a rich LLMStreamingResult.
 * (Single committed source tree — no old/next split.)
 *
 * Markers:
 *   [MISSING]  Swift has it, Web has NO public equivalent (real gap)
 *   [WEB-ONLY] Web has it, Swift does not (browser/WASM plumbing — mostly justified)
 *   [DIVERGE]  same feature, different name/shape
 *
 * HEADLINE: Web has the MOST gaps AND the most extras. Real feature gaps: setHfToken,
 * web-search tool, ragDocumentCount, public inferModelFileRole, standalone unsubscribeSDKEvents.
 * Diffusion absent = expected (Apple-only). Huge WEB-ONLY surface for browser storage/handles/hybrid.
 */

// =====================================================================
// 1. INIT / LIFECYCLE  (RunAnywhere object)
// =====================================================================
get isInitialized(): boolean;
get areServicesReady(): boolean;
get isActive(): boolean;
get version(): string;
get environment(): SDKEnvironment | null;
get events(): EventBus;
get deviceId(): string;                              // [DIVERGE] throwing getter vs Swift deviceId() throws
get isAuthenticated(): boolean;
getUserId(): string | null;
getOrganizationId(): string | null;
isDeviceRegistered(): boolean;
// [MISSING] setHfToken — no HF-token setter anywhere in packages/*/src
initialize(options: SDKInitOptions): Promise<void>;  // [DIVERGE] single options-bag vs Swift 2 overloads
completeServicesInitialization(): Promise<void>;
reset(): Promise<void>;                               // delegates to shutdown()
// [WEB-ONLY] runtime getter, setRuntime(mode), ensureServicesReady(), hydrateModelRegistry(),
//            shutdown(), storage namespace (FS Access / OPFS)

// =====================================================================
// 2. LLM
// =====================================================================
generate(options: TextGenerationOptions, extra?: CancellableCall): Promise<LLMGenerationResult>; // [DIVERGE] options-object (prompt is a field), no (prompt, options) top-level form
generateStream(options, extra?): Promise<LLMStreamingResult>;                                     // [DIVERGE] returns { events, stream, result, cancel } not bare iterable
cancelGeneration(): void;
// textGeneration.generate(request) / generate(options) overloads exist under RunAnywhere.textGeneration
// aggregateStream(prompt, streaming, onToken?, onThinking?) — [DIVERGE] only under RunAnywhere.textGeneration, not flat

// --- Structured output (flat) ---
generateStructured(prompt: string, schema: StructuredOutputSchema, options?): Promise<StructuredOutputResult>;
generateWithStructuredOutput(prompt: string, structuredOutput: Partial<StructuredOutputOptions>, options?): Promise<LLMGenerationResult>;
generateStructuredStream(prompt: string, schema, options?): AsyncIterable<StructuredOutputStreamEvent>;
extractStructuredOutput(text: string, schema): StructuredOutputResult;
// [WEB-ONLY] structuredOutput.{supportsProtoStructuredOutput, preparePrompt, validate}

// --- Tools (RunAnywhere.toolCalling.*) ---
registerTool(definition: ToolDefinition, executor: ToolExecutor): void;
unregisterTool(name: string): void;
getRegisteredTools(): ToolDefinition[];
clearTools(): void;
executeTool(toolCall: ToolCall): Promise<ToolResult>;
generateWithTools(prompt: string, options?: Partial<ToolCallingOptions>, extra?: GenerateWithToolsOptions): Promise<ToolCallingResult>; // [DIVERGE] extra: { signal, llmOptions, validateCalls, history }
// [WEB-ONLY] toolCalling.{parse, parseToolCall, formatPrompt, validateCall, buildInitialPrompt, buildFollowupPrompt, supportsProtoToolCalling, ...}

// --- Web search ---
// [MISSING] webSearchToolDefinition
// [MISSING] registerWebSearchTool()

// =====================================================================
// 3. STT  — FULL PARITY (+ handle namespace)
// =====================================================================
transcribe(audio: Uint8Array | Float32Array, options?: TranscribeOptions, extra?: CancellableCall): Promise<STTOutput>;
transcribeStream(audio, options?): AsyncIterable<STTPartialResult>;
// [WEB-ONLY] stt.{create, loadModel, isLoaded, transcribe(handle,...), unload, destroy, supportsProtoSTT}

// =====================================================================
// 4. TTS
// =====================================================================
synthesize(text: string, options?: SynthesizeOptions, extra?): Promise<TTSOutput>;
synthesizeStream(handle, text: string, options, extra?): AsyncIterable<TTSOutput>;   // [DIVERGE] requires a component handle (no lifecycle-auto top-level form)
stopSynthesis(handle): boolean;                                                       // [DIVERGE] takes handle
speak(text: string, options?): Promise<TTSSpeakResult>;
stopSpeaking(handle?): boolean;                                                       // [DIVERGE] optional handle
// [WEB-ONLY] tts.{create, loadVoice, listVoices, listLoadedVoices, synthesize, stop, destroy}

// =====================================================================
// 5. VAD
// =====================================================================
detectVoiceActivity(audio: Float32Array, options?: DetectVoiceOptions): Promise<VADResult>;
streamVAD(audio: AsyncIterable<Float32Array>, options?): AsyncIterable<VADResult>;    // native stream requires 16kHz (throws otherwise)
resetVAD(handle): boolean;                                                            // [DIVERGE] requires handle vs Swift parameterless
// [WEB-ONLY] vad.{create, configure, initialize, loadModel, process, statistics, setActivityHandler, start, stop, reset, destroy}

// =====================================================================
// 6. VLM  — FULL PARITY (both overloads present)
// =====================================================================
processImage(image: VLMImage, options: VLMGenerationOptions, extra?: CancellableCall): Promise<VLMResult>;
processImageStream(image: VLMImage, options: VLMGenerationOptions): Promise<AsyncIterable<VLMStreamEvent>>; // [DIVERGE] Promise-wrapped
processImageStream(image: VLMImage, prompt: string, options?: VLMGenerationOptions): Promise<AsyncIterable<VLMStreamEvent>>;
cancelVLMGeneration(): Promise<void>;

// =====================================================================
// 7. DIFFUSION  (Apple-only in Swift)
// =====================================================================
// [MISSING] generateImage / generateImageStream / cancelImageGeneration — NO public facade.
//   Only an internal DiffusionProtoAdapter exists. Expected non-parity (Apple/CoreML only).

// =====================================================================
// 8. EMBEDDINGS  (RunAnywhere.embeddings)  — FULL PARITY
// =====================================================================
get isLoaded(): boolean;
get currentModelID(): string | null;
embed(text: string, modelID: string, options?: EmbeddingsOptions): Promise<EmbeddingsResult>; // [DIVERGE] modelID required positional
embedBatch(request: EmbeddingsRequest, modelID: string): Promise<EmbeddingsResult>;
unload(): Promise<void>;
// [WEB-ONLY] embeddingCosineSimilarity, embeddingComputeNorm, embeddingsResultProcessingTime

// =====================================================================
// 9. RAG  (flat verbs)
// =====================================================================
ragResolvedConfiguration(embeddingModelId, llmModelId, baseConfiguration?): Promise<RAGConfiguration>;
ragCreatePipeline(config): Promise<void>;
ragCreatePipeline(embeddingModelId, llmModelId, baseConfiguration?): Promise<void>;
ragDestroyPipeline(): Promise<void>;
ragIngest(text: string, metadataJson?): Promise<void>;
ragIngest(document: RAGDocument): Promise<RAGStatistics>;
ragClearDocuments(): Promise<void>;
ragGetDocumentCount(): Promise<number>;
// [MISSING] ragDocumentCount — only ragGetDocumentCount exists (Swift has both)
ragQuery(question: string, options?): Promise<RAGResult>;
ragQuery(options: RAGQueryOptions): Promise<RAGResult>;
ragQueryStream(question: string, options?): AsyncIterable<RAGStreamEvent>;
ragQueryStream(options: RAGQueryOptions): AsyncIterable<RAGStreamEvent>;
ragAddDocumentsBatch(documents: Array<{ text: string; metadataJson?: string }>): Promise<void>;
ragGetStatistics(): Promise<RAGStatistics>;
// ragCancelQuery correctly absent (matches Swift)
// [WEB-ONLY] rag.{setProvider, createNativeProvider, availability, pipelineState, ensureReady, listDocuments, removeDocument, capabilities}

// =====================================================================
// 10. LoRA  (RunAnywhere.lora)
// =====================================================================
apply(request: LoRAApplyRequest): Promise<LoRAApplyResult>;
// [MISSING] second apply overload — covered by applyCatalogAdapter
applyCatalogAdapter(entry, options?): Promise<LoRAApplyResult>;
remove(request): Promise<LoRAState>;
list(request?): Promise<LoRAState>;
state(request?): Promise<LoRAState>;
checkCompatibility(config): Promise<LoraCompatibilityResult>;
register(entry): Promise<LoraAdapterCatalogEntry>;
registerArtifact(entry): Promise<ModelInfo>;
download(entry, onProgress?): Promise<string>;
listCatalog(request?): Promise<LoraAdapterCatalogListResult>;
queryCatalog(query): Promise<LoraAdapterCatalogListResult>;
getCatalogEntry(request): Promise<LoraAdapterCatalogGetResult>;
markDownloadCompleted(request): Promise<LoraAdapterDownloadCompletedResult>;
markImportCompleted(request): Promise<LoraAdapterDownloadCompletedResult>;
importAdapter(file: File | Blob, filename?: string): Promise<LoraAdapterImportResult>; // [DIVERGE] browser File/Blob vs Swift URL/path
adaptersForModel(modelId): Promise<LoraAdapterCatalogEntry[]>;
allRegistered(): Promise<LoraAdapterCatalogEntry[]>;
// [WEB-ONLY] lora.{supportsNative, missingExports, supportsNativeCatalog, catalog}

// =====================================================================
// 11. VOICE AGENT  (flat verbs)  — FULL PARITY
// =====================================================================
defaultVADModelID: string;
ensureDefaultVAD(modelID?: string): Promise<boolean>;
initializeVoiceAgent(config: VoiceAgentComposeConfig): Promise<void>;
getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates>;
initializeVoiceAgentWithLoadedModels(ttsVoiceID?: string, ensureVAD?: boolean): Promise<void>;
cleanupVoiceAgent(): Promise<void>;
processVoiceTurn(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult>;
streamVoiceAgent(req?: VoiceAgentRequest, signal?: AbortSignal): AsyncIterable<VoiceEvent>; // [DIVERGE] AbortSignal + default req
// [WEB-ONLY] voiceAgent.{availability, isAvailable, isReady, areAllComponentsReady, transcribe, generateResponse, synthesizeSpeech}

// =====================================================================
// 12. MODELS — LIFECYCLE  — FULL PARITY
// =====================================================================
loadModel(request: ModelLoadRequest): Promise<ModelLoadResult | null>;
unloadModel(request: ModelUnloadRequest): Promise<ModelUnloadResult | null>;
currentModel(request?: CurrentModelRequest): CurrentModelResult | null;
modelInfoForCategory(category: ModelCategory): ModelInfo | null;
componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot | null;

// =====================================================================
// 13. MODELS — REGISTRY
// =====================================================================
listModels(): ModelInfoList | null;
queryModels(query: ModelQuery): ModelInfoList | null;
getModel(modelId: string): ModelInfo | null;                 // [DIVERGE] takes id vs Swift ModelGetRequest
downloadedModels(): ModelInfoList | null;
refreshModelRegistry(options?: RefreshOptions): boolean;
// [MISSING] inferModelFileRole — only internal ProtoWasmBridge.inferModelFileRole, not on public surface
getDefaultFramework(category: ModelCategory): InferenceFramework; // [WEB-ONLY]
// [WEB-ONLY] modelRegistry.{registerModel, importModel, updateModel, updateDownloadStatus, removeModel, availability, defaultFramework}

// =====================================================================
// 14. DOWNLOAD  — FULL PARITY
// =====================================================================
downloadModel(input: string | DownloadModelOptions, extra?: CancellableCall): Promise<DownloadProgress>; // [DIVERGE] accepts id string or options w/ onProgress
downloadModelStream(input: string | DownloadModelOptions, extra?): AsyncIterable<DownloadProgress>;

// =====================================================================
// 15. STORAGE  — FULL PARITY (register split into 3 named positional fns)
// =====================================================================
registerModel(url: string, name: string, framework: InferenceFramework, options?: RegisterModelOptions): ModelInfo;
registerModelArchive(url: string, name: string, framework: InferenceFramework, archiveType: ModelArtifactType, options?): ModelInfo; // [DIVERGE] Swift registerModel(archive:) overload
registerModelMultiFile(options: RegisterMultiFileOptions): ModelInfo;                                                               // [DIVERGE] Swift registerModel(multiFile:) overload
importModel(request: ModelImportRequest): ModelImportResult;
getStorageInfo(request): StorageInfoResult;
deleteStorage(request): Promise<StorageDeleteResult>;
deleteModel(modelId: string): Promise<StorageDeleteResult>;
clearCache(): Promise<void>;
cleanTempFiles(): Promise<void>;
// [WEB-ONLY] storage.{isLocalStorageSupported, chooseLocalStorageDirectory, restoreLocalStorage, requestLocalStorageAccess, info, availability, delete, deleteModel} (FS Access / OPFS)

// =====================================================================
// 16. EVENTS + MISC
// =====================================================================
// SDK events (RunAnywhere.sdkEvents.*):
//   subscribe(handler) -> SDKEventUnsubscribe | null   [DIVERGE] closure, no standalone unsubscribeSDKEvents [MISSING]
//   publish(event) -> boolean; poll() -> SDKEvent | null; publishFailure({...}) -> boolean; clearQueue() [WEB-ONLY]
// EventBus (RunAnywhere.events): modelLifecycle/modelLoaded/modelUnloaded/modelLifecycleChange
// Logging (flat, sync void): configureLogging/setLocalLoggingEnabled/setLogLevel/addLogDestination/setDebugMode/flushLogs
// Audio (flat, sync): pcm16ToFloat32/pcm16ToFloat32Samples/pcm16ToWav
// Solutions (RunAnywhere.solutions): run(SolutionRunInput) -> SolutionHandle
// PluginLoader (RunAnywhere.pluginLoader): apiVersion/registeredCount/registeredNames/listLoaded/load/unload

// =====================================================================
// EXTRAS beyond the 16 areas
// =====================================================================
// - Hybrid STT (entire area): RunAnywhere.hybrid.*, HybridSttRouter, Cloud/cloud,
//   registerCloudSttProvider/unregisterCloudSttProvider, setHybridDeviceStateProvider
// - Backend/runtime plumbing: setStreamWorkerFactory, @runanywhere/web/{backend,internal,browser} subpaths

// =====================================================================
// CONSOLIDATED
// =====================================================================
// TRULY MISSING (real gaps): setHfToken, webSearchToolDefinition, registerWebSearchTool,
//   ragDocumentCount, public inferModelFileRole, standalone unsubscribeSDKEvents
// EXPECTED-MISSING: diffusion (Apple-only)
// WEB-ONLY (mostly justified): runtime/storage browser namespaces, stt/tts/vad handle namespaces,
//   toolCalling primitives, rag provider namespace, voiceAgent namespace, hybrid STT, modelRegistry namespace
// DIVERGE: handle-based tts/vad top-level, options-bag generate, Promise-wrapped VLM stream,
//   register split into 3 named fns, sdkEvents.* naming, AbortSignal cancellation
