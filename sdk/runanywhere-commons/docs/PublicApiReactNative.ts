/*
 * PUBLIC API SNAPSHOT — React Native SDK (sdk/runanywhere-react-native/packages/core)
 * Audit reference only. NOT compilable. Compare against PublicApiSwift.swift (same 16 areas).
 * Entry: `RunAnywhere` object (Public/RunAnywhere.ts) + Public/Extensions/*. NitroModules/JSI.
 * Hermes caveat: all streams are AsyncIterable consumed via manual next()/return() — never `for await`.
 *
 * Markers:
 *   [MISSING]  Swift has it, RN has NO equivalent (real gap)
 *   [RN-ONLY]  RN has it, Swift does not
 *   [DIVERGE]  same feature, different name/shape (RN async/Promise over the Nitro bridge)
 *
 * HEADLINE: RN is close to full parity. Real gaps: web-search tool (2), VLM prompt-overload,
 * LoRA 2nd apply overload, standalone unsubscribeSDKEvents. Everything else is Promise-shaping.
 */

// =====================================================================
// 1. INIT / LIFECYCLE  (RunAnywhere object)
// =====================================================================
get isInitialized(): boolean;
get areServicesReady(): boolean;
get isActive(): boolean;
get environment(): SDKEnvironment | null;
get version(): string;
events: EventBus;
isAuthenticated(): Promise<boolean>;               // [DIVERGE] Swift sync Bool
getUserId(): Promise<string | null>;               // [DIVERGE] Swift sync String?
getOrganizationId(): Promise<string | null>;       // [DIVERGE] Swift sync String?
isDeviceRegistered(): Promise<boolean>;            // [DIVERGE] Swift sync Bool
getDeviceId(): Promise<string>;                    // [RN-ONLY] method form
get deviceId(): Promise<string>;                   // [DIVERGE] Swift throwing sync property
setHfToken(token: string): Promise<void>;
initialize(options: SDKInitOptions): Promise<void>; // [DIVERGE] single options-bag vs Swift 2 positional overloads
completeServicesInitialization(): Promise<void>;
reset(): Promise<void>;

// =====================================================================
// 2. LLM
// =====================================================================
generate(prompt: string, options?: LLMGenerationOptions): Promise<LLMGenerationResult>;
generate(request: LLMGenerateRequest): Promise<LLMGenerationResult>;
generateStream(prompt: string, options?: LLMGenerationOptions): AsyncIterable<LLMStreamEvent>;
generateStream(request: LLMGenerateRequest): AsyncIterable<LLMStreamEvent>;
cancelGeneration(): Promise<void>;
aggregateStream(prompt: string, iterable: AsyncIterable<LLMStreamEvent>, onToken?: (t: string) => void | Promise<void>): Promise<LLMGenerationResult>;

// --- Structured output ---
generateStructured<T>(prompt: string, schema: JSONSchema, options?: StructuredOutputOptions): Promise<StructuredOutputResult>;
generateWithStructuredOutput(prompt: string, structuredOutput: StructuredOutputOptions, options?: LLMGenerationOptions): Promise<LLMGenerationResult>;
generateStructuredStream(prompt: string, schema: JSONSchema, options?: StructuredOutputOptions): AsyncIterable<StructuredOutputStreamEvent>;
extractStructuredOutput(text: string, schema: JSONSchema): Promise<StructuredOutputResult>;

// --- Tools ---
registerTool(definition: ToolDefinition, executor: ToolExecutor): Promise<void>;
unregisterTool(toolName: string): Promise<void>;
getRegisteredTools(): Promise<ToolDefinition[]>;
clearTools(): Promise<void>;
executeTool(toolCall: ToolCall): Promise<ToolResult>;
generateWithTools(prompt: string, options?: Partial<ToolCallingOptions>, extra?: GenerateWithToolsOptions): Promise<ToolCallingResult>; // [RN-ONLY] extra: { signal(AbortSignal), llmOptions, validateCalls, history }

