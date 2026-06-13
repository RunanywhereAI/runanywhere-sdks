/**
 * Internal Web SDK entrypoint.
 *
 * Backend packages use this surface to install WASM modules and browser
 * platform adapters. App code should import from `@runanywhere/web`.
 */

export {
  clearRunanywhereModule,
  getModuleForCapability,
  registerWasmModule,
  setRunanywhereModule,
  tryRunanywhereModule,
  unregisterWasmModule,
} from './runtime/EmscriptenModule';
export type {
  EmscriptenRunanywhereModule,
  WasmCapability,
} from './runtime/EmscriptenModule';

export {
  hasSpeechBackendExports,
  missingSpeechBackendExports,
  speechBackendRequirementMessage,
} from './runtime/SpeechBackendExports';
export type { SpeechBackendModule } from './runtime/SpeechBackendExports';

// Shared browser rac_platform_adapter_t populator (MEMFS / localStorage /
// console / Date.now) — used by the core Commons module and every backend
// bridge so the mandatory-slot guard in rac_init is satisfied identically.
export { PlatformAdapter } from './runtime/PlatformAdapter';
export type { PlatformAdapterModule } from './runtime/PlatformAdapter';

export {
  completeDeferredServicesInitialization,
  completeNativePhase1ForModule,
} from './Public/RunAnywhere';

export {
  Runtime,
  setAccelerationSwitcher,
  setActiveAccelerationMode,
  setModelLoadPreparation,
  prepareModelLoad,
  setModelLoadFailureRecovery,
  recoverModelLoadFailure,
} from './Foundation/RuntimeConfig';
export type {
  RuntimeAccelerationMode,
  RuntimeAccelerationSwitcher,
  RuntimeModelLoadPreparation,
  RuntimeModelLoadFailureRecovery,
  StreamingMode,
} from './Foundation/RuntimeConfig';

