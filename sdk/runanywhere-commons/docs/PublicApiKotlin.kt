/*
 * PUBLIC API SNAPSHOT — Kotlin/Android SDK (sdk/runanywhere-kotlin)
 * Audit reference only. NOT compilable. Signatures mirror the real facade.
 * Compare 1:1 with PublicApiSwift.swift (same feature order).
 *
 * Markers:
 *   [DIVERGE] signature/shape differs from Swift
 *   [KT-ONLY] exists in Kotlin, absent from Swift facade (source-of-truth violation)
 *   [MISSING] Swift has it, Kotlin does not (see the Swift file for the entry)
 */
@file:Suppress("unused")

// =====================================================================
// 1. INIT / LIFECYCLE  —  object RunAnywhere (RunAnywhere.kt)
// =====================================================================
val isInitialized: Boolean
val areServicesReady: Boolean
val isActive: Boolean
val version: String
val environment: SDKEnvironment?
val events: EventBus
val isAuthenticated: Boolean
val deviceId: String                                  // [DIVERGE] Swift: throwing getter `deviceId { get throws }`
fun getUserId(): String?
fun getOrganizationId(): String?
fun isDeviceRegistered(): Boolean
fun setHfToken(token: String?)
fun initialize(apiKey: String? = null, baseURL: String? = null, environment: SDKEnvironment = SDK_ENVIRONMENT_DEVELOPMENT)
fun initialize(apiKey: String, baseURL: URL, environment: SDKEnvironment = SDK_ENVIRONMENT_PRODUCTION)
fun initialize(context: Context, apiKey: String? = null, baseURL: String? = null, environment: SDKEnvironment = SDK_ENVIRONMENT_DEVELOPMENT) // [DIVERGE] Android Context overloads (no Swift equiv, expected)
fun initialize(context: Context, apiKey: String, baseURL: URL, environment: SDKEnvironment = SDK_ENVIRONMENT_PRODUCTION)                       // [DIVERGE] "
suspend fun completeServicesInitialization()
suspend fun reset()

// =====================================================================
// 2. LLM
// =====================================================================
suspend fun RunAnywhere.generate(prompt: String, options: RALLMGenerationOptions? = null): RALLMGenerationResult
suspend fun RunAnywhere.generate(request: RALLMGenerateRequest): RALLMGenerationResult
fun RunAnywhere.generateStream(prompt: String, options: RALLMGenerationOptions? = null): Flow<RALLMStreamEvent>
fun RunAnywhere.generateStream(request: RALLMGenerateRequest): Flow<RALLMStreamEvent>
suspend fun RunAnywhere.cancelGeneration()
suspend fun RunAnywhere.aggregateStream(prompt: String, events: Flow<RALLMStreamEvent>, onThinking: (suspend (String) -> Unit)? = null, onToken: (suspend (String) -> Unit)? = null): RALLMGenerationResult
// [MISSING] webSearchToolDefinition : RAToolDefinition
// [MISSING] suspend fun RunAnywhere.registerWebSearchTool()

// --- LLM: Structured Output ---
suspend fun RunAnywhere.generateStructured(prompt: String, schema: RAJSONSchema, options: RALLMGenerationOptions? = null): RAStructuredOutputResult
suspend fun RunAnywhere.generateWithStructuredOutput(prompt: String, structuredOutput: StructuredOutputOptions, options: RALLMGenerationOptions? = null): RALLMGenerationResult
suspend fun RunAnywhere.extractStructuredOutput(text: String, schema: RAJSONSchema): RAStructuredOutputResult      // [DIVERGE] Swift is sync `throws`, not suspend
fun RunAnywhere.generateStructuredStream(prompt: String, schema: RAJSONSchema, options: RALLMGenerationOptions? = null): Flow<StructuredOutputStreamEvent>

// --- LLM: Tool Calling ---
suspend fun RunAnywhere.registerTool(definition: ToolDefinition, executor: ToolExecutor)
suspend fun RunAnywhere.unregisterTool(toolName: String)
suspend fun RunAnywhere.getRegisteredTools(): List<ToolDefinition>
suspend fun RunAnywhere.clearTools()
suspend fun RunAnywhere.executeTool(toolCall: ToolCall): ToolResult
suspend fun RunAnywhere.generateWithTools(prompt: String, options: RALLMGenerationOptions?, toolOptions: RAToolCallingOptions?, toolChoice: ToolChoiceMode?, forcedToolName: String?, validateCalls: Boolean? = null, history: List<String> = emptyList()): RAToolCallingResult

