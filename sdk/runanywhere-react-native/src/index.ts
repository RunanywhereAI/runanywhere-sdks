/**
 * RunAnywhere React Native SDK
 *
 * On-device AI with intelligent routing between on-device and cloud execution
 * for optimal cost and privacy.
 *
 * @packageDocumentation
 */

// Main SDK
import { RunAnywhere as _RunAnywhere } from './Public/RunAnywhere';
export { RunAnywhere, Conversation, type ModelInfo, type DownloadProgress as ModelDownloadProgress } from './Public/RunAnywhere';
export default _RunAnywhere;

// Types
export * from './types';

// Errors
export { SDKError, SDKErrorCode } from './Public/Errors/SDKError';

// Events
export { EventBus, NativeEventNames } from './Public/Events';

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
  createSTTConfiguration,
  STTMode,
  STTServiceWrapper,
  DEFAULT_STT_CONFIGURATION,
  type STTConfiguration,
  type STTInput,
  type STTOutput,
  type STTService,
  type WordTimestamp,
  type TranscriptionAlternative,
  type TranscriptionMetadata,
  type STTTranscriptionResult,
  type TimestampInfo,
  type AlternativeTranscription,
  // TTS Component
  TTSComponent,
  createTTSComponent,
  createTTSConfiguration,
  TTSServiceWrapper,
  DEFAULT_TTS_CONFIGURATION,
  getAudioFormatSampleRate,
  type TTSConfiguration,
  type TTSInput,
  type TTSOutput,
  type TTSOptions,
  type TTSService,
  type PhonemeTimestamp,
  type SynthesisMetadata,
  type VoiceInfo,
} from './components';
