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
  HybridSttRouter,
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
  HybridDeviceStateProvider,
} from './Public/Extensions/Hybrid';

export { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
export type { SDKInitOptions } from './types/models';

export {
  ErrorCode,
  ErrorCategory,
  SDKException,
  isSDKException,
  asSDKException,
} from './Foundation/Errors';
export type { ErrorContext } from './Foundation/Errors';

export { EventBus } from './Public/Events/EventBus';
export type {
  EventBusCancellable,
  SDKEventHandler,
} from './Public/Events/EventBus';

export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader';

export type { ToolExecutor } from './Public/Extensions/LLM/RunAnywhere+ToolCalling';