// =====================================================================
// 3. STT
// =====================================================================
suspend fun RunAnywhere.transcribe(audio: ByteArray, options: RASTTOptions = RASTTOptions.defaults()): RASTTOutput
fun RunAnywhere.transcribeStream(audio: Flow<ByteArray>, options: RASTTOptions = RASTTOptions.defaults()): Flow<RASTTPartialResult>

// =====================================================================
// 4. TTS
// =====================================================================
suspend fun RunAnywhere.synthesize(text: String, options: RATTSOptions = RATTSOptions.defaults()): RATTSOutput
fun RunAnywhere.synthesizeStream(text: String, options: RATTSOptions = RATTSOptions.defaults()): Flow<RATTSOutput>
suspend fun RunAnywhere.stopSynthesis()
suspend fun RunAnywhere.speak(text: String, options: RATTSOptions = RATTSOptions.defaults()): TTSSpeakResult
suspend fun RunAnywhere.stopSpeaking()

// =====================================================================
// 5. VAD
// =====================================================================
suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray, options: RAVADOptions? = null): RAVADResult
fun RunAnywhere.streamVAD(audio: Flow<ByteArray>, options: RAVADOptions? = null): Flow<RAVADResult>
suspend fun RunAnywhere.resetVAD()

// =====================================================================
// 6. VLM
// =====================================================================
suspend fun RunAnywhere.processImage(image: RAVLMImage, options: RAVLMGenerationOptions): RAVLMResult
fun RunAnywhere.processImageStream(image: RAVLMImage, options: RAVLMGenerationOptions): Flow<RAVLMStreamEvent>
// [MISSING] fun RunAnywhere.processImageStream(image: RAVLMImage, prompt: String, options: RAVLMGenerationOptions = ...): Flow<RAVLMStreamEvent>
suspend fun RunAnywhere.cancelVLMGeneration()

// =====================================================================
// 7. DIFFUSION
// =====================================================================
suspend fun RunAnywhere.generateImage(options: RADiffusionGenerationOptions, modelId: String? = null): RADiffusionResult // [DIVERGE] Swift takes options only, no modelId
suspend fun RunAnywhere.inpaint(inputImage: ByteArray, maskImage: ByteArray, prompt: String = "Remove the masked region.", width: Int = 512, height: Int = 512, modelId: String? = null): RADiffusionResult // [KT-ONLY]
// [MISSING] fun RunAnywhere.generateImageStream(options): Flow<RADiffusionStreamEvent>
// [MISSING] suspend fun RunAnywhere.cancelImageGeneration()

// =====================================================================
// 8. EMBEDDINGS  (val RunAnywhere.embeddings: Embeddings)
// =====================================================================
suspend fun Embeddings.isLoaded(): Boolean
suspend fun Embeddings.currentModelID(): String?
suspend fun Embeddings.embed(text: String, modelId: String, options: EmbeddingsOptions? = null): RAEmbeddingsResult
suspend fun Embeddings.embedBatch(request: EmbeddingsRequest, modelId: String): RAEmbeddingsResult
suspend fun Embeddings.unload()

// =====================================================================
// 9. RAG
// =====================================================================
suspend fun RunAnywhere.ragResolvedConfiguration(embeddingModel: RAModelInfo, llmModel: RAModelInfo, baseConfiguration: RARAGConfiguration): RARAGConfiguration
suspend fun RunAnywhere.ragCreatePipeline(embeddingModel: RAModelInfo, llmModel: RAModelInfo, baseConfiguration: RARAGConfiguration = RARAGConfiguration.defaults())
suspend fun RunAnywhere.ragCreatePipeline(config: RARAGConfiguration)
suspend fun RunAnywhere.ragDestroyPipeline()
suspend fun RunAnywhere.ragIngest(document: RARAGDocument): RARAGStatistics
suspend fun RunAnywhere.ragClearDocuments()
suspend fun RunAnywhere.ragGetDocumentCount(): Int
suspend fun RunAnywhere.ragDocumentCount(): Int                          // [DIVERGE] Swift: async computed `var ragDocumentCount`
suspend fun RunAnywhere.ragQuery(question: String, options: RAGQueryOptions? = null): RAGResult
suspend fun RunAnywhere.ragQuery(options: RAGQueryOptions): RAGResult
fun RunAnywhere.ragQueryStream(question: String, options: RAGQueryOptions? = null): Flow<RAGStreamEvent>
fun RunAnywhere.ragQueryStream(options: RAGQueryOptions): Flow<RAGStreamEvent>
suspend fun RunAnywhere.ragCancelQuery()                                 // [KT-ONLY]
suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RARAGDocument>)
suspend fun RunAnywhere.ragGetStatistics(): RARAGStatistics

