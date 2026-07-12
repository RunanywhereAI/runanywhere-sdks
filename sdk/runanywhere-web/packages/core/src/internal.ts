/**
 * Internal Web SDK entrypoint.
 *
 * SDK harnesses use this broad surface for low-level diagnostics. Backend
 * packages use the narrower `@runanywhere/web/backend` contract; app code
 * should import from `@runanywhere/web`.
 */

export {
  clearRunanywhereModule,
  getModuleForCapability,
  registerWasmModule,
  tryRunanywhereModule,
  unregisterWasmModule,
} from './runtime/EmscriptenModule.js';
export type {
  EmscriptenRunanywhereModule,
  WasmCapability,
} from './runtime/EmscriptenModule.js';

export {
  hasSpeechBackendExports,
  missingSpeechBackendExports,
  speechBackendRequirementMessage,
} from './runtime/SpeechBackendExports.js';
export type { SpeechBackendModule } from './runtime/SpeechBackendExports.js';

// Shared browser rac_platform_adapter_t populator (MEMFS / localStorage /
// console / Date.now) — used by the core Commons module and every backend
// bridge so the mandatory-slot guard in rac_init is satisfied identically.
export { PlatformAdapter } from './runtime/PlatformAdapter.js';
export type { PlatformAdapterModule } from './runtime/PlatformAdapter.js';

export {
  completeDeferredServicesInitialization,
  completeNativePhase1ForModule,
} from './Public/RunAnywhere.js';

export {
  Runtime,
  setAccelerationSwitcher,
  setActiveAccelerationMode,
  setModelLoadPreparation,
  prepareModelLoad,
  setModelLoadFailureRecovery,
  recoverModelLoadFailure,
} from './Foundation/RuntimeConfig.js';
export type {
  RuntimeAccelerationMode,
  RuntimeAccelerationSwitcher,
  RuntimeModelLoadContext,
  RuntimeModelLoadFailureContext,
  RuntimeModelLoadRequest,
  RuntimeModelLoadPreparation,
  RuntimeModelLoadFailureRecovery,
  StreamingMode,
} from './Foundation/RuntimeConfig.js';

