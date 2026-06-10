/**
 * Hybrid STT router public surface.
 *
 * THIN binding over the commons STT hybrid router (offline sherpa <-> cloud).
 * Commons owns all routing (filter / rank / cascade / fallback); this layer only
 * marshals proto bytes + handles through the Nitro `RunAnywhereCore` bridge.
 *
 * Mirrors Swift `Sources/RunAnywhere/Hybrid/*` and Kotlin
 * `public/hybrid/*` (RACRouter / Backend / RACModel / RoutingPolicy / CloudSTT).
 */

export { HybridSttRouter } from './HybridSttRouter';
export {
  CloudSTT,
  type CloudModelEntry,
  type CloudRegisterOptions,
} from './CloudSTT';
export {
  HybridDeviceState,
  type HybridDeviceStateProvider,
} from './HybridDeviceState';
export {
  HybridBackendKind,
  HybridModelType,
  DEFAULT_CLOUD_PROVIDER,
  offlineSherpa,
  onlineCloud,
  pinnedEngineName,
  type HybridModel,
  type HybridTranscribeOptions,
  type HybridTranscribeResult,
  type HybridRoutedMetadata,
} from './HybridModel';
export {
  HybridRank,
  HYBRID_STT_CONFIDENCE_THRESHOLD,
  Filters,
  Cascades,
  customFiltersOf,
  encodeHybridRoutingPolicy,
  type HybridFilter,
  type HybridCascade,
  type HybridRoutingPolicy,
  type CustomFilterCheck,
} from './HybridRoutingPolicy';
