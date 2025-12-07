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
// Export commonly used enums for easy access
export { LLMFramework, ModelCategory, ModelFormat } from './types/enums';

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
  requireDeviceInfoModule,
  requireFileSystemModule,
} from './native';
export type { NativeRunAnywhereModule } from './native';

// Components (following Swift SDK architecture)
export {
  // STT Component
  STTComponent,
  STTServiceWrapper,
  type STTConfiguration,
  type STTInput,
  type STTOutput,
  // TTS Component
  TTSComponent,
  TTSServiceWrapper,
  type TTSConfiguration as TTSConfig,
  type TTSInput,
  type TTSOutput,
  type TTSOptions,
  // LLM Component
  LLMComponent,
  LLMServiceWrapper,
  type LLMConfiguration,
  type LLMInput,
  type LLMOutput,
  type Message,
  MessageRole,
  FinishReason,
} from './components';

// Core Registry & Providers
export { ModuleRegistry } from './Core/ModuleRegistry';
export { LlamaCppProvider } from './Providers';
