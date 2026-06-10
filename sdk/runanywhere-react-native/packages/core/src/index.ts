/**
 * @runanywhere/core - React Native public SDK facade.
 *
 * Swift is the source of truth for this surface. Generated DTOs/enums come
 * directly from `@runanywhere/proto-ts/*`; this root exports only the
 * RunAnywhere facade and the small RN call-site types/errors that do not have
 * a standalone generated package entry.
 *
 * Provider/internal plumbing lives at `@runanywhere/core/internal`.
 *
 * @packageDocumentation
 */

export { RunAnywhere } from './Public/RunAnywhere';

// Hybrid STT router (offline sherpa <-> cloud). THIN binding over the
// commons hybrid router — commons owns all routing. Mirrors Swift `Hybrid/*`
// and Kotlin `public/hybrid/*` (RACRouter / CloudSTT / RoutingPolicy).
export {
  HybridSTTRouter,
  CloudSTT,
  HybridDeviceState,
  HybridBackendKind,
  HybridModelType,
  HybridRank,
  DEFAULT_CLOUD_PROVIDER,
  HYBRID_STT_CONFIDENCE_THRESHOLD,
  Filters,
  Cascades,
  offlineSherpa,
  onlineCloud,
} from './Public/Extensions/Hybrid';
export type {
  HybridModel,
  HybridTranscribeOptions,
  HybridTranscribeResult,
  HybridRoutedMetadata,
  HybridFilter,
  HybridCascade,
  HybridRoutingPolicy,
  CustomFilterCheck,
  CloudModelEntry,
  CloudRegisterOptions,
  CloudSttProviderHandler,
  CloudSttProviderRequest,
  CloudSttProviderResult,
  HybridDeviceStateProvider,
} from './Public/Extensions/Hybrid';

export { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
export type { SDKInitOptions } from './types/models';

// SDKEnvironment behaviour helpers — mirror Swift SDKEnvironment.swift:42-128.
export {
  deployableEnvironments,
  environmentDescription,
  isProduction,
  isTesting,
  requiresBackendURL,
  shouldSendTelemetry,
  shouldSyncWithBackend,
  requiresAuthentication,
  defaultLogLevel,
} from './Public/Helpers/SDKEnvironment+Helpers';

// SDKComponent display names — mirror Swift RASDKComponent+DisplayName.swift.
export { sdkComponentDisplayName } from './Public/Helpers/SDKComponent+DisplayName';

// VLMImage factory helpers — mirror Swift RAVLMImage+Helpers.swift.
export { VLMImages } from './Public/Extensions/VLM/VLMImage+Helpers';

// Embedding vector math helpers — mirror Swift EmbeddingsProto+Helpers.swift.
export {
  cosineSimilarity,
  computeNorm,
} from './Public/Extensions/Embeddings/EmbeddingsProto+Helpers';

// Storage proto helpers — mirror Swift StorageProto+Helpers.swift.
export {
  makeDeviceStorageInfo,
  makeAppStorageInfo,
  makeModelStorageMetrics,
  makeStorageAvailability,
  emptyStorageInfo,
  totalModelsSizeBytes,
  totalModelsSize,
  storedModels,
  usagePercentage,
} from './Public/Extensions/Storage/StorageProto+Helpers';

export {
  ErrorCode,
  ErrorCategory,
  SDKException,
  isSDKException,
  asSDKException,
  isExpectedErrorCode,
  sdkExceptionFromRcResult,
  throwIfRcError,
} from './Foundation/Errors';
export type { ErrorContext } from './Foundation/Errors';

// In-SDK audio capture/playback — mirror Swift's
// Features/STT/Services/AudioCaptureManager.swift and
// Features/TTS/Services/AudioPlaybackManager.swift.
export { AudioCaptureManager } from './Features/VoiceSession/AudioCaptureManager';
export { AudioPlaybackManager } from './Features/VoiceSession/AudioPlaybackManager';

export { EventBus, modelLifecycleChange } from './Public/Events/EventBus';
export type {
  EventBusCancellable,
  SDKEventHandler,
  ModelLifecycleChange,
} from './Public/Events/EventBus';

export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader';

export type { ToolExecutor } from './Public/Extensions/LLM/RunAnywhere+ToolCalling';
