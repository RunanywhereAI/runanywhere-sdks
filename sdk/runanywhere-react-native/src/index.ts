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
export {
  RunAnywhere,
  Conversation,
  type ModelInfo,
  type DownloadProgress as ModelDownloadProgress,
} from './Public/RunAnywhere';
export default _RunAnywhere;

// Types
export * from './types';
// Export commonly used enums for easy access
export {
  LLMFramework,
  ModelCategory,
  ModelFormat,
  AudioFormat,
  getAudioFormatMimeType,
  getAudioFormatFileExtension,
} from './types/enums';

// Foundation (Core infrastructure matching iOS SDK)
export {
  // Initialization (matching iOS two-phase initialization pattern)
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
  // Error Types (matching iOS Foundation/ErrorTypes/)
  ErrorCode,
  getErrorCodeMessage,
  ErrorCategory,
  allErrorCategories,
  getCategoryFromCode,
  inferCategoryFromError,
  type ErrorContext,
  createErrorContext,
  formatStackTrace,
  formatLocation,
  formatContext,
  ContextualError,
  withContext,
  getErrorContext,
  getUnderlyingError,
  // SDKError (unified - supports both legacy SDKErrorCode and numeric ErrorCode)
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
} from './Foundation';

// Events
export { EventBus, NativeEventNames } from './Public/Events';

// Infrastructure (Event system with routing)
export {
  type SDKEvent,
  EventDestination,
  EventCategory,
  createSDKEvent,
  isSDKEvent,
  EventPublisher,
  // Analytics & Telemetry
  TelemetryEventType,
  TelemetryRepository,
  type TelemetryDataEntity,
  type TelemetryStorage,
  AnalyticsQueueManager,
  LLMAnalyticsService,
  STTAnalyticsService,
  TTSAnalyticsService,
} from './Infrastructure';

// Services
export {
  ModelRegistry,
  DownloadService,
  DownloadState,
  JSDownloadService,
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
  type JSDownloadProgress,
} from './services';

// Authentication types from Data/Network
export { type AuthenticationResponse } from './Data/Network';

// Native Module (for advanced use)
export {
  NativeRunAnywhere,
  isNativeModuleAvailable,
  requireNativeModule,
  requireDeviceInfoModule,
  requireFileSystemModule,
} from './native';
export type { NativeRunAnywhereModule } from './native';

// Features (following Swift SDK architecture)
export {
  // STT Capability
  STTCapability,
  STTServiceWrapper,
  type STTConfiguration,
  type STTInput,
  type STTOutput,
  STTError,
  // TTS Capability
  TTSCapability,
  TTSServiceWrapper,
  type TTSConfiguration as TTSConfig,
  type TTSInput,
  type TTSOutput,
  type TTSOptions,
  TTSError,
  // LLM Capability
  LLMCapability,
  LLMServiceWrapper,
  type LLMConfiguration,
  type LLMInput,
  type LLMOutput,
  type Message,
  MessageRole,
  FinishReason,
  LLMError,
  // VAD Capability
  VADCapability,
  VADError,
} from './Features';

// Core Registry & Providers
export { ServiceRegistry } from './Foundation/DependencyInjection/ServiceRegistry';
export { ServiceContainer } from './Foundation/DependencyInjection/ServiceContainer';
export { LlamaCppProvider } from './Providers';

// Security (matching iOS Foundation/Security/)
export {
  SecureStorageKeys,
  SecureStorageService,
  type SecureStorageErrorCode,
  SecureStorageError,
  isSecureStorageError,
  isItemNotFoundError,
} from './Foundation/Security';

// Data/Network (matching iOS Data/Network/)
export {
  // APIClient
  APIClient,
  APIClientError,
  createAPIClient,
  type APIClientConfig,
  type AuthenticationProvider,
  // Endpoints
  type APIEndpointType,
  type APIEndpointDefinition,
  APIEndpoints,
  deviceRegistrationEndpointForEnvironment,
  analyticsEndpointForEnvironment,
  // Auth Models
  type AuthenticationRequest,
  type RefreshTokenRequest,
  type DeviceRegistrationRequest,
  type DeviceRegistrationResponse,
  type HealthCheckResponse,
  toInternalAuthResponse,
  createAuthRequest,
  createRefreshRequest,
} from './Data/Network';

// Data/Protocols (matching iOS Data/Protocols/)
export {
  // Repository Protocol
  type Repository,
  type SyncableRepository,
  RepositoryHelpers,
  // Repository Entity
  type RepositoryEntity,
  RepositoryEntityHelpers,
  // Data Source
  type DataSource,
  type RemoteDataSource,
  type LocalDataSource,
  type DataSourceStorageInfo,
  DataSourceError,
  DataSourceErrorCode,
  RemoteOperationHelper,
  // Repository Errors
  RepositoryError,
} from './Data/Protocols';

// Data/Repositories (matching iOS Data/Repositories/)
export { ModelInfoRepository } from './Data/Repositories';

// Data/Services (matching iOS Data/Services/)
export { ModelInfoService } from './Data/Services';

// Data/Sync (matching iOS Data/Sync/)
export { SyncCoordinator } from './Data/Sync';

// Core/Capabilities (matching iOS Core/Capabilities/)
export {
  // Capability Protocols
  type Capability,
  type ModelLoadableCapability,
  type ServiceBasedCapability,
  type CompositeCapability,
  type ComponentConfiguration,
  // Loading State
  type CapabilityLoadingState,
  isIdle,
  isLoading,
  isLoaded,
  isFailed,
  // Resource Types
  CapabilityResourceType,
  // Managed Lifecycle
  ManagedLifecycle,
  ModelLifecycleManager,
  // Errors
  CapabilityError,
  CapabilityErrorCode,
} from './Core/Capabilities';
