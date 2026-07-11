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
} from './Foundation/RuntimeConfig.js';
export type {
  RuntimeModelLoadContext,
  RuntimeModelLoadFailureContext,
  RuntimeModelLoadRequest,
} from './Foundation/RuntimeConfig.js';

export { setVisionLanguageProvider } from './Public/Extensions/RunAnywhere+VisionLanguage.js';
export type { VisionLanguageProvider } from './Public/Extensions/RunAnywhere+VisionLanguage.js';

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
