/*
 * PUBLIC API SNAPSHOT — iOS/macOS Swift SDK (sdk/runanywhere-swift)
 * Audit reference only. NOT compilable. Signatures mirror the real facade.
 * Compare 1:1 with PublicApiKotlin.kt (same feature order).
 * Facade type is `public enum RunAnywhere`; members live in `public extension` blocks.
 *
 * Markers:
 *   [DIVERGE]  signature/shape differs from Kotlin
 *   [SWIFT-ONLY] exists in Swift, absent from Kotlin
 *   [KT-ONLY]  Kotlin has it, Swift does not (see the Kotlin file)
 */

// =====================================================================
// 1. INIT / LIFECYCLE  —  enum RunAnywhere (Public/RunAnywhere.swift)
// =====================================================================
static var isInitialized: Bool
static var areServicesReady: Bool
static var isActive: Bool
static var version: String
static var environment: SDKEnvironment?
static var events: EventBus
static var isAuthenticated: Bool
static var deviceId: String { get throws }                 // [DIVERGE] Kotlin: non-throwing `val deviceId: String`
static func getUserId() -> String?
static func getOrganizationId() -> String?
static func isDeviceRegistered() -> Bool
static func setHfToken(_ token: String?)
static func initialize(apiKey: String? = nil, baseURL: String? = nil, environment: SDKEnvironment = .development) throws
static func initialize(apiKey: String, baseURL: URL, environment: SDKEnvironment = .production) throws
// [KT-ONLY] initialize(context:...) overloads — Android needs a Context; no Swift equivalent (expected)
static func completeServicesInitialization() async throws
static func reset() async

// =====================================================================
// 2. LLM
// =====================================================================
static func generate(prompt: String, options: RALLMGenerationOptions? = nil) async throws -> RALLMGenerationResult
static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult
static func generateStream(prompt: String, options: RALLMGenerationOptions? = nil) async throws -> AsyncStream<RALLMStreamEvent>
static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent>
static func cancelGeneration() async
static func aggregateStream(prompt: String, events: AsyncStream<RALLMStreamEvent>, onThinking: ((String) async -> Void)? = nil, onToken: ((String) async -> Void)? = nil) async -> RALLMGenerationResult
static var webSearchToolDefinition: RAToolDefinition       // [SWIFT-ONLY]
static func registerWebSearchTool() async                  // [SWIFT-ONLY]

// --- LLM: Structured Output ---
static func generateStructured(prompt: String, schema: RAJSONSchema, options: RALLMGenerationOptions? = nil) async throws -> RAStructuredOutputResult
static func generateWithStructuredOutput(prompt: String, structuredOutput: RAStructuredOutputOptions, options: RALLMGenerationOptions? = nil) async throws -> RALLMGenerationResult
static func extractStructuredOutput(text: String, schema: RAJSONSchema) throws -> RAStructuredOutputResult   // [DIVERGE] sync throws (Kotlin: suspend)
static func generateStructuredStream(prompt: String, schema: RAJSONSchema, options: RALLMGenerationOptions? = nil) throws -> AsyncThrowingStream<RAStructuredOutputStreamEvent, Error>

// --- LLM: Tool Calling ---
static func registerTool(_ definition: RAToolDefinition, executor: @escaping ToolExecutor) async
static func unregisterTool(_ toolName: String) async
static func getRegisteredTools() async -> [RAToolDefinition]
static func clearTools() async
static func executeTool(_ toolCall: RAToolCall) async -> RAToolResult
static func generateWithTools(prompt: String, options: RALLMGenerationOptions = .defaults(), toolOptions: RAToolCallingOptions? = nil, toolChoice: RAToolChoiceMode? = nil, forcedToolName: String? = nil, validateCalls: Bool? = nil, history: [String] = []) async throws -> RAToolCallingResult

// =====================================================================
// 3. STT
// =====================================================================
static func transcribe(audio audioData: Data, options: RASTTOptions = .defaults()) async throws -> RASTTOutput
static func transcribeStream(audio: AsyncStream<Data>, options: RASTTOptions = .defaults()) -> AsyncStream<RASTTPartialResult>