// =====================================================================
// 10. LoRA  (val RunAnywhere.lora: LoRA)
// =====================================================================
suspend fun LoRA.apply(request: RALoRAApplyRequest): LoRAApplyResult
suspend fun LoRA.apply(entry: LoraAdapterCatalogEntry, localPath: String? = null, scale: Float? = null, replaceExisting: Boolean = false): LoRAApplyResult
// [MISSING] applyCatalogAdapter(entry, localPath, scale, replaceExisting)  (KT's apply(entry,...) is behaviorally equal)
suspend fun LoRA.remove(request: RALoRARemoveRequest): RALoRAState
suspend fun LoRA.list(): RALoRAState
suspend fun LoRA.state(): RALoRAState
suspend fun LoRA.checkCompatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult
suspend fun LoRA.register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry
suspend fun LoRA.registerArtifact(entry: LoraAdapterCatalogEntry): RAModelInfo
suspend fun LoRA.download(entry: LoraAdapterCatalogEntry, onProgress: (suspend (DownloadProgress) -> Unit)? = null): String
suspend fun LoRA.listCatalog(request: LoraAdapterCatalogListRequest = LoraAdapterCatalogListRequest()): LoraAdapterCatalogListResult
suspend fun LoRA.queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult
suspend fun LoRA.getCatalogEntry(request: LoraAdapterCatalogGetRequest): LoraAdapterCatalogGetResult
suspend fun LoRA.markDownloadCompleted(request: LoraAdapterDownloadCompletedRequest): LoraAdapterDownloadCompletedResult
suspend fun LoRA.importAdapter(sourcePath: String): LoraAdapterImportResult   // [DIVERGE] Swift takes `from url: URL`
suspend fun LoRA.markImportCompleted(request: LoraAdapterDownloadCompletedRequest): LoraAdapterDownloadCompletedResult
suspend fun LoRA.adaptersForModel(modelId: String): List<LoraAdapterCatalogEntry>
suspend fun LoRA.allRegistered(): List<LoraAdapterCatalogEntry>

// =====================================================================
// 11. VOICE AGENT
// =====================================================================
val RunAnywhere.defaultVADModelID: String
suspend fun RunAnywhere.ensureDefaultVAD(modelID: String? = null): Boolean
suspend fun RunAnywhere.initializeVoiceAgent(config: RAVoiceAgentComposeConfig)
suspend fun RunAnywhere.getVoiceAgentComponentStates(): RAVoiceAgentComponentStates
suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels(ttsVoiceId: String? = null, ensureVAD: Boolean = true)
suspend fun RunAnywhere.cleanupVoiceAgent()
suspend fun RunAnywhere.processVoiceTurn(audioData: ByteArray): VoiceAgentResult
fun RunAnywhere.streamVoiceAgent(): Flow<VoiceEvent>

// =====================================================================
// 12. MODELS — LIFECYCLE
// =====================================================================
suspend fun RunAnywhere.loadModel(request: RAModelLoadRequest): RAModelLoadResult
suspend fun RunAnywhere.loadModel(model: RAModelInfo): RAModelLoadResult                      // [DIVERGE] KT-extra convenience overload
suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult
suspend fun RunAnywhere.currentModel(request: CurrentModelRequest = CurrentModelRequest()): CurrentModelResult // [DIVERGE] Swift: SYNC, single overload
suspend fun RunAnywhere.currentModel(model: RAModelInfo): CurrentModelResult                  // [DIVERGE] KT-extra overload
suspend fun RunAnywhere.currentModel(candidates: Iterable<RAModelInfo>): CurrentModelResult?  // [DIVERGE] KT-extra overload
suspend fun RunAnywhere.modelInfoForCategory(category: ModelCategory): ModelInfo?             // [DIVERGE] Swift: sync
suspend fun RunAnywhere.componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot?