// T6.1 — Worker streaming primitives. Backend packages call
// `setStreamWorkerInit(...)` with their wasm bytes + factory id during
// `register()`. App code does NOT use these — see `index.ts` for the
// public `setStreamWorkerFactory`.
export {
  setStreamWorkerFactory,
  getStreamWorkerFactory,
  hasStreamWorkerFactory,
} from './runtime/StreamWorkerFactoryRegistry';
export type { StreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry';
export {
  OffscreenRuntimeBridge,
  setStreamWorkerInit,
} from './runtime/OffscreenRuntimeBridge';
export type {
  BridgeStreamRequest,
  StreamIteratorOptions,
} from './runtime/OffscreenRuntimeBridge';
export type {
  StreamRequestKind,
  StreamWorkerModule,
  StreamModuleFactory,
  StreamWorkerScope,
  WorkerRequest,
  WorkerResponse,
} from './runtime/StreamWorker';
export {
  registerStreamModuleFactory,
  runStreamWorker,
} from './runtime/StreamWorker';
export type { AccelerationMode } from './Foundation/WASMBridge';

export { SDKLogger, LogLevel } from './Foundation/SDKLogger';
// For error codes use ProtoErrorCode (positive values from '@runanywhere/proto-ts/errors',
// re-exported here); negate to get the signed rac_result_t cAbiCode.
export { SDKException, isSDKException } from './Foundation/SDKException';
export { ProtoErrorCategory, ProtoErrorCode, ProtoErrorSeverity } from './Foundation/SDKException';
export type { ProtoSDKError, ProtoErrorContext } from './Foundation/SDKException';
export {
  RAC_ERROR_NETWORK_UNAVAILABLE,
  RAC_ERROR_NETWORK_ERROR,
  RAC_ERROR_INVALID_ARGUMENT,
  RAC_ERROR_CANCELLED,
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  RAC_ERROR_NOT_FOUND,
  RAC_ERROR_FEATURE_NOT_AVAILABLE,
} from './Foundation/RACErrors';
export { EventBus } from './Foundation/EventBus';
export type { EventListener, SDKEventEnvelope, Unsubscribe } from './Foundation/EventBus';

export { HTTPAdapter, DownloadStatus, HTTP_FETCH_CARVE_OUTS } from './Adapters/HTTPAdapter';
export type {
  ChunkHandler,
  DownloadProgressHandler,
  DownloadRequest,
  HTTPHeader,
  HTTPModule,
  HTTPRequest,
  HTTPResponse,
} from './Adapters/HTTPAdapter';
export { FetchHttpTransport } from './Adapters/FetchHttpTransport';
export type { FetchHttpTransportModule } from './Adapters/FetchHttpTransport';

export { ModelRegistryAdapter } from './Adapters/ModelRegistryAdapter';
export type {
  ModelInfoList,
  ModelRegistryAvailability,
  ModelRegistryModule,
  RefreshOptions,
} from './Adapters/ModelRegistryAdapter';
export { ModelLifecycleAdapter } from './Adapters/ModelLifecycleAdapter';
export type { ModelLifecycleModule } from './Adapters/ModelLifecycleAdapter';
export { DownloadAdapter } from './Adapters/DownloadAdapter';
export type { DownloadModule, ProtoDownloadProgressHandler } from './Adapters/DownloadAdapter';

// Raw proto-bridge namespaces (Web's CppBridge analog). Swift keeps its
// bridge internal, so these are NOT on the public `RunAnywhere` facade —
// app code uses the flat Swift-named verbs (`downloadModel`, `listModels`,
// `importModel`, ...) instead. Backend packages and harnesses that need the
// raw plan/start/poll or registry mutate primitives import them from here.
export { Downloads } from './Public/Extensions/RunAnywhere+Downloads';
export { ModelRegistry } from './Public/Extensions/RunAnywhere+ModelRegistry';
export { StorageAdapter } from './Adapters/StorageAdapter';
export type { StorageModule } from './Adapters/StorageAdapter';
export { SDKEventStreamAdapter } from './Adapters/SDKEventStreamAdapter';
export type {
  SDKEventHandler,
  SDKEventStreamModule,
  SDKEventUnsubscribe,
} from './Adapters/SDKEventStreamAdapter';

export {
  DiffusionProtoAdapter,
  EmbeddingsProtoAdapter,
  LLMProtoAdapter,
  LoRAProtoAdapter,
  ModalityProtoAdapter,
  RAGProtoAdapter,
  STTProtoAdapter,
  TTSProtoAdapter,
  VADProtoAdapter,
  VLMProtoAdapter,
  VoiceAgentProtoAdapter,
} from './Adapters/ModalityProtoAdapter';
export type {
  ModalityProtoModule,
  ProtoEventHandler,
} from './Adapters/ModalityProtoAdapter';
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter';
export type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';

export {
  createDefaultRAGConfiguration,
  createRAGNativeProvider,
  getRAGAvailability,
  isRAGAvailable,
  setRAGProvider,
  setRAGSessionHandle,
} from './Public/Extensions/RunAnywhere+RAG';
export type {
  RAGAvailability,
  RAGAvailabilitySource,
  RAGNativeProviderOptions,
  RAGProvider,
  RAGProviderCapabilities,
} from './Public/Extensions/RunAnywhere+RAG';

export {
  createVoiceAgentHandleProvider,
  getVoiceAgentAvailability,
  isVoiceAgentAvailable,
  setVoiceAgentHandle,
  setVoiceAgentProvider,
} from './Public/Extensions/RunAnywhere+VoiceAgent';
export type {
  VoiceAgentAvailability,
  VoiceAgentAvailabilitySource,
  VoiceAgentProvider,
  VoiceAgentStreamSource,
} from './Public/Extensions/RunAnywhere+VoiceAgent';

export {
  setVisionLanguageProvider,
} from './Public/Extensions/RunAnywhere+VisionLanguage';
export type {
  VisionLanguageProvider,
} from './Public/Extensions/RunAnywhere+VisionLanguage';

export { SolutionAdapter, SolutionHandle } from './Adapters/SolutionAdapter';
export type { SolutionRunInput } from './Adapters/SolutionAdapter';