// =====================================================================
// 4. TTS
// =====================================================================
static func synthesize(_ text: String, options: RATTSOptions = .defaults()) async throws -> RATTSOutput
static func synthesizeStream(_ text: String, options: RATTSOptions = .defaults()) -> AsyncStream<RATTSOutput>
static func stopSynthesis() async
static func speak(_ text: String, options: RATTSOptions = .defaults()) async throws -> RATTSSpeakResult
static func stopSpeaking() async

// =====================================================================
// 5. VAD
// =====================================================================
static func detectVoiceActivity(_ audioData: Data, options: RAVADOptions? = nil) async throws -> RAVADResult
static func streamVAD(audio: AsyncStream<Data>, options: RAVADOptions? = nil) -> AsyncStream<RAVADResult>
static func resetVAD() async throws

// =====================================================================
// 6. VLM
// =====================================================================
static func processImage(_ image: RAVLMImage, options: RAVLMGenerationOptions) async throws -> RAVLMResult
static func processImageStream(_ image: RAVLMImage, options: RAVLMGenerationOptions) async throws -> AsyncStream<RAVLMStreamEvent>
static func processImageStream(_ image: RAVLMImage, prompt: String, options: RAVLMGenerationOptions = .defaults()) async throws -> AsyncStream<RAVLMStreamEvent> // [SWIFT-ONLY]
static func cancelVLMGeneration() async

// =====================================================================
// 7. DIFFUSION
// =====================================================================
static func generateImage(_ options: RADiffusionGenerationOptions) async throws -> RADiffusionResult          // [DIVERGE] Kotlin adds modelId param
static func generateImageStream(_ options: RADiffusionGenerationOptions) async throws -> AsyncStream<RADiffusionStreamEvent> // [SWIFT-ONLY]
static func cancelImageGeneration() async                                                                     // [SWIFT-ONLY]
// [KT-ONLY] inpaint(inputImage:maskImage:prompt:width:height:modelId:) — no Swift facade method

// =====================================================================
// 8. EMBEDDINGS  (static var embeddings: Embeddings)
// =====================================================================
var isLoaded: Bool
var currentModelID: String?
func embed(_ text: String, modelID: String, options: RAEmbeddingsOptions? = nil) async throws -> RAEmbeddingsResult
func embedBatch(_ request: RAEmbeddingsRequest, modelID: String) async throws -> RAEmbeddingsResult
func unload() async throws

// =====================================================================
// 9. RAG
// =====================================================================
static func ragResolvedConfiguration(embeddingModel: RAModelInfo, llmModel: RAModelInfo, baseConfiguration: RARAGConfiguration = .defaults()) async throws -> RARAGConfiguration
static func ragCreatePipeline(embeddingModel: RAModelInfo, llmModel: RAModelInfo, baseConfiguration: RARAGConfiguration = .defaults()) async throws
static func ragCreatePipeline(config: RARAGConfiguration) async throws
static func ragDestroyPipeline() async
static func ragIngest(_ document: RARAGDocument) async throws -> RARAGStatistics
static func ragClearDocuments() async throws
static func ragGetDocumentCount() async -> Int
static var ragDocumentCount: Int { get async }                         // [DIVERGE] Kotlin: suspend fun ragDocumentCount()
static func ragQuery(question: String, options: RARAGQueryOptions? = nil) async throws -> RARAGResult
static func ragQuery(_ options: RARAGQueryOptions) async throws -> RARAGResult
static func ragQueryStream(question: String, options: RARAGQueryOptions? = nil) async throws -> AsyncStream<RARAGStreamEvent>
static func ragQueryStream(_ options: RARAGQueryOptions) async throws -> AsyncStream<RARAGStreamEvent>
// [KT-ONLY] ragCancelQuery() — Swift cancels via stream backpressure (break the AsyncStream)
static func ragAddDocumentsBatch(documents: [RARAGDocument]) async throws
static func ragGetStatistics() async throws -> RARAGStatistics

