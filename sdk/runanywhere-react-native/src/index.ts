/**
 * RunAnywhere React Native SDK
 *
 * On-device AI with intelligent routing between on-device and cloud execution
 * for optimal cost and privacy.
 *
 * @packageDocumentation
 */

// Main SDK
export { RunAnywhere, Conversation } from './RunAnywhere';
export default RunAnywhere;

// Types
export * from './types';

// Errors
export { SDKError, SDKErrorCode, ErrorCode } from './errors';

// Events
export { EventBus, NativeEventNames } from './events';

// Services
export {
  ConfigurationService,
  AuthenticationService,
  ModelRegistry,
  DownloadService,
  DownloadState,
  type ConfigurationUpdateOptions,
  type AuthenticationResponse,
  type AuthenticationState,
  type DeviceRegistrationInfo,
  type ModelCriteria,
  type AddModelFromURLOptions,
  type DownloadProgress,
  type DownloadTask,
  type DownloadConfiguration,
  type ProgressCallback,
} from './services';

// Native Module (for advanced use)
export {
  NativeRunAnywhere,
  isNativeModuleAvailable,
  requireNativeModule,
} from './native';
export type { NativeRunAnywhereModule } from './native';
