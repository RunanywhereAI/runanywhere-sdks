/*
 * PUBLIC API SNAPSHOT — Flutter SDK (sdk/runanywhere-flutter/packages/runanywhere)
 * Audit reference only. NOT compilable. Compare against PublicApiSwift.swift (same 16 areas).
 * Entry: `abstract final class RunAnywhere` (lib/public/runanywhere.dart) + capability
 * objects (RunAnywhere.llm / .stt / .tts / .vad / .vlm / .rag / .lora / .voice / .models /
 * .downloads / .solutions / .pluginLoader) and extension classes.
 *
 * Markers:
 *   [MISSING]      Swift has the feature, Flutter has NO equivalent (real gap)
 *   [NO-FLAT]      behavior exists on a capability object, but Swift's flat RunAnywhere.* static is absent (namespacing gap, not missing behavior)
 *   [FLUTTER-ONLY] Flutter has it, Swift does not
 *   [DIVERGE]      same feature, different name/shape
 *
 * HEADLINE: the ONLY truly-absent feature vs Swift is the web-search tool (area 2).
 * Everything else is flat-alias namespacing or Dart naming conventions.
 */

// =====================================================================
// 1. INIT / LIFECYCLE  (static on RunAnywhere)
// =====================================================================
bool get isInitialized;
bool get isActive;
bool get areServicesReady;
bool get hasCompletedHTTPSetup;                 // [FLUTTER-ONLY]
String get deviceId;                            // [DIVERGE] Swift method deviceId(){throws}; Flutter throwing getter
String? get userId;                             // [DIVERGE] Swift getUserId()
String? get organizationId;                     // [DIVERGE] Swift getOrganizationId()
bool get isAuthenticated;
bool get isDeviceRegistered;                    // [DIVERGE] Swift isDeviceRegistered() method
void setHfToken(String? token);
SDKInitParams? get initParams;                  // [FLUTTER-ONLY]
SDKEnvironment? get environment;
String get version;
EventBus get events;
Future<void> initialize({String? apiKey, String? baseURL, SDKEnvironment environment});
Future<void> initializeWithParams(SDKInitParams params);   // [DIVERGE] Swift 2nd initialize overload
Future<void> completeServicesInitialization();
Future<void> reset();

// =====================================================================
// 2. LLM
// =====================================================================
Future<LLMGenerationResult> generate(String prompt, [LLMGenerationOptions? options]);
Future<LLMGenerationResult> generateRequest(LLMGenerateRequest request);            // [DIVERGE] Swift generate(request) overload
Stream<LLMStreamEvent> generateStream(String prompt, [LLMGenerationOptions? options]);
Stream<LLMStreamEvent> generateStreamRequest(LLMGenerateRequest request);           // [DIVERGE] Swift generateStream(request) overload
void cancelGeneration();
Future<LLMGenerationResult> aggregateStream({required String prompt, required Stream<LLMStreamEvent> events, Future<void> Function(String)? onToken});
// llm.chat(String)  // [FLUTTER-ONLY]

// --- Structured output ---
Future<StructuredOutputResult> generateStructured({required String prompt, required JSONSchema schema, LLMGenerationOptions? options});
Future<LLMGenerationResult> generateWithStructuredOutput({required String prompt, required StructuredOutputOptions structuredOutput, LLMGenerationOptions? options});
StructuredOutputResult extractStructuredOutput({required String text, required JSONSchema schema});
Stream<StructuredOutputStreamEvent> generateStructuredStream({required String prompt, required JSONSchema schema, LLMGenerationOptions? options});

// --- Tool calling (RunAnywhere.tools + flat) ---
void registerTool(ToolDefinition definition, ToolExecutor executor);
void unregisterTool(String name);
List<ToolDefinition> getRegisteredTools();
void clearTools();
Future<ToolResult> executeTool(ToolCall call);                                       // [DIVERGE] capability method is tools.execute()
Future<ToolCallingResult> generateWithTools(String prompt, {LLMGenerationOptions? llmOptions, ToolCallingOptions? options, ToolChoiceMode? toolChoice, String? forcedToolName, bool? validateCalls, List<String> history});

// --- Web search ---
// [MISSING] webSearchToolDefinition
// [MISSING] registerWebSearchTool()

