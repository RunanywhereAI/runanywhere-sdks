/**
 * RunAnywhere React Native SDK
 *
 * On-device AI with intelligent routing between on-device and cloud execution
 * for optimal cost and privacy.
 *
 * @packageDocumentation
 */

// Main SDK
import { RunAnywhere as _RunAnywhere } from './RunAnywhere';
export { RunAnywhere, Conversation } from './RunAnywhere';
export default _RunAnywhere;

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

// Components (following Swift SDK architecture)
export {
  // STT Component
  STTComponent,
  createSTTComponent,
  STTMode,
  DEFAULT_STT_CONFIG,
  type STTConfiguration,
  type STTInput,
  type STTOutput,
  type STTStreamHandle,
  type WordTimestamp,
  type TranscriptionAlternative,
  type TranscriptionMetadata,
  // TTS Component
  TTSComponent,
  createTTSComponent,
  DEFAULT_TTS_CONFIG,
  type TTSComponentConfiguration,
  type TTSInput,
  type TTSOutput,
  type TTSOptions,
  type PhonemeTimestamp,
  type SynthesisMetadata,
  type VoiceInfo,
} from './components';
