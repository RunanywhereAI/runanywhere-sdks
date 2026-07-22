/**
 * RunAnywhere Web SDK public facade.
 *
 * The root package intentionally mirrors the Swift SDK shape: app code talks
 * to `RunAnywhere` and public proto-derived types. Backend/runtime/browser
 * plumbing lives under `@runanywhere/web/backend`,
 * `@runanywhere/web/internal`, or `@runanywhere/web/browser`.
 */

export { RunAnywhere } from './Public/RunAnywhere.js';
export type { StorageBackend } from './Public/RunAnywhere.js';
export {
  Diffusion,
  generateImage,
  generateImageStream,
  cancelImageGeneration,
} from './Public/Extensions/RunAnywhere+Diffusion.js';
export type {
  DiffusionAvailability,
} from './Public/Extensions/RunAnywhere+Diffusion.js';

export type {
  JSONSchemaDescriptor,
  StructuredOutputResult,
  StructuredOutputStreamEvent,
  TextGenerationOptions,
} from './Public/Extensions/RunAnywhere+TextGeneration.js';
export type { ToolCallingGenerationOptions } from './Public/Extensions/RunAnywhere+ToolCalling.js';
export type {
  STTOptions,
  STTOutput,
  STTPartialResult,
  TranscribeOptions,
} from './Public/Extensions/RunAnywhere+STT.js';
export type {
  SynthesizeOptions,
  TTSOptions,
  TTSOutput,
  TTSVoiceInfo,
} from './Public/Extensions/RunAnywhere+TTS.js';
export type {
  DetectVoiceOptions,
  SpeechActivityEvent,
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
} from './Public/Extensions/RunAnywhere+VAD.js';
export type {
  VisionLanguageProvider,
} from './Public/Extensions/RunAnywhere+VisionLanguage.js';
// Hybrid STT router (cross-SDK parity with Kotlin RACRouter / Swift
// HybridSTTRouter). Per-request offline(sherpa)↔online(cloud) dispatch;
// commons owns all routing. Public API surfaces via `RunAnywhere.hybrid.*`.
export { HybridSttRouter } from './Public/Extensions/Hybrid/HybridSttRouter.js';
export { Cloud, cloud } from './Public/Extensions/Hybrid/Cloud.js';
export type {
  CloudModelEntry,
  CloudSTTConfig,
} from './Public/Extensions/Hybrid/Cloud.js';
export {
  HybridBackendKind,
  HybridModelType,
  HybridRank,
  DEFAULT_CLOUD_PROVIDER,
  HYBRID_STT_CONFIDENCE_THRESHOLD,
  networkFilter,
  batteryFilter,
  customFilter,
  confidenceCascade,
  offlineSherpa,
  onlineCloud,
} from './Public/Extensions/Hybrid/HybridTypes.js';
export type {
  HybridFilterSpec,
  HybridCascadeSpec,
  HybridRoutingPolicySpec,
  HybridModelSpec,
  HybridTranscribeOptions,
  HybridTranscribeResult,
  HybridRoutedMetadata,
} from './Public/Extensions/Hybrid/HybridTypes.js';
// Custom-filter registrars are internal-only — Swift parity:
// HybridCustomFilter.swift:31 (filters are supplied via the policy's
// `customFilter(...)` spec, never registered directly by apps).
export {
  setHybridDeviceStateProvider,
  browserDeviceStateProvider,
} from './Public/Extensions/Hybrid/HybridDeviceState.js';
export type { HybridDeviceStateProvider } from './Public/Extensions/Hybrid/HybridDeviceState.js';
export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader.js';
export type {
  RAGAvailability,
  RAGDocumentSummary,
  RAGEnsureReadyOptions,
  RAGPipelineState,
  RAGProvider,
  RAGProviderCapabilities,
} from './Public/Extensions/RunAnywhere+RAG.js';
export {
  createPersistentRAGProvider,
  registerPersistentRAGProvider,
} from './Public/Extensions/RunAnywhere+RAG.js';
export { Hardware } from './Public/Extensions/RunAnywhere+Hardware.js';
export type { WebCapabilities } from './Public/Extensions/RunAnywhere+Hardware.js';
export {
  getStoredHfToken,
  setHfToken,
} from './Public/Extensions/RunAnywhere+HuggingFace.js';
export { registerDuckDuckGoSearchTool } from './Public/Helpers/registerDuckDuckGoSearchTool.js';
export type {
  EmbeddingsOptions,
  EmbeddingsRequest,
  EmbeddingsResult,
} from './Public/Extensions/RunAnywhere+Embeddings.js';
export {
  SegmentationPixelFormat,
} from './Public/Extensions/RunAnywhere+Segmentation.js';
export type {
  SegmentationClassSummary,
  SegmentationImage,
  SegmentationOptions,
  SegmentationRequest,
  SegmentationResult,
} from './Public/Extensions/RunAnywhere+Segmentation.js';
export type {
  RegisterModelFile,
  RegisterModelOptions,
  RegisterMultiFileOptions,
} from './Public/Extensions/RunAnywhere+Storage.js';
export { LogLevel } from './Public/Extensions/RunAnywhere+Logging.js';
export type { LoggingConfiguration, LogDestination } from './Public/Extensions/RunAnywhere+Logging.js';
// Hardware profile types are proto-generated; import them directly from
// `@runanywhere/proto-ts/hardware_profile` if needed.
export type {
  HardwareProfile,
  HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';

// T6.1 — Worker streaming path. Backend packages
// (`@runanywhere/web-llamacpp`, `@runanywhere/web-onnx`) call
// `setStreamWorkerFactory(fn)` during their `register()`; consumers can
// override `Runtime.streamingMode` to force `'auto' | 'worker' | 'main'`.
// When unregistered, all adapter `*Stream` methods transparently use the
// main-thread `queueMicrotask` path (the T3.1 MVP).
export { setStreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry.js';
export type { StreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry.js';

// SDK metadata constants — mirror Swift `SDKConstants.version/name/platform`.
export { SDK_NAME, SDK_PLATFORM, SDK_VERSION } from './Foundation/Version.js';

// For error codes use ProtoErrorCode from '@runanywhere/proto-ts/errors' (re-exported below).
export { SDKException, isSDKException } from './Foundation/SDKException.js';
export type { ProtoErrorContext, ProtoSDKError } from './Foundation/SDKException.js';
export {
  ProtoErrorCategory,
  ProtoErrorCode,
  ProtoErrorSeverity,
} from './Foundation/SDKException.js';

export {
  AudioEncoding,
  InterruptReason,
  PipelineState as VoiceEventPipelineState,
  TokenKind,
  VoiceEvent,
  type AssistantTokenEvent,
  type AudioFrameEvent,
  type ErrorEvent,
  type InterruptedEvent,
  type MetricsEvent,
  type StateChangeEvent,
  type UserSaidEvent,
  type VADEvent,
} from '@runanywhere/proto-ts/voice_events';
export { VADStreamEventKind } from '@runanywhere/proto-ts/vad_options';

export * from './types/index.js';

// Helpers — pure-JS proxies for commons utilities.
export { formatFramework } from './Public/Helpers/formatFramework.js';

// Tool calling — Swift-parity two-channel options for generateWithTools.
export type { GenerateWithToolsOptions } from './Public/Extensions/RunAnywhere+ToolCalling.js';

// Cloud STT provider table — developer-defined providers by name (mirrors
// Swift Cloud.registerProvider / Cloud.unregisterProvider).
export {
  CloudAudioFormat,
  registerCloudSttProvider,
  unregisterCloudSttProvider,
} from './Public/Extensions/Hybrid/CloudSttProvider.js';
export type {
  CloudSttRequest,
  CloudSttResult,
  SttProviderHandler,
} from './Public/Extensions/Hybrid/CloudSttProvider.js';

// Audio conversion helpers — mirrors Swift RAAudioConvert.swift
// (`RunAnywhere.pcm16ToFloat32` / `pcm16ToFloat32Samples` / `pcm16ToWav`).
export {
  pcm16ToFloat32,
  pcm16ToFloat32Samples,
  pcm16ToWav,
} from './Public/Extensions/RunAnywhere+AudioConvert.js';

// SDKEnvironment helpers — mirrors Swift SDKEnvironment.swift:28-128.
export {
  environmentDeployableCases,
  environmentDescription,
  environmentIsProduction,
  environmentIsTesting,
  environmentRequiresBackendURL,
  environmentDefaultLogLevel,
  environmentShouldSendTelemetry,
  environmentShouldSyncWithBackend,
  environmentRequiresAuthentication,
} from './Foundation/SDKEnvironment+Helpers.js';

// Storage proto helpers — mirrors Swift StorageProto+Helpers.swift.
export * from './types/StorageProto+Helpers.js';

// Model-lifecycle event streams — mirrors Swift EventBus+ModelLifecycle.swift.
export {
  modelLifecycle,
  modelLoaded,
  modelUnloaded,
  modelLifecycleChange,
  type ModelLifecycleChange,
} from './Foundation/EventBus+ModelLifecycle.js';

// Model-type helpers + artifacts — mirrors Swift ModelTypes.swift /
// ModelTypes+Artifacts.swift (commons-ABI-backed; no hand-written tables).
export {
  categoryRequiresContextLength,
  categorySupportsThinking,
  modelFormatWireString,
  modelFormatFromWireString,
  inferenceFrameworkWireString,
  inferenceFrameworkFromWireString,
  modelInfoMake,
  modelInfoArtifact,
  artifactCaseType,
  artifactTypeRequiresExtraction,
  artifactTypeRequiresDownload,
  artifactTypeDisplayName,
  modelInfoIsBuiltIn,
  modelInfoIsDownloadedOnDisk,
  modelInfoIsAvailableForUse,
  modelInfoRequiresExtraction,
  modelInfoRequiresDownload,
  modelInfoArtifactDisplayName,
  modelInfoArchiveArtifact,
  modelInfoMultiFileDescriptors,
  modelInfoExpectedArtifactFiles,
  modelInfoSettingDownloadUrl,
  modelInfoSettingLocalPath,
  modelInfoSettingArtifact,
  expectedModelFilesNone,
  isEmptyExpectedFilesManifest,
  makeModelFileDescriptor,
  modelFileDescriptorDestinationFilename,
  modelFileDescriptorResolvedLocalPath,
  resolvedModelFilePath,
  resolvedPrimaryModelPath,
  resolvedVisionProjectorPath,
  resolvedTokenizerPath,
  resolvedConfigPath,
  resolvedVocabularyPath,
  lifecyclePrimaryArtifactPath,
} from './types/ModelTypes+Artifacts.js';
export type { ModelInfoArtifact, ModelInfoMakeParams } from './types/ModelTypes+Artifacts.js';

// Embeddings helpers — mirrors Swift Embeddings *+Helpers.swift.
export {
  embeddingCosineSimilarity,
  embeddingComputeNorm,
  embeddingsResultProcessingTime,
} from './Public/Extensions/RunAnywhere+Embeddings.js';
export type { EmbeddingVector } from './Public/Extensions/RunAnywhere+Embeddings.js';

// RAG proto helpers — mirrors Swift RAGProto+Helpers.swift.
export {
  ragQueryOptionsWithQuestion,
  ragResultTotalTime,
  ragStatisticsLastUpdated,
} from './Public/Extensions/RunAnywhere+RAG.js';

// Structured-output proto helpers — mirrors Swift StructuredOutputProto+Helpers.swift.
export {
  jsonSchemaString,
  structuredOutputOptionsWithSchema,
  structuredOutputResultSuccess,
  namedEntityLength,
} from './Public/Extensions/RunAnywhere+StructuredOutput.js';
export type { JSONSchema, NamedEntity } from './Public/Extensions/RunAnywhere+StructuredOutput.js';

// VLM image factories — mirrors Swift RAVLMImage+Helpers.swift (cross-platform set).
export {
  vlmImageFromEncoded,
  vlmImageFromFilePath,
  vlmImageFromBase64,
  vlmImageFromRawRGB,
  vlmImageFromRawRGBA,
} from './Public/Extensions/RAVLMImage+Helpers.js';