// =====================================================================
// 3. STT
// =====================================================================
Future<STTOutput> transcribe(Uint8List audio, [STTOptions? options]);
Stream<STTPartialResult> transcribeStream(Stream<Uint8List> audio, {STTOptions? options});
// FLUTTER-ONLY: transcribeBuffer, processStreamingAudio, stopStreamingTranscription, isStreaming

// =====================================================================
// 4. TTS
// =====================================================================
Future<TTSOutput> synthesize(String text, [TTSOptions? options]);
Stream<TTSOutput> synthesizeStream(String text, {TTSOptions? options});              // [NO-FLAT] only via RunAnywhere.tts
Future<void> stopSynthesis();
Future<TTSSpeakResult> speak(String text, [TTSOptions? options]);
Future<void> stopSpeaking();                                                         // [NO-FLAT] only via RunAnywhere.tts
// FLUTTER-ONLY: isSpeaking, playbackStateStream, playbackProgressStream, availableVoices()

// =====================================================================
// 5. VAD  (RunAnywhere.vad only — no flat statics)
// =====================================================================
Future<VADResult> detectVoiceActivity(Uint8List audio, [VADOptions? options]);       // [NO-FLAT]
Stream<VADResult> streamVAD(Stream<Uint8List> audio);                                // [NO-FLAT]
void reset();                                                                        // [NO-FLAT][DIVERGE] Swift resetVAD()

// =====================================================================
// 6. VLM  (RunAnywhere.vlm / .visionLanguage — no flat statics)
// =====================================================================
Future<VLMResult> processImage(VLMImage image, {String? prompt, VLMGenerationOptions? options});      // [NO-FLAT]
Stream<VLMStreamEvent> processImageStream(VLMImage image, {String? prompt, VLMGenerationOptions? options}); // [NO-FLAT][DIVERGE] Swift 2 overloads collapsed into named {prompt,options}
Future<void> cancelVLMGeneration();                                                  // [NO-FLAT]

// =====================================================================
// 7. DIFFUSION  (Apple-only; fails closed off-Apple) — FULL PARITY
// =====================================================================
Future<DiffusionResult> generateImage(DiffusionGenerationOptions options);
Stream<DiffusionStreamEvent> generateImageStream(DiffusionGenerationOptions options);
Future<void> cancelImageGeneration();

// =====================================================================
// 8. EMBEDDINGS  (RunAnywhere.embeddings)
// =====================================================================
bool get isLoaded;
String? get currentModelId;                                                          // [DIVERGE] Swift currentModelID (casing)
Future<EmbeddingsResult> embed(String text, {required String modelId, EmbeddingsOptions? options}); // [DIVERGE] requires modelId + self-loads
Future<EmbeddingsResult> embedBatch(EmbeddingsRequest request, {required String modelId});           // [DIVERGE] Swift takes [String]
Future<void> unload();

// =====================================================================
// 9. RAG  — FULL PARITY (ragCancelQuery correctly absent, matching Swift)
// =====================================================================
Future<RAGConfiguration> ragResolvedConfiguration({required ModelInfo embeddingModel, required ModelInfo llmModel, RAGConfiguration? baseConfiguration});
Future<void> ragCreatePipeline(RAGConfiguration config);
Future<void> ragCreatePipelineForModels({required ModelInfo embeddingModel, required ModelInfo llmModel, RAGConfiguration? baseConfiguration}); // [DIVERGE] Swift ragCreatePipeline(embeddingModel:llmModel:) overload
Future<void> ragDestroyPipeline();
Future<RAGStatistics> ragIngest(RAGDocument document);
Future<void> ragAddDocumentsBatch(List<RAGDocument> documents);
Future<void> ragClearDocuments();
Future<int> ragGetDocumentCount();
Future<int> get ragDocumentCount;
Future<RAGStatistics> ragGetStatistics();
Future<RAGResult> ragQuery(RAGQueryOptions options);
Stream<RAGStreamEvent> ragQueryStream(RAGQueryOptions options);
// FLUTTER-ONLY ergonomic aliases: query(question), queryStream(question), createPipeline, destroyPipeline, documentCount, getStatistics, clearDocuments

