/**
 * @runanywhere/core - Core SDK for RunAnywhere React Native
 *
 * Thin TypeScript wrapper over native commons.
 * All business logic is in native C++ (runanywhere-commons).
 *
 * @packageDocumentation
 */

// =============================================================================
// Main SDK
// =============================================================================

export { RunAnywhere } from './Public/RunAnywhere';

// =============================================================================
// Types
// =============================================================================

export * from './types';

// =============================================================================
// Foundation - Error Types
// =============================================================================

export {
  // Error Codes
  ErrorCode,
  getErrorCodeMessage,
  // Error Category
  ErrorCategory,
  allErrorCategories,
  getCategoryFromCode,
  inferCategoryFromError,
  // Error Context
  type ErrorContext,
  createErrorContext,
  formatStackTrace,
  formatLocation,
  formatContext,
  ContextualError,
  withContext,
  getErrorContext,
  getUnderlyingError,
  // SDKError
  SDKErrorCode,
  type SDKErrorProtocol,
  SDKError,
  asSDKError,
  isSDKError,
  captureAndThrow,
  notInitializedError,
  alreadyInitializedError,
  invalidInputError,
  modelNotFoundError,
  modelLoadError,
  networkError,
  authenticationError,
  generationError,
  storageError,
} from './Foundation/ErrorTypes';

// =============================================================================
// Foundation - Initialization
// =============================================================================

export {
  InitializationPhase,
  type SDKInitParams,
  type InitializationState,
  isSDKUsable,
  areServicesReady,
  isInitializing,
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from './Foundation/Initialization';

// =============================================================================
// Foundation - Security
// =============================================================================

export {
  SecureStorageKeys,
  SecureStorageService,
  type SecureStorageErrorCode,
  SecureStorageError,
  isSecureStorageError,
  isItemNotFoundError,
} from './Foundation/Security';

// =============================================================================
// Foundation - Logging
// =============================================================================

export { SDKLogger } from './Foundation/Logging/Logger/SDKLogger';
export { LogLevel } from './Foundation/Logging/Models/LogLevel';
export { LoggingManager } from './Foundation/Logging/Services/LoggingManager';

// =============================================================================
// Foundation - DI
// =============================================================================

export { ServiceRegistry } from './Foundation/DependencyInjection/ServiceRegistry';
export { ServiceContainer } from './Foundation/DependencyInjection/ServiceContainer';

// =============================================================================
// Events
// =============================================================================

export { EventBus, NativeEventNames } from './Public/Events';
export {
  type SDKEvent,
  EventDestination,
  EventCategory,
  createSDKEvent,
  isSDKEvent,
  EventPublisher,
} from './Infrastructure/Events';

// =============================================================================
// Services (thin wrappers over native)
// =============================================================================

export {
  ModelRegistry,
  DownloadService,
  DownloadState,
  SystemTTSService,
  getVoicesByLanguage,
  getDefaultVoice,
  getPlatformDefaultVoice,
  PlatformVoices,
  type ModelCriteria,
  type AddModelFromURLOptions,
  type DownloadProgress,
  type DownloadTask,
  type DownloadConfiguration,
  type ProgressCallback,
} from './services';

// =============================================================================
// Features
// =============================================================================

export {
  AudioCaptureManager,
  AudioPlaybackManager,
  VoiceSessionHandle,
  DEFAULT_VOICE_SESSION_CONFIG,
} from './Features';
export type {
  AudioDataCallback,
  AudioLevelCallback,
  AudioCaptureConfig,
  AudioCaptureState,
  PlaybackState,
  PlaybackCompletionCallback,
  PlaybackErrorCallback,
  PlaybackConfig,
  VoiceSessionConfig,
  VoiceSessionEvent,
  VoiceSessionEventType,
  VoiceSessionEventCallback,
  VoiceSessionState,
} from './Features';

// =============================================================================
// Native Module (re-export for convenience)
// =============================================================================

export {
  NativeRunAnywhere,
  isNativeModuleAvailable,
  requireNativeModule,
  requireDeviceInfoModule,
  requireFileSystemModule,
} from '@runanywhere/native';
export type { NativeRunAnywhereModule } from '@runanywhere/native';