// =====================================================================
// 12b. MODELS — REGISTRY
// =====================================================================
suspend fun RunAnywhere.listModels(request: ModelListRequest = ModelListRequest()): ModelListResult
suspend fun RunAnywhere.queryModels(query: ModelQuery): ModelListResult
suspend fun RunAnywhere.getModel(request: ModelGetRequest): ModelGetResult
suspend fun RunAnywhere.downloadedModels(): ModelListResult
suspend fun RunAnywhere.refreshModelRegistry(rescanLocal: Boolean = true, includeRemoteCatalog: Boolean = false, pruneOrphans: Boolean = false)
fun RunAnywhere.inferModelFileRole(filename: String, modality: ModelCategory): ModelFileRole

// =====================================================================
// 13. DOWNLOAD
// =====================================================================
suspend fun RunAnywhere.downloadModel(model: RAModelInfo, onProgress: (suspend (DownloadProgress) -> Unit)? = null): DownloadProgress
fun RunAnywhere.downloadModelStream(model: RAModelInfo): Flow<DownloadProgress>

// =====================================================================
// 14. STORAGE
// =====================================================================
suspend fun RunAnywhere.registerModel(id: String? = null, name: String, url: String, framework: InferenceFramework, modality: ModelCategory = MODEL_CATEGORY_LANGUAGE, artifactType: ModelArtifactType? = null, memoryRequirement: Long? = null, supportsThinking: Boolean = false, supportsLora: Boolean = false): RAModelInfo
suspend fun RunAnywhere.registerModel(archiveUrl: String, structure: ArchiveStructure, id: String? = null, name: String, framework: InferenceFramework, modality: ModelCategory = MODEL_CATEGORY_LANGUAGE, archiveType: ArchiveType? = null, memoryRequirement: Long? = null, supportsThinking: Boolean = false, supportsLora: Boolean = false): RAModelInfo
suspend fun RunAnywhere.registerModel(multiFile: List<ModelFileDescriptor>, id: String, name: String, framework: InferenceFramework, modality: ModelCategory = MODEL_CATEGORY_LANGUAGE, memoryRequirement: Long? = null, contextLength: Int? = null, supportsThinking: Boolean = false, source: ModelSource = MODEL_SOURCE_REMOTE): RAModelInfo
suspend fun RunAnywhere.importModel(request: ModelImportRequest): ModelImportResult
suspend fun RunAnywhere.getStorageInfo(request: StorageInfoRequest = StorageInfoRequest()): StorageInfoResult
suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult
suspend fun RunAnywhere.deleteModel(modelId: String): StorageDeleteResult
suspend fun RunAnywhere.clearCache()
suspend fun RunAnywhere.cleanTempFiles()

// =====================================================================
// 15. EVENTS
// =====================================================================
// object EventBus : Flow<SDKEvent> events, start(), stop(), publish(event),
//   events(category), on(scope, handler), on(scope, category, handler),
//   voiceEventPayloads / downloadEventPayloads / componentLifecycleEventPayloads / modelRegistryEventPayloads,
//   llmEvents / sttEvents / ttsEvents / modelEvents / errorEvents / sdkEvents / ragEvents,
//   modelLifecycle / modelLoaded / modelUnloaded (EventBus+ModelLifecycle)
fun RunAnywhere.subscribeSDKEvents(handler: (SDKEvent) -> Unit): Long
fun RunAnywhere.unsubscribeSDKEvents(subscriptionId: Long)
fun RunAnywhere.publishSDKEvent(event: SDKEvent): Boolean
fun RunAnywhere.pollSDKEvent(): SDKEvent?
fun RunAnywhere.publishSDKFailure(errorCode: Int, message: String, component: String, operation: String, recoverable: Boolean = false): Boolean

// =====================================================================
// 16. MISC — logging / audio / solutions / plugin loader
// =====================================================================
fun RunAnywhere.configureLogging(config: LoggingConfiguration)
fun RunAnywhere.setLocalLoggingEnabled(enabled: Boolean)
fun RunAnywhere.setLogLevel(level: LogLevel)
fun RunAnywhere.addLogDestination(destination: LogDestination)
fun RunAnywhere.setDebugMode(enabled: Boolean)
fun RunAnywhere.flushLogs()
fun RunAnywhere.pcm16ToFloat32(int16Bytes: ByteArray): ByteArray
fun RunAnywhere.pcm16ToFloat32Samples(int16Bytes: ByteArray): FloatArray
fun RunAnywhere.pcm16ToWav(int16Bytes: ByteArray, sampleRate: Int): ByteArray
// val RunAnywhere.solutions: Solutions -> run(yaml) / run(configBytes) / run(config) -> SolutionHandle
// val RunAnywhere.pluginLoader: PluginLoaderNamespace -> apiVersion, registeredCount, load, unload, registeredNames, listLoaded