// =====================================================================
// 10. LoRA  (RunAnywhere.lora)  — FULL PARITY
// =====================================================================
Future<LoRAApplyResult> apply(LoRAApplyRequest request);
Future<LoRAApplyResult> applyCatalogAdapter(LoraAdapterCatalogEntry entry, {String? localPath, double? scale, bool replaceExisting});
Future<LoRAState> remove(LoRARemoveRequest request);
Future<LoRAState> list();
Future<LoRAState> state();
Future<LoraCompatibilityResult> checkCompatibility(LoRAAdapterConfig config);
Future<LoraAdapterCatalogEntry> register(LoraAdapterCatalogEntry entry);
Future<ModelInfo> registerArtifact(LoraAdapterCatalogEntry entry);
Future<String> download(LoraAdapterCatalogEntry entry, {void Function(double)? onProgress});
Future<LoraAdapterCatalogListResult> listCatalog([LoraAdapterCatalogListRequest? request]);
Future<LoraAdapterCatalogListResult> queryCatalog(LoraAdapterCatalogQuery query);
Future<LoraAdapterCatalogGetResult> getCatalogEntry(LoraAdapterCatalogGetRequest request);
Future<LoraAdapterDownloadCompletedResult> markDownloadCompleted(LoraAdapterDownloadCompletedRequest request);
Future<LoraAdapterDownloadCompletedResult> markImportCompleted(LoraAdapterDownloadCompletedRequest request);
Future<LoraAdapterImportResult> importAdapter(String sourcePath);
Future<List<LoraAdapterCatalogEntry>> adaptersForModel(String modelId);
Future<List<LoraAdapterCatalogEntry>> allRegistered();

// =====================================================================
// 11. VOICE AGENT  (RunAnywhere.voice)
// =====================================================================
String get defaultVADModelID;
Future<bool> ensureDefaultVAD({String? modelID});                                   // [NO-FLAT]
Future<void> initializeVoiceAgent(VoiceAgentComposeConfig config);                  // [NO-FLAT]
Future<VoiceAgentComponentStates> componentStates();                               // [NO-FLAT][DIVERGE] Swift getVoiceAgentComponentStates()
Future<void> initializeWithLoadedModels({String? ttsVoiceID, bool ensureVAD});      // [DIVERGE] Swift initializeVoiceAgentWithLoadedModels
void cleanup();                                                                      // [DIVERGE] Swift cleanupVoiceAgent()
Future<VoiceAgentResult> processVoiceTurn(Uint8List audioData);                     // [NO-FLAT]
Stream<VoiceEvent> eventStream();                                                    // [DIVERGE] flat RunAnywhere.streamVoiceAgent() exists
// FLUTTER-ONLY: isReady, isAgentReady

// =====================================================================
// 12. MODELS — LIFECYCLE  — FULL PARITY (flat statics)
// =====================================================================
Future<ModelLoadResult> loadModel(ModelLoadRequest request);
Future<ModelUnloadResult> unloadModel(ModelUnloadRequest request);
Future<CurrentModelResult> currentModel([CurrentModelRequest? request]);
Future<ModelInfo?> modelInfoForCategory(ModelCategory category);
ComponentLifecycleSnapshot? componentLifecycleSnapshot(SDKComponent component);

// =====================================================================
// 13. MODELS — REGISTRY  (RunAnywhere.models)
// =====================================================================
Future<ModelListResult> list({ModelQuery? query});                                  // [DIVERGE] Swift listModels; [NO-FLAT] RunAnywhere.listModels
Future<ModelListResult> queryModels(ModelQuery query);
Future<ModelGetResult> getModel(ModelGetRequest request);
Future<ModelListResult> downloadedModels();
Future<void> refreshModelRegistry({bool rescanLocal, bool includeRemoteCatalog, bool pruneOrphans}); // flat alias exists
ModelFileRole inferModelFileRole({required String filename, required ModelCategory modality});
// FLUTTER-ONLY: available(), listDownloaded(), register/registerArchiveModel/registerMultiFile (on models), updateDownloadStatus, remove, currentLoadedId, resolveModelFilePath

