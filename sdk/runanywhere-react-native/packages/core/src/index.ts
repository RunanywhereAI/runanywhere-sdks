/**
 * @runanywhere/core - Core SDK for RunAnywhere React Native
 *
 * Core SDK that includes:
 * - RACommons bindings via Nitrogen HybridObject
 * - Authentication, Device Registration
 * - Lifecycle-driven model loading (registry, download, paths owned by commons)
 * - Storage proto bindings
 * - Events / proto stream
 * - HTTP transport adapters (URLSession iOS / OkHttp Android)
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
} from './Foundation/Errors';
export type { ErrorContext } from './Foundation/Errors';

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
// Network Layer — HTTP transport is owned by native C++ (rac_http_client_*).
// These exports are for configuration / telemetry / endpoints only.
// =============================================================================

export {
  SDKEnvironment,
  createNetworkConfig,
  getEnvironmentName,
  looksLikePlaceholder,
  isUsableHttpUrl,
  isUsableCredential,
  hasUsableBackendConfig,
  hasUsableSupabaseConfig,
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
  ModelFileDescriptor,
} from './services';

// =============================================================================
// Features
// =============================================================================

export { AudioCaptureManager, AudioPlaybackManager } from './Features';
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
// Proto-stream VoiceAgentStreamAdapter is the canonical voice session path.
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter';

// Canonical public streaming method for voice agent (§10 spec).
export { streamVoiceAgent } from './Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent';

// proto-stream LLMStreamAdapter (canonical path) — mirrors Web's adapter.
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
} from './native/NativeRunAnywhereCore';
export type {
  NativeRunAnywhereCoreModule,
} from './native/NativeRunAnywhereCore';

// =============================================================================
// Public Extensions (standalone function exports)
// These are also available via RunAnywhere.* but exported here for direct import
// =============================================================================

export {
  deleteStorage,
  getStorageInfoProto,
  cleanTempFiles,
} from './Public/Extensions/Storage/RunAnywhere+Storage';

export {
  pollSDKEvent,
  publishSDKEvent,
  publishSDKFailure,
  subscribeSDKEvents,
} from './Public/Events/RunAnywhere+SDKEvents';

export {
  getComponentLifecycleSnapshot,
  getCurrentModel,
  getLifecycleResolvedArtifactPath,
  loadModelLifecycle,
  resolveVLMArtifactsFromLifecycleResult,
  unloadModelLifecycle,
} from './Public/Extensions/Models/RunAnywhere+ModelLifecycle';

export {
  configureLogging,
  setLocalLoggingEnabled,
  setLogLevel,
  setSentryLoggingEnabled,
  addLogDestination,
  setDebugMode,
  flushLogs,
} from './Public/Extensions/RunAnywhere+Logging';

export { pluginLoader } from './Public/Extensions/RunAnywhere+PluginLoader';
export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader';

// =============================================================================
// Hardware Profile (CANONICAL_API §14)
// =============================================================================

export {
  Hardware,
  getHardwareProfile,
  getHardwareChip,
  hardwareHasNeuralEngine,
  hardwareAccelerationMode,
  getHardwareAccelerators,
  setHardwareAcceleratorPreference,
  AccelerationPreference,
} from './Public/Extensions';
export type { AcceleratorInfo, HardwareProfileResult } from './Public/Extensions';

// =============================================================================
// Model Management — Swift parity (registerModel / downloadModel / etc.)
// =============================================================================

export {
  registerModel,
  registerMultiFileModel,
  listModels,
  queryModels,
  getModel,
  downloadedModels,
  importModel,
  downloadModel,
  cancelDownload,
  deleteModel,
  loadModel,
} from './Public/Extensions/Models/RunAnywhere+ModelRegistry';
export type {
  RegisterModelInput,
  RegisterMultiFileModelInput,
} from './Public/Extensions/Models/RunAnywhere+ModelRegistry';

// =============================================================================
// Proto byte helpers (re-export from internal services/ProtoBytes.ts)
// =============================================================================

export {
  bytesToArrayBuffer,
  arrayBufferToBytes,
} from './services/ProtoBytes';

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
} from './Public/Extensions/RAG/RunAnywhere+RAG';

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
} from './Public/Extensions/VLM/RunAnywhere+VisionLanguage';

// =============================================================================
// LoRA Adapter Management — canonical `RunAnywhere.lora.*` namespace
// =============================================================================

export { lora } from './Public/Extensions/LLM/RunAnywhere+LoRA';

export type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

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

export type { STTStreamingResult } from './Public/Extensions/STT/RunAnywhere+STT';
export type { TTSStreamingResult } from './Public/Extensions/TTS/RunAnywhere+TTS';
export type {
  VLMBackendProvider,
  VLMStreamingResult,
} from './Public/Extensions/VLM/RunAnywhere+VisionLanguage';

// =============================================================================
// VLM model overload (mirrors Swift +VLMModels)
// =============================================================================

export { loadVLMModel as loadVLMModelByInfo } from './Public/Extensions/VLM/RunAnywhere+VLMModels';

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