// =====================================================================
// 10. LoRA  (static var lora: LoRA)
// =====================================================================
func apply(_ request: RALoRAApplyRequest) async throws -> RALoRAApplyResult
func apply(_ entry: RALoraAdapterCatalogEntry, localPath: String? = nil, scale: Float? = nil, replaceExisting: Bool = false) async throws -> RALoRAApplyResult
func applyCatalogAdapter(_ entry: RALoraAdapterCatalogEntry, localPath: String? = nil, scale: Float? = nil, replaceExisting: Bool = false) async throws -> RALoRAApplyResult // [SWIFT-ONLY]
func remove(_ request: RALoRARemoveRequest) async throws -> RALoRAState
func list() async throws -> RALoRAState
func state() async throws -> RALoRAState
func checkCompatibility(_ config: RALoRAAdapterConfig) async -> RALoraCompatibilityResult
func register(_ entry: RALoraAdapterCatalogEntry) async throws -> RALoraAdapterCatalogEntry
func registerArtifact(_ entry: RALoraAdapterCatalogEntry) async throws -> RAModelInfo
func download(_ entry: RALoraAdapterCatalogEntry, onProgress: ((RADownloadProgress) async -> Void)? = nil) async throws -> String
func listCatalog(_ request: RALoraAdapterCatalogListRequest = RALoraAdapterCatalogListRequest()) async throws -> RALoraAdapterCatalogListResult
func queryCatalog(_ query: RALoraAdapterCatalogQuery) async throws -> RALoraAdapterCatalogListResult
func getCatalogEntry(_ request: RALoraAdapterCatalogGetRequest) async throws -> RALoraAdapterCatalogGetResult
func markDownloadCompleted(_ request: RALoraAdapterDownloadCompletedRequest) async throws -> RALoraAdapterDownloadCompletedResult
func importAdapter(from url: URL) async throws -> RALoraAdapterImportResult   // [DIVERGE] Kotlin takes sourcePath: String
func markImportCompleted(_ request: RALoraAdapterDownloadCompletedRequest) async throws -> RALoraAdapterDownloadCompletedResult
func adaptersForModel(_ modelId: String) async throws -> [RALoraAdapterCatalogEntry]
func allRegistered() async throws -> [RALoraAdapterCatalogEntry]

// =====================================================================
// 11. VOICE AGENT
// =====================================================================
static var defaultVADModelID: String
static func ensureDefaultVAD(modelID: String? = nil) async -> Bool
static func initializeVoiceAgent(_ config: RAVoiceAgentComposeConfig) async throws
static func getVoiceAgentComponentStates() async throws -> RAVoiceAgentComponentStates
static func initializeVoiceAgentWithLoadedModels(ttsVoiceID: String? = nil, ensureVAD: Bool = true) async throws
static func cleanupVoiceAgent() async
static func processVoiceTurn(_ audioData: Data) async throws -> RAVoiceAgentResult
static func streamVoiceAgent() -> AsyncStream<RAVoiceEvent>

// =====================================================================
// 12. MODELS — LIFECYCLE
// =====================================================================
static func loadModel(_ request: RAModelLoadRequest) async -> RAModelLoadResult               // [DIVERGE] async NON-throwing
// [KT-ONLY] loadModel(model: RAModelInfo) convenience overload
static func unloadModel(_ request: RAModelUnloadRequest) async -> RAModelUnloadResult
static func currentModel(_ request: RACurrentModelRequest = RACurrentModelRequest()) -> RACurrentModelResult // [DIVERGE] SYNC, single overload (Kotlin: suspend + 3 overloads)
static func modelInfoForCategory(_ category: RAModelCategory) -> RAModelInfo?                  // [DIVERGE] sync (Kotlin: suspend)
static func componentLifecycleSnapshot(_ component: RASDKComponent) -> RAComponentLifecycleSnapshot?