// --- Web search ---
// [MISSING] webSearchToolDefinition
// [MISSING] registerWebSearchTool()

// =====================================================================
// 3. STT  — FULL PARITY
// =====================================================================
transcribe(audio: Uint8Array, options?: Partial<STTOptions>): Promise<STTOutput>;
transcribeStream(audio: AsyncIterable<Uint8Array>, options?: Partial<STTOptions>): AsyncIterable<STTPartialResult>;

// =====================================================================
// 4. TTS  — FULL PARITY
// =====================================================================
synthesize(text: string, options?: Partial<TTSOptions>): Promise<TTSOutput>;
synthesizeStream(text: string, options?: Partial<TTSOptions>): AsyncIterable<TTSOutput>;
stopSynthesis(): Promise<void>;
speak(text: string, options?: Partial<TTSOptions>): Promise<TTSSpeakResult>;
stopSpeaking(): Promise<void>;

// =====================================================================
// 5. VAD  — FULL PARITY
// =====================================================================
detectVoiceActivity(audio: Uint8Array | Float32Array | string | ArrayBuffer, options?: Partial<VADOptions>): Promise<VADResult>; // [DIVERGE] wide input union vs Swift Data
streamVAD(audio: AsyncIterable<Uint8Array>, options?: Partial<VADOptions>): AsyncIterable<VADResult>;
resetVAD(): Promise<void>;

// =====================================================================
// 6. VLM
// =====================================================================
processImage(image: VLMImage, options: Partial<VLMGenerationOptions>): Promise<VLMResult>;
processImageStream(image: VLMImage, options: Partial<VLMGenerationOptions>): Promise<AsyncIterable<VLMStreamEvent>>; // [DIVERGE] Promise-wrapped iterable
// [MISSING] processImageStream(image, prompt, options) second overload — prompt must go in options.prompt
cancelVLMGeneration(): Promise<void>;

// =====================================================================
// 7. DIFFUSION  (Apple-gated; throws off-Apple)  — FULL PARITY
// =====================================================================
generateImage(options: Partial<DiffusionGenerationOptions>): Promise<DiffusionResult>;
generateImageStream(options: Partial<DiffusionGenerationOptions>): Promise<AsyncIterable<DiffusionStreamEvent>>; // [DIVERGE] Promise-wrapped
cancelImageGeneration(): Promise<void>;

// =====================================================================
// 8. EMBEDDINGS  (RunAnywhere.embeddings)  — FULL PARITY
// =====================================================================
get isLoaded(): boolean;                            // [DIVERGE] TS-cached vs Swift sync snapshot
get currentModelID(): string | null;
embed(text: string, modelID: string, options?: EmbeddingsOptions): Promise<EmbeddingsResult>;
embedBatch(request: EmbeddingsRequest, modelID: string): Promise<EmbeddingsResult>;
unload(): Promise<void>;

// =====================================================================
// 9. RAG  — FULL PARITY (ragCancelQuery correctly absent, matching Swift)
// =====================================================================
ragResolvedConfiguration(embeddingModel: ModelInfo, llmModel: ModelInfo, baseConfiguration?: RAGConfiguration): Promise<RAGConfiguration>;
ragCreatePipeline(config: RAGConfiguration): Promise<void>;
ragCreatePipeline(args: { embeddingModel: ModelInfo; llmModel: ModelInfo; baseConfiguration?: RAGConfiguration }): Promise<void>;
ragDestroyPipeline(): Promise<void>;
ragIngest(document: RAGDocument): Promise<RAGStatistics>;
ragAddDocumentsBatch(documents: RAGDocument[]): Promise<void>;
ragQuery(question: string, options?: Partial<Omit<RAGQueryOptions, "question">>): Promise<RAGResult>;
ragQuery(options: RAGQueryOptions): Promise<RAGResult>;
ragQueryStream(question: string, options?): AsyncIterable<RAGStreamEvent>;
ragQueryStream(options: RAGQueryOptions): AsyncIterable<RAGStreamEvent>;
ragClearDocuments(): Promise<void>;
ragGetDocumentCount(): Promise<number>;
ragDocumentCount(): Promise<number>;
ragGetStatistics(): Promise<RAGStatistics>;

