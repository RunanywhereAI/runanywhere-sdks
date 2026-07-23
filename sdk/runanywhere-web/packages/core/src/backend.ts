/**
 * Backend integration contract for independently packaged Web backends.
 *
 * Application code imports from `@runanywhere/web`; backend packages import
 * this deliberately narrow surface instead of depending on the broad
 * `@runanywhere/web/internal` implementation entrypoint.
 */

export {
  registerWasmModule,
  unregisterWasmModule,
} from './runtime/EmscriptenModule.js';
export type {
  EmscriptenRunanywhereModule,
  WasmCapability,
} from './runtime/EmscriptenModule.js';

export {
  missingSpeechBackendExports,
  speechBackendRequirementMessage,
} from './runtime/SpeechBackendExports.js';

export { PlatformAdapter } from './runtime/PlatformAdapter.js';
export type { PlatformAdapterModule } from './runtime/PlatformAdapter.js';

export {
  completeDeferredServicesInitialization,
  completeNativePhase1ForModule,
} from './Public/RunAnywhere.js';

export {
  setAccelerationSwitcher,
  setActiveAccelerationMode,
  setModelLoadFailureRecovery,
  setModelLoadPreparation,
  setRuntimeDegradedReason,
} from './Foundation/RuntimeConfig.js';
export type {
  RuntimeModelLoadContext,
  RuntimeModelLoadFailureContext,
  RuntimeModelLoadRequest,
} from './Foundation/RuntimeConfig.js';

// @internal Stage 3 worker bootstrap contract. Backends may opt in from
// `register()` once they ship a bundler-specific worker entrypoint.
export {
  getBackendWorkerFactory,
  setBackendWorkerFactory,
} from './runtime/BackendWorkerFactoryRegistry.js';
export {
  BackendWorkerHost,
  getActiveBackendWorkerHost,
  getBackendWorkerRuntimeDiagnostics,
} from './runtime/BackendWorkerHost.js';
export type { BackendWorkerFactory } from './runtime/BackendWorkerHost.js';
export {
  getBackendWorkerHost,
  setBackendWorkerHost,
} from './runtime/BackendWorkerHostRegistry.js';
export type { BackendWorkerBackendId } from './runtime/BackendWorkerProtocol.js';
export {
  setLlamaBackendWorkerRequired,
  clearLlamaBackendWorkerDead,
} from './runtime/BackendWorkerModelOwnership.js';
export { runBackendWorker } from './runtime/BackendWorker.js';
export type {
  BackendWorkerHandlers,
  BackendWorkerScope,
} from './runtime/BackendWorker.js';

// T6.1 stream-worker bootstrap — retained for compatibility; production
// backends should prefer BackendWorkerHost / runBackendWorker.
export {
  setStreamWorkerFactory,
  getStreamWorkerFactory,
} from './runtime/StreamWorkerFactoryRegistry.js';
export type { StreamWorkerFactory } from './runtime/StreamWorkerFactoryRegistry.js';
export { setStreamWorkerInit } from './runtime/OffscreenRuntimeBridge.js';
export {
  registerStreamModuleFactory,
  runStreamWorker,
} from './runtime/StreamWorker.js';
export type {
  StreamModuleFactory,
  StreamWorkerModule,
  StreamWorkerScope,
} from './runtime/StreamWorker.js';

export { callEmscriptenAsyncNumber } from './runtime/EmscriptenAsync.js';
export { OPFSBridge } from './Infrastructure/OPFSBridge.js';

export { setVisionLanguageProvider } from './Public/Extensions/RunAnywhere+VisionLanguage.js';
export type { VisionLanguageProvider } from './Public/Extensions/RunAnywhere+VisionLanguage.js';
export {
  setDiffusionAvailabilityProvider,
} from './Public/Extensions/RunAnywhere+Diffusion.js';
export type {
  DiffusionAvailability,
  DiffusionAvailabilityProvider,
} from './Public/Extensions/RunAnywhere+Diffusion.js';
export {
  createPersistentRAGProvider,
  registerPersistentRAGProvider,
  registerRAGProvider,
} from './Public/Extensions/RunAnywhere+RAG.js';
export type { RAGProvider } from './Public/Extensions/RunAnywhere+RAG.js';
export { registerVoiceAgentProvider } from './Public/Extensions/RunAnywhere+VoiceAgent.js';
export type { VoiceAgentProvider } from './Public/Extensions/RunAnywhere+VoiceAgent.js';

export { HTTPAdapter } from './Adapters/HTTPAdapter.js';
export { VLMProtoAdapter } from './Adapters/ModalityProtoAdapter.js';
export {
  missingExports,
  modalityModuleFor,
} from './Adapters/ProtoAdapterTypes.js';
export type { ModalityProtoModule } from './Adapters/ProtoAdapterTypes.js';

export { SDKLogger } from './Foundation/SDKLogger.js';
export { SDKException, ProtoErrorCode } from './Foundation/SDKException.js';
export { RAC_ERROR_MODULE_ALREADY_REGISTERED } from './Foundation/RACErrors.js';
export type { AccelerationMode } from './Foundation/WASMBridge.js';

export { redactResourceURL } from './Foundation/BackendContract.js';
export type { BackendRegistrationState } from './Foundation/BackendContract.js';