// =====================================================================
// 14. DOWNLOAD
// =====================================================================
Future<DownloadProgress> downloadModel(String modelId, {Future<void> Function(DownloadProgress)? onProgress});
Stream<DownloadProgress> start(String modelId);                                     // [DIVERGE] Swift downloadModelStream; [NO-FLAT]
// FLUTTER-ONLY: plan, startDownload, cancelDownload, cancel, resume, pollProgress, deleteAllModels, list()

// =====================================================================
// 15. STORAGE  — FULL PARITY (register split into 3 named methods)
// =====================================================================
Future<ModelInfo> registerModel({String? id, required String name, required String url, required InferenceFramework framework, ModelCategory modality, ModelArtifactType? artifactType, int? memoryRequirement, bool supportsThinking, bool supportsLora});
Future<ModelInfo> registerArchiveModel({required String archiveUrl, required ArchiveStructure structure, /* ... */});  // [DIVERGE] Swift registerModel(archive:) overload
Future<ModelInfo> registerMultiFileModel({required List<ModelFileDescriptor> files, required String id, required String name, /* ... */}); // [DIVERGE] Swift registerModel(multiFile:) overload
Future<ModelImportResult> importModel(ModelImportRequest request);
Future<StorageInfo> getStorageInfo();                                                // [DIVERGE] on RunAnywhere.downloads
Future<StorageDeleteResult> deleteStorage(StorageDeleteRequest request);
Future<StorageDeleteResult> deleteModel(String modelId);
Future<void> clearCache();                                                           // on RunAnywhere.downloads
Future<void> cleanTempFiles();

// =====================================================================
// 16. EVENTS + MISC  — FULL PARITY (different host classes)
// =====================================================================
// EventBus (RunAnywhere.events): initializationEvents/generationEvents/modelEvents/ragEvents/
//   llmEvents/sttEvents/ttsEvents/errorEvents/sdkEvents/allEvents, voiceEventPayloads/
//   downloadEventPayloads/componentLifecycleEventPayloads/modelRegistryEventPayloads,
//   modelLifecycle/modelLoaded/modelUnloaded, onCategory, publish
StreamSubscription<SDKEvent> subscribeSDKEvents(void Function(SDKEvent) handler);   // [DIVERGE] returns StreamSubscription (Swift returns UInt64 token)
Future<void> unsubscribeSDKEvents(StreamSubscription<SDKEvent> sub);
Future<bool> publishSDKEvent(SDKEvent event);
Future<SDKEvent?> pollSDKEvent();
Future<bool> publishSDKFailure({required int errorCode, required String message, required String component, required String operation, bool recoverable});
// Logging on class RunAnywhereLogging: configureLogging/setLocalLoggingEnabled/setLogLevel/addLogDestination/setDebugMode/flushLogs (+ removeLogDestination FLUTTER-ONLY)  [DIVERGE host class]
// Audio on class RunAnywhereAudioConvert: pcm16ToFloat32/pcm16ToFloat32Samples/pcm16ToWav  [DIVERGE host class]
// Solutions (RunAnywhere.solutions): run({config, configBytes, yaml}) -> SolutionHandle (start/stop/cancel/closeInput/feed/destroy/isAlive)
// PluginLoader (RunAnywhere.pluginLoader): apiVersion/registeredCount/registeredNames/listLoaded/load/unload

// =====================================================================
// EXTRAS beyond the 16 areas (Flutter-only, not in Swift baseline)
// =====================================================================
// - RunAnywhere.hybrid (HybridSttRouter, CloudBackend, HybridRoutingPolicy) — mirrors Swift HybridSTTRouter (not enumerated)
// - Backend packages: LlamaCpp / Onnx / QHexRT register()/unregister()/isAvailable/autoRegister/dispose

// =====================================================================
// CONSOLIDATED
// =====================================================================
// TRULY MISSING (real feature gaps): webSearchToolDefinition, registerWebSearchTool  (2)
// NO-FLAT (behavior present on capability object, flat RunAnywhere.* static absent):
//   VAD (3), VLM (3), tts.synthesizeStream/stopSpeaking, models.list(listModels),
//   downloads.start(downloadModelStream), voice.* — cosmetic surface parity only
// FLUTTER-ONLY: many convenience methods (chat, per-capability isLoaded/load/unload,
//   RAG ergonomic aliases, download plan/cancel/resume, hybrid STT router)