// T6.1 — Worker streaming primitives. Backend packages call
// `setStreamWorkerInit(...)` with their wasm bytes + factory id during
// `register()`. App code does NOT use these — see `index.ts` for the
// public `setStreamWorkerFactory`.
export {
  setStreamWorkerFactory,
  getStreamWorkerFactory,
  hasStreamWorkerFactory,
} from './runtime/StreamWorkerFactoryRegistry.js';
export type { StreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry.js';
export {
  OffscreenRuntimeBridge,
  setStreamWorkerInit,
} from './runtime/OffscreenRuntimeBridge.js';
export type {
  BridgeStreamRequest,
  StreamIteratorOptions,
} from './runtime/OffscreenRuntimeBridge.js';
export type {
  StreamRequestKind,
  StreamWorkerModule,
  StreamModuleFactory,
  StreamWorkerScope,
  WorkerRequest,
  WorkerResponse,
} from './runtime/StreamWorker.js';
export {
  registerStreamModuleFactory,
  runStreamWorker,
} from './runtime/StreamWorker.js';
export type { AccelerationMode } from './Foundation/WASMBridge.js';

export { SDKLogger, LogLevel } from './Foundation/SDKLogger.js';
// For error codes use ProtoErrorCode (positive values from '@runanywhere/proto-ts/errors',
// re-exported here); negate to get the signed rac_result_t cAbiCode.
export { SDKException, isSDKException } from './Foundation/SDKException.js';
export { ProtoErrorCategory, ProtoErrorCode, ProtoErrorSeverity } from './Foundation/SDKException.js';
export type { ProtoSDKError, ProtoErrorContext } from './Foundation/SDKException.js';
export {
  RAC_ERROR_NETWORK_UNAVAILABLE,
  RAC_ERROR_NETWORK_ERROR,
  RAC_ERROR_INVALID_ARGUMENT,
  RAC_ERROR_CANCELLED,
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  RAC_ERROR_NOT_FOUND,
  RAC_ERROR_FEATURE_NOT_AVAILABLE,
} from './Foundation/RACErrors.js';
export { EventBus } from './Foundation/EventBus.js';
export type { EventListener, SDKEventEnvelope, Unsubscribe } from './Foundation/EventBus.js';

export { HTTPAdapter, HTTP_FETCH_CARVE_OUTS } from './Adapters/HTTPAdapter.js';
export type {
  ChunkHandler,
  DownloadProgressHandler,
  DownloadRequest,
  HTTPHeader,
  HTTPModule,
  HTTPRequest,
  HTTPResponse,
} from './Adapters/HTTPAdapter.js';

export { ModelRegistryAdapter } from './Adapters/ModelRegistryAdapter.js';
export type {
  ModelInfoList,
  ModelRegistryAvailability,
  ModelRegistryModule,
  RefreshOptions,
} from './Adapters/ModelRegistryAdapter.js';
export { ModelLifecycleAdapter } from './Adapters/ModelLifecycleAdapter.js';
export type { ModelLifecycleModule } from './Adapters/ModelLifecycleAdapter.js';
export { DownloadAdapter } from './Adapters/DownloadAdapter.js';
export type { DownloadModule, ProtoDownloadProgressHandler } from './Adapters/DownloadAdapter.js';

// Raw proto-bridge namespaces (Web's CppBridge analog). Swift keeps its
// bridge internal, so these are NOT on the public `RunAnywhere` facade —
// app code uses the flat Swift-named verbs (`downloadModel`, `listModels`,
// `importModel`, ...) instead. Backend packages and harnesses that need the
// raw plan/start/poll or registry mutate primitives import them from here.
export { Downloads } from './Public/Extensions/RunAnywhere+Downloads.js';
export { ModelRegistry } from './Public/Extensions/RunAnywhere+ModelRegistry.js';
export { StorageAdapter } from './Adapters/StorageAdapter.js';
export type { StorageModule } from './Adapters/StorageAdapter.js';
export { SDKEventStreamAdapter } from './Adapters/SDKEventStreamAdapter.js';
export type {
  SDKEventHandler,
  SDKEventStreamModule,
  SDKEventUnsubscribe,
} from './Adapters/SDKEventStreamAdapter.js';

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
} from './Adapters/ModalityProtoAdapter.js';
export type {
  ModalityProtoModule,
  ProtoEventHandler,
} from './Adapters/ModalityProtoAdapter.js';
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter.js';
export type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';

export {
  createDefaultRAGConfiguration,
  createRAGNativeProvider,
  getRAGAvailability,
  isRAGAvailable,
  setRAGProvider,
  setRAGSessionHandle,
} from './Public/Extensions/RunAnywhere+RAG.js';
export type {
  RAGAvailability,
  RAGAvailabilitySource,
  RAGNativeProviderOptions,
  RAGProvider,
  RAGProviderCapabilities,
} from './Public/Extensions/RunAnywhere+RAG.js';

export {
  createVoiceAgentHandleProvider,
  getVoiceAgentAvailability,
  isVoiceAgentAvailable,
  setVoiceAgentHandle,
  setVoiceAgentProvider,
} from './Public/Extensions/RunAnywhere+VoiceAgent.js';
export type {
  VoiceAgentAvailability,
  VoiceAgentAvailabilitySource,
  VoiceAgentProvider,
  VoiceAgentStreamSource,
} from './Public/Extensions/RunAnywhere+VoiceAgent.js';

export {
  setVisionLanguageProvider,
} from './Public/Extensions/RunAnywhere+VisionLanguage.js';
export type {
  VisionLanguageProvider,
} from './Public/Extensions/RunAnywhere+VisionLanguage.js';

export { SolutionAdapter, SolutionHandle } from './Adapters/SolutionAdapter.js';
export type { SolutionRunInput } from './Adapters/SolutionAdapter.js';
