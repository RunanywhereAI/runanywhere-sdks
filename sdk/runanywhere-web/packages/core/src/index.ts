/**
 * RunAnywhere Web SDK public facade.
 *
 * The root package intentionally mirrors the Swift SDK shape: app code talks
 * to `RunAnywhere` and public proto-derived types. Backend/runtime/browser
 * plumbing lives under `@runanywhere/web/internal` or `@runanywhere/web/browser`.
 */

export { RunAnywhere } from './Public/RunAnywhere';
export type { StorageBackend } from './Public/RunAnywhere';

export type {
  JSONSchemaDescriptor,
  StructuredOutputResult,
  TextGenerationOptions,
} from './Public/Extensions/RunAnywhere+TextGeneration';
export type { ToolCallingGenerationOptions } from './Public/Extensions/RunAnywhere+ToolCalling';
export type {
  STTOptions,
  STTOutput,
  STTPartialResult,
  TranscribeOptions,
} from './Public/Extensions/RunAnywhere+STT';
export type {
  SynthesizeOptions,
  TTSOptions,
  TTSOutput,
  TTSVoiceInfo,
} from './Public/Extensions/RunAnywhere+TTS';
export type {
  DetectVoiceOptions,
  SpeechActivityEvent,
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
} from './Public/Extensions/RunAnywhere+VAD';
export type {
  VisionLanguageProvider,
} from './Public/Extensions/RunAnywhere+VisionLanguage';
// Hybrid STT router (cross-SDK parity with Kotlin RACRouter / Swift
// HybridSTTRouter). Per-request offline(sherpa)↔online(cloud) dispatch;
// commons owns all routing. Public API surfaces via `RunAnywhere.hybrid.*`.
export { HybridSttRouter } from './Public/Extensions/Hybrid/HybridSttRouter';
export { CloudSTT, cloud } from './Public/Extensions/Hybrid/CloudSTT';
export type {
  CloudModelEntry,
  CloudSTTConfig,
} from './Public/Extensions/Hybrid/CloudSTT';
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
} from './Public/Extensions/Hybrid/HybridTypes';
export type {
  HybridFilterSpec,
  HybridCascadeSpec,
  HybridRoutingPolicySpec,
  HybridModelSpec,
  HybridTranscribeOptions,
  HybridTranscribeResult,
  HybridRoutedMetadata,
} from './Public/Extensions/Hybrid/HybridTypes';
export {
  setHybridDeviceStateProvider,
  registerHybridCustomFilter,
  unregisterHybridCustomFilter,
  browserDeviceStateProvider,
} from './Public/Extensions/Hybrid/HybridDeviceState';
export type { HybridDeviceStateProvider } from './Public/Extensions/Hybrid/HybridDeviceState';
export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader';
export type {
  RAGAvailability,
  RAGDocumentSummary,
  RAGEnsureReadyOptions,
} from './Public/Extensions/RunAnywhere+RAG';
export type {
  EmbeddingsOptions,
  EmbeddingsRequest,
  EmbeddingsResult,
} from './Public/Extensions/RunAnywhere+Embeddings';
export type {
  RegisterModelFile,
  RegisterModelOptions,
  RegisterMultiFileOptions,
} from './Public/Extensions/RunAnywhere+Storage';
export type {
  BackendModalitySupport,
  OnnxBackendStatus,
} from './Public/Extensions/Backends/onnxStatus';
export { LogLevel } from './Public/Extensions/RunAnywhere+Logging';
export type { LoggingConfiguration, LogDestination } from './Public/Extensions/RunAnywhere+Logging';
export type {
  HardwareProfile,
  HardwareProfileResult,
} from './Public/Extensions/RunAnywhere+Hardware';

// T6.1 — Worker streaming path. Backend packages
// (`@runanywhere/web-llamacpp`, `@runanywhere/web-onnx`) call
// `setStreamWorkerFactory(fn)` during their `register()`; consumers can
// override `Runtime.streamingMode` to force `'auto' | 'worker' | 'main'`.
// When unregistered, all adapter `*Stream` methods transparently use the
// main-thread `queueMicrotask` path (the T3.1 MVP).
export { setStreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry';
export type { StreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry';

// For error codes use ProtoErrorCode from '@runanywhere/proto-ts/errors' (re-exported below).
export { SDKException, isSDKException } from './Foundation/SDKException';
export type { ProtoErrorContext, ProtoSDKError } from './Foundation/SDKException';
export {
  ProtoErrorCategory,
  ProtoErrorCode,
  ProtoErrorSeverity,
} from './Foundation/SDKException';

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

export * from './types/index';

// Helpers — pure-JS proxies for commons utilities.
export { formatFramework } from './Public/Helpers/formatFramework';
