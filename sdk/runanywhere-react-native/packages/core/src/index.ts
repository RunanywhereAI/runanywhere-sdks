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
// Global NitroModules Initialization (MUST be first!)
// =============================================================================

export {
  initializeNitroModulesGlobally,
  getNitroModulesProxySync,
  isNitroModulesInitialized,
  type NitroProxy,
} from './native/NitroModulesGlobalInit';

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
  // Canonical proto error types (numeric codes + categories).
  ErrorCode,
  ErrorCategory,
  // Sole throwable surface — proto-backed `Error` subclass.
  SDKException,
  isSDKException,
  asSDKException,
} from './Foundation/ErrorTypes';
export type { ErrorContext } from './Foundation/ErrorTypes';

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
  MultiFileModelCache,
  DownloadService,
  DownloadState,
  type ModelCriteria,
  type AddModelFromURLOptions,
  type ModelFileDescriptor,
  type DownloadProgress,
  type DownloadTask,
  type DownloadConfiguration,
  type ProgressCallback,
} from './services';

// =============================================================================
// Network Layer — HTTP transport is owned by native C++ (rac_http_client_*).
// These exports are for configuration / telemetry / endpoints only.
// =============================================================================

export {
  SDKEnvironment,
  createNetworkConfig,
  getEnvironmentName,
  isDevelopment,
  isProduction,
  DEFAULT_BASE_URL,
  DEFAULT_TIMEOUT_MS,
  TelemetryService,
  TelemetryCategory,
  APIEndpoints,
} from './services';

export type {
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
} from './Features';
// v3.1: VoiceSessionHandle + DEFAULT_VOICE_SESSION_CONFIG +
// VoiceSessionConfig/Event/EventType/EventCallback/State DELETED.

// v3.1: proto-stream VoiceAgentStreamAdapter (canonical path).
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter';

// Canonical public streaming method for voice agent (§10 spec).
export { streamVoiceAgent } from './Public/Extensions/RunAnywhere+VoiceAgent';

// G-A2: proto-stream LLMStreamAdapter (canonical path) — mirrors Web's adapter.
export { LLMStreamAdapter } from './Adapters/LLMStreamAdapter';

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
// Public Extensions (standalone function exports)
// These are also available via RunAnywhere.* but exported here for direct import
// =============================================================================

export {
  getMmprojPath,
  getModelPath,
  getAvailableModels,
  getModelInfo,
  isModelDownloaded,
  downloadModel,
  cancelDownload,
  deleteModel,
  deleteAllModels,
  registerModel,
  registerMultiFileModel,
  refreshModelRegistry,
} from './Public/Extensions/RunAnywhere+Models';

// =============================================================================
// Device / NPU Chip Detection
// =============================================================================

export { getChip } from './Public/Extensions/RunAnywhere+Device';
export type { NPUChip } from './types/NPUChip';
export {
  NPU_CHIPS,
  NPU_BASE_URL,
  getNPUDownloadUrl,
  npuChipFromSocModel,
} from './types/NPUChip';

// =============================================================================
// RAG Pipeline
// =============================================================================

export {
  ragCreatePipeline,
  ragDestroyPipeline,
  ragIngest,
  ragAddDocumentsBatch,
  ragQuery,
  ragClearDocuments,
  ragGetDocumentCount,
  ragGetStatistics,
} from './Public/Extensions/RunAnywhere+RAG';

// =============================================================================
// Vision Language Model
// =============================================================================

export {
  registerVLMBackend,
  loadVLMModel,
  loadVLMModelById,
  isVLMModelLoaded,
  unloadVLMModel,
  describeImage,
  askAboutImage,
  processImage,
  processImageStream,
  cancelVLMGeneration,
} from './Public/Extensions/RunAnywhere+VisionLanguage';

// =============================================================================
// LoRA Adapter Management — canonical `RunAnywhere.lora.*` namespace
// =============================================================================

export { lora } from './Public/Extensions/RunAnywhere+LoRA';

export type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraAdapterCatalogEntry,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

// =============================================================================
// Diffusion / Image Generation
// =============================================================================

export {
  generateImage,
  generateImageStream,
  loadDiffusionModel,
  unloadDiffusionModel,
  isDiffusionModelLoaded,
  currentDiffusionModelId,
  currentDiffusionFramework,
  cancelImageGeneration,
  getDiffusionCapabilities,
} from './Public/Extensions/RunAnywhere+Diffusion';

export {
  DiffusionModelVariant,
  DiffusionScheduler,
  DiffusionMode,
  DiffusionTokenizerSourceKind,
} from '@runanywhere/proto-ts/diffusion_options';

export type {
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionProgress,
  DiffusionResult,
  DiffusionCapabilities,
  DiffusionTokenizerSource,
} from '@runanywhere/proto-ts/diffusion_options';

// Streaming wrapper (RN-local, AsyncIterable shape — no proto counterpart).
export type { DiffusionStreamingResult } from './Public/Extensions/RunAnywhere+Diffusion';

// =============================================================================
// Live Transcription Session
// =============================================================================

export {
  LiveTranscriptionSession,
  LiveTranscriptionError,
  startLiveTranscription,
} from './Public/Sessions/LiveTranscriptionSession';
export type { LiveTranscriptionListener } from './Public/Sessions/LiveTranscriptionSession';

// =============================================================================
// Streaming type re-exports for newly aligned AsyncIterable shapes
// =============================================================================

export type { STTStreamingResult } from './Public/Extensions/RunAnywhere+STT';
export type { TTSStreamingResult } from './Public/Extensions/RunAnywhere+TTS';
export type { VLMStreamingResult } from './Public/Extensions/RunAnywhere+VisionLanguage';

// =============================================================================
// Phase D namespace extensions (new). Mirror Swift `+Frameworks`,
// `+ModelAssignments`, `+ModelManagement`, `+PluginLoader`, `+VLMModels`.
// =============================================================================

export {
  getRegisteredFrameworks,
  getFrameworks,
  getModelsForFramework as getModelsForFrameworkExt,
} from './Public/Extensions/RunAnywhere+Frameworks';

export {
  fetchModelAssignments,
  getModelsForFramework as getModelsForFrameworkAssignment,
  getModelsForCategory,
} from './Public/Extensions/RunAnywhere+ModelAssignments';

export {
  loadModelByCategory,
  resolveModelFilePath,
  ensureModelDownloaded,
} from './Public/Extensions/RunAnywhere+ModelManagement';

export {
  pluginApiVersion,
  loadPlugin,
  unloadPlugin,
  registeredPluginCount,
  registeredPluginNames,
} from './Public/Extensions/RunAnywhere+PluginLoader';

export {
  loadVLMModel as loadVLMModelByInfo,
} from './Public/Extensions/RunAnywhere+VLMModels';

// =============================================================================
// Phase C-prime ergonomic helpers — proto factory defaults + predicates
// =============================================================================

import * as helpers from './helpers';
export { helpers };

export type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGResult,
  RAGSearchResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereCore } from './specs/RunAnywhereCore.nitro';