// =====================================================================
// 10. LoRA  (RunAnywhere.lora)
// =====================================================================
apply(request: LoRAApplyRequest): Promise<LoRAApplyResult>;
// [MISSING] second apply(entry, localPath?, scale?, replaceExisting?) overload — covered by applyCatalogAdapter
applyCatalogAdapter(entry: LoraAdapterCatalogEntry, options?: { localPath?: string; scale?: number; replaceExisting?: boolean }): Promise<LoRAApplyResult>;
remove(request: LoRARemoveRequest): Promise<LoRAState>;
list(request?: LoRAState): Promise<LoRAState>;
state(request?: LoRAState): Promise<LoRAState>;
checkCompatibility(config: LoRAAdapterConfig): Promise<LoraCompatibilityResult>;
register(entry: LoraAdapterCatalogEntry): Promise<LoraAdapterCatalogEntry>;
registerArtifact(entry: LoraAdapterCatalogEntry): Promise<ModelInfo>;
download(entry: LoraAdapterCatalogEntry, onProgress?: (p: DownloadProgress) => void): Promise<string>;
listCatalog(request?: LoraAdapterCatalogListRequest): Promise<LoraAdapterCatalogListResult>;
queryCatalog(query: LoraAdapterCatalogQuery): Promise<LoraAdapterCatalogListResult>;
getCatalogEntry(request: LoraAdapterCatalogGetRequest): Promise<LoraAdapterCatalogGetResult>;
markDownloadCompleted(request: LoraAdapterDownloadCompletedRequest): Promise<LoraAdapterDownloadCompletedResult>;
markImportCompleted(request: LoraAdapterDownloadCompletedRequest): Promise<LoraAdapterDownloadCompletedResult>;
importAdapter(sourcePath: string): Promise<LoraAdapterImportResult>;
adaptersForModel(modelId: string): Promise<LoraAdapterCatalogEntry[]>;
allRegistered(): Promise<LoraAdapterCatalogEntry[]>;

// =====================================================================
// 11. VOICE AGENT  — FULL PARITY
// =====================================================================
defaultVADModelID: string;
ensureDefaultVAD(modelID?: string): Promise<boolean>;
initializeVoiceAgent(config: VoiceAgentComposeConfig): Promise<void>;
getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates>;
initializeVoiceAgentWithLoadedModels(ttsVoiceID?: string, ensureVAD?: boolean): Promise<void>;
cleanupVoiceAgent(): Promise<void>;
processVoiceTurn(audioData: ArrayBuffer | Uint8Array): Promise<VoiceAgentResult>;
streamVoiceAgent(): AsyncIterable<VoiceEvent>;

// =====================================================================
// 12. MODELS — LIFECYCLE  — FULL PARITY
// =====================================================================
loadModel(request: ModelLoadRequest): Promise<ModelLoadResult>;
unloadModel(request: ModelUnloadRequest): Promise<ModelUnloadResult>;
currentModel(request?: CurrentModelRequest): Promise<CurrentModelResult | null>;
modelInfoForCategory(category: ModelCategory): Promise<ModelInfo | null>;
componentLifecycleSnapshot(component: SDKComponent): Promise<ComponentLifecycleSnapshot | null>;