// =====================================================================
// 12b. MODELS — REGISTRY
// =====================================================================
static func listModels(_ request: RAModelListRequest = RAModelListRequest()) async -> RAModelListResult
static func queryModels(_ query: RAModelQuery) async -> RAModelListResult
static func getModel(_ request: RAModelGetRequest) async -> RAModelGetResult
static func downloadedModels() async -> RAModelListResult
static func refreshModelRegistry(rescanLocal: Bool = true, includeRemoteCatalog: Bool = false, pruneOrphans: Bool = false) async
static func inferModelFileRole(filename: String, modality: ModelCategory) -> RAModelFileRole

// =====================================================================
// 13. DOWNLOAD
// =====================================================================
static func downloadModel(_ model: RAModelInfo, onProgress: ((RADownloadProgress) async -> Void)? = nil) async throws -> RADownloadProgress
static func downloadModelStream(_ model: RAModelInfo) -> AsyncThrowingStream<RADownloadProgress, Error>

// =====================================================================
// 14. STORAGE
// =====================================================================
static func registerModel(id: String? = nil, name: String, url: String, framework: InferenceFramework, modality: ModelCategory = .language, artifactType: RAModelArtifactType? = nil, memoryRequirement: Int64? = nil, supportsThinking: Bool = false, supportsLora: Bool = false) async throws -> RAModelInfo
static func registerModel(archive url: String, structure: RAArchiveStructure, id: String? = nil, name: String, framework: InferenceFramework, modality: ModelCategory = .language, archiveType: RAArchiveType? = nil, memoryRequirement: Int64? = nil, supportsThinking: Bool = false, supportsLora: Bool = false) async throws -> RAModelInfo
static func registerModel(multiFile descriptors: [RAModelFileDescriptor], id: String, name: String, framework: InferenceFramework, modality: ModelCategory = .language, memoryRequirement: Int64? = nil, contextLength: Int? = nil, supportsThinking: Bool = false, source: RAModelSource = .remote) async throws -> RAModelInfo
static func importModel(_ request: RAModelImportRequest) async throws -> RAModelImportResult
static func getStorageInfo(_ request: RAStorageInfoRequest = RAStorageInfoRequest()) async -> RAStorageInfoResult
static func deleteStorage(_ request: RAStorageDeleteRequest) async -> RAStorageDeleteResult
static func deleteModel(_ modelId: String) async -> RAStorageDeleteResult
static func clearCache() async throws
static func cleanTempFiles() async throws

// =====================================================================
// 15. EVENTS
// =====================================================================
// final class EventBus : events (AnyPublisher), start(), stop(), publish(_),
//   events(for category), on(_ handler), on(_ category:handler:),
//   voiceEventPayloads / downloadEventPayloads / componentLifecycleEventPayloads / modelRegistryEventPayloads,
//   llmEvents / sttEvents / ttsEvents / modelEvents / errorEvents / sdkEvents / ragEvents,
//   modelLifecycle / modelLoaded / modelUnloaded (EventBus+ModelLifecycle)
static func subscribeSDKEvents(_ handler: @escaping @Sendable (RASDKEvent) -> Void) -> UInt64
static func unsubscribeSDKEvents(_ subscriptionId: UInt64)
static func publishSDKEvent(_ event: RASDKEvent) -> Bool
static func pollSDKEvent() -> RASDKEvent?
static func publishSDKFailure(errorCode: rac_result_t, message: String, component: String, operation: String, recoverable: Bool = false) -> Bool

// =====================================================================
// 16. MISC — logging / audio / solutions / plugin loader
// =====================================================================
static func configureLogging(_ config: RALoggingConfiguration)
static func setLocalLoggingEnabled(_ enabled: Bool)
static func setLogLevel(_ level: RALogLevel)
static func addLogDestination(_ destination: LogDestination)
static func setDebugMode(_ enabled: Bool)
static func flushLogs()
static func pcm16ToFloat32(_ int16Data: Data) -> Data
static func pcm16ToFloat32Samples(_ int16Data: Data) -> [Float]
static func pcm16ToWav(_ int16Data: Data, sampleRate: Int) -> Data
// static var solutions: Solutions -> run(configBytes:) / run(config:) / run(yaml:) -> SolutionHandle
// static var pluginLoader: PluginLoaderNamespace -> apiVersion, load, unload, registeredCount, registeredNames, listLoaded
