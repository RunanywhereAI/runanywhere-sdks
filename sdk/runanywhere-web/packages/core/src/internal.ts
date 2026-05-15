/**
 * Internal Web SDK entrypoint.
 *
 * Backend packages use this surface to install WASM modules and browser
 * platform adapters. App code should import from `@runanywhere/web`.
 */

export {
  clearRunanywhereModule,
  setRunanywhereModule,
  tryRunanywhereModule,
} from './runtime/EmscriptenModule';
export type { EmscriptenRunanywhereModule } from './runtime/EmscriptenModule';

export {
  hasSpeechBackendExports,
  missingSpeechBackendExports,
  speechBackendRequirementMessage,
} from './runtime/SpeechBackendExports';
export type { SpeechBackendModule } from './runtime/SpeechBackendExports';

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
} from './Foundation/RuntimeConfig';
export type { AccelerationMode } from './Foundation/WASMBridge';

export { SDKLogger, LogLevel } from './Foundation/SDKLogger';
export { SDKErrorCode, SDKException, isSDKException } from './Foundation/SDKException';
export type { ProtoSDKError, ProtoErrorContext } from './Foundation/SDKException';
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
export { HardwareAdapter } from './Adapters/HardwareAdapter';
export type { HardwareModule } from './Adapters/HardwareAdapter';
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
  unavailableRAGResult,
  unavailableRAGStatistics,
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
  unavailableVoiceAgentResult,
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
