/**
 * @runanywhere/core - Core SDK for RunAnywhere React Native
 *
 * Core SDK that includes:
 * - RACommons bindings via Nitrogen HybridObject
 * - Authentication, Device Registration
 * - Model Registry, Download Service
 * - Storage, Events, HTTP Client
 *
 * NO LLM/STT/TTS/VAD functionality - use:
 * - @runanywhere/llamacpp for text generation
 * - @runanywhere/onnx for speech processing
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
  DeviceIdentity,
} from './Foundation/Security';

// =============================================================================
// Foundation - Constants
// =============================================================================

export { SDKConstants } from './Foundation/Constants';

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
  FileSystem,
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
// Network Layer - Using axios (industry standard HTTP library)
// =============================================================================

export {
  // HTTP Service
  HTTPService,
  // Configuration
  SDKEnvironment,
  createNetworkConfig,
  getEnvironmentName,
  isDevelopment,
  isProduction,
  DEFAULT_BASE_URL,
  DEFAULT_TIMEOUT_MS,
  // Telemetry
  TelemetryService,
  TelemetryCategory,
  // Endpoints
  APIEndpoints,
} from './services';

export type {
  HTTPServiceConfig,
  DevModeConfig,
  NetworkConfig,
  APIEndpointKey,
  APIEndpointValue,
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
// Native Module (now part of core)
// =============================================================================

export {
  NativeRunAnywhereCore,
  getNativeCoreModule,
  requireNativeCoreModule,
  isNativeCoreModuleAvailable,
  // Backwards compatibility exports (match old @runanywhere/native)
  requireNativeModule,
  isNativeModuleAvailable,
  requireDeviceInfoModule,
  requireFileSystemModule,
} from './native/NativeRunAnywhereCore';
export type { NativeRunAnywhereCoreModule, FileSystemModule } from './native/NativeRunAnywhereCore';

// =============================================================================
// Cloud Provider & Routing
// =============================================================================

export {
  // Cloud types & enums
  RoutingMode,
  CloudExecutionTarget,
  HandoffReason,
  DEFAULT_ROUTING_POLICY,
  LOCAL_ONLY_POLICY,
  CLOUD_ONLY_POLICY,
  hybridAutoPolicy,
  hybridManualPolicy,
  // Provider
  OpenAICompatibleProvider,
  CloudProviderError,
  CloudProviderErrorType,
  // Manager
  CloudProviderManager,
  // Routing engine
  RoutingEngine,
  // Cost tracking
  CloudCostTracker,
  // Failover chain
  ProviderFailoverChain,
} from './cloud';
export type {
  CloudRoutingPolicy,
  RoutingDecision,
  CloudGenerationOptions,
  CloudGenerationResult,
  RoutedGenerationResult,
  RoutedStreamingResult,
  CloudProvider,
  OpenAICompatibleProviderConfig,
  // Cost tracking
  CloudCostSummary,
  // Failover chain
  ProviderHealthStatus,
  // Telemetry events
  RoutingEvent,
  CloudCostEvent,
  ProviderFailoverEvent,
  LatencyTimeoutEvent,
  CloudTelemetryEvent,
} from './cloud';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereCore } from './specs/RunAnywhereCore.nitro';