// =====================================================================
// 13. MODELS — REGISTRY  — FULL PARITY
// =====================================================================
listModels(request?: ModelListRequest): Promise<ModelListResult>;
queryModels(query: ModelQuery): Promise<ModelListResult>;
getModel(request: ModelGetRequest): Promise<ModelGetResult>;
downloadedModels(): Promise<ModelListResult>;
refreshModelRegistry(options?: { rescanLocal?: boolean; includeRemoteCatalog?: boolean; pruneOrphans?: boolean }): Promise<void>;
inferModelFileRole(filename: string, modality: ModelCategory): ModelFileRole;
getDefaultFramework(category: ModelCategory): InferenceFramework; // [RN-ONLY] Swift exposes as RAModelCategory.defaultFramework property

// =====================================================================
// 14. DOWNLOAD  — FULL PARITY
// =====================================================================
downloadModel(model: ModelInfo, onProgress?: (p: DownloadProgress) => void): Promise<DownloadProgress>;
downloadModelStream(model: ModelInfo): AsyncIterable<DownloadProgress>;

// =====================================================================
// 15. STORAGE  — FULL PARITY (register split into 3 named fns w/ option bags)
// =====================================================================
registerModel(input: RegisterModelInput): Promise<ModelInfo>;                 // url form
registerArchiveModel(input: RegisterArchiveModelInput): Promise<ModelInfo>;   // [DIVERGE] Swift registerModel(archive:) overload
registerMultiFileModel(input: RegisterMultiFileModelInput): Promise<ModelInfo>; // [DIVERGE] Swift registerModel(multiFile:) overload
registerModelFromUrl(url: string, name: string, framework: InferenceFramework, options?): Promise<ModelInfo>; // [RN-ONLY] positional convenience
importModel(request: ModelImportRequest): Promise<ModelImportResult>;
getStorageInfo(): Promise<StorageInfo | null>;
deleteStorage(request: StorageDeleteRequest): Promise<StorageDeleteResult>;
deleteModel(modelId: string): Promise<StorageDeleteResult>;
clearCache(): Promise<void>;
cleanTempFiles(): Promise<boolean>;                                           // [DIVERGE] Swift returns void

// =====================================================================
// 16. EVENTS + MISC  — near parity
// =====================================================================
subscribeSDKEvents(callback: (event: SDKEvent) => void): Promise<() => Promise<void>>; // [DIVERGE] returns unsubscribe closure
// [MISSING] standalone unsubscribeSDKEvents() — folded into the closure above
publishSDKEvent(event: SDKEvent): Promise<boolean>;
pollSDKEvent(): Promise<SDKEvent | null>;
publishSDKFailure(options: { errorCode: number; message: string; component: string; operation: string; recoverable: boolean }): Promise<boolean>;
// EventBus (RunAnywhere.events): on/eventsFor/llmEvents/.../voiceEventPayloads/modelLifecycle/modelLoaded/modelUnloaded + [RN-ONLY] free fn modelLifecycleChange(event)
// Logging (sync void): configureLogging/setLocalLoggingEnabled/setLogLevel/addLogDestination/setDebugMode/flushLogs
// Audio (sync): pcm16ToFloat32/pcm16ToFloat32Samples/pcm16ToWav
// Solutions (RunAnywhere.solutions): run(SolutionRunArgs union {config|configBytes|yaml}) -> SolutionHandle
// PluginLoader (RunAnywhere.pluginLoader): apiVersion/registeredCount/registeredNames/listLoaded/load/unload

// =====================================================================
// CONSOLIDATED
// =====================================================================
// TRULY MISSING: webSearchToolDefinition, registerWebSearchTool, VLM prompt-overload,
//   LoRA 2nd apply overload, standalone unsubscribeSDKEvents, 2nd initialize overload
// RN-ONLY: getDeviceId, registerModelFromUrl, getDefaultFramework, generateWithTools extra bag (AbortSignal),
//   EventBus modelLifecycleChange free fn
// DIVERGE: auth reads async, Promise-wrapped VLM/Diffusion streams, cleanTempFiles->boolean,
//   register split into 3 named fns, all streams manual-iterator AsyncIterable (Hermes)
