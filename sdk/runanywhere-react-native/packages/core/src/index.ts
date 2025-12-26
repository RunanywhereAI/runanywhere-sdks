/**
 * @runanywhere/core - Core SDK for RunAnywhere React Native
 *
 * This package provides the core SDK infrastructure:
 * - Public API (RunAnywhere main class)
 * - Foundation (logging, DI, errors, security)
 * - Infrastructure (events, analytics, download)
 * - Features (capabilities interfaces)
 * - Data layer (network, repositories)
 * - Core types and models
 *
 * @packageDocumentation
 */

// =============================================================================
// Main SDK
// =============================================================================

export {
  RunAnywhere,
  Conversation,
  type ModelInfo,
  type DownloadProgress as ModelDownloadProgress,
} from './Public/RunAnywhere';

// =============================================================================
// Types
// =============================================================================

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

// =============================================================================
// Foundation
// =============================================================================

export {
  // Initialization
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
  // Error Types
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
} from './Foundation';

// =============================================================================
// Events
// =============================================================================

export { EventBus, NativeEventNames } from './Public/Events';

// =============================================================================
// Infrastructure
// =============================================================================

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

// =============================================================================
// Services
// =============================================================================

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

// =============================================================================
// Data Layer
// =============================================================================

// Authentication types from Data/Network
export { type AuthenticationResponse } from './Data/Network';

// =============================================================================
// Features
// =============================================================================

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

// =============================================================================
// Voice Session
// =============================================================================

export {
  VoiceSessionHandle,
  VoiceSessionEventType,
  VoiceSessionEventFactory,
  VoiceSessionError,
  VoiceSessionErrorCode,
  isVoiceSessionError,
  DEFAULT_VOICE_SESSION_CONFIG,
  createVoiceSessionConfig,
  VoiceSessionConfigPresets,
  type VoiceSessionEvent,
  type VoiceSessionConfig,
  type VoiceSessionEventListener,
} from './Features/VoiceSession';

// =============================================================================
// Voice Agent
// =============================================================================

export {
  type VoiceAgentResult,
  type VoiceAgentStreamEvent,
  type VoiceAgentComponentStates,
  type ComponentLoadState,
  VoiceAgentError,
  VoiceAgentErrorCode,
  isVoiceAgentFullyReady,
  getMissingComponents,
} from './Features/VoiceAgent/VoiceAgentModels';

// =============================================================================
// Storage Management
// =============================================================================

export {
  type StorageInfo,
  createStorageInfo,
  createEmptyStorageInfo,
} from './Infrastructure/FileManagement/Models';
export {
  type AppStorageInfo,
  createAppStorageInfo,
} from './Infrastructure/FileManagement/Models/AppStorageInfo';
export {
  type DeviceStorageInfo,
  createDeviceStorageInfo,
} from './Infrastructure/FileManagement/Models/DeviceStorageInfo';

// =============================================================================
// Core Registry & Containers
// =============================================================================

export { ServiceRegistry } from './Foundation/DependencyInjection/ServiceRegistry';
export { ServiceContainer } from './Foundation/DependencyInjection/ServiceContainer';

// =============================================================================
// Security
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
// Data/Network
// =============================================================================

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

// =============================================================================
// Data/Protocols
// =============================================================================

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

// =============================================================================
// Data/Repositories
// =============================================================================

export type { ModelInfoRepository } from './Data/Repositories';
export { ModelInfoRepositoryImpl } from './Data/Repositories';

// =============================================================================
// Data/Services
// =============================================================================

export { ModelInfoService } from './Data/Services';

// =============================================================================
// Data/Sync
// =============================================================================

export { SyncCoordinator } from './Data/Sync';

// =============================================================================
// Core/Capabilities
// =============================================================================

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

// =============================================================================
// Core/Protocols - Service Providers
// =============================================================================

export type { LLMServiceProvider } from './Core/Protocols/LLM/LLMServiceProvider';
export type { LLMService } from './Core/Protocols/LLM/LLMService';
export type { STTServiceProvider } from './Core/Protocols/Voice/STTServiceProvider';
export type { STTService } from './Core/Protocols/Voice/STTService';
export type { TTSServiceProvider } from './Core/Protocols/Voice/TTSServiceProvider';
export type { TTSService } from './Core/Protocols/Voice/TTSService';

// =============================================================================
// Capabilities/TextGeneration - Generation Types
// =============================================================================

export type { GenerationOptions } from './Capabilities/TextGeneration/Models/GenerationOptions';
export type { GenerationResult } from './Capabilities/TextGeneration/Models/GenerationResult';
export { PerformanceMetricsImpl } from './Capabilities/TextGeneration/Models/PerformanceMetrics';
export { ExecutionTarget, HardwareAcceleration } from './types/enums';

// =============================================================================
// Re-export native module for convenience
// =============================================================================

export {
  NativeRunAnywhere,
  isNativeModuleAvailable,
  requireNativeModule,
  requireDeviceInfoModule,
  requireFileSystemModule,
} from '@runanywhere/native';
export type { NativeRunAnywhereModule } from '@runanywhere/native';
