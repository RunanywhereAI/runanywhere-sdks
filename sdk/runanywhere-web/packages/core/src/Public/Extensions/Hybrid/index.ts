/**
 * Hybrid STT router — public barrel.
 *
 * Thin Web binding over the commons STT hybrid router for cross-SDK parity
 * with Kotlin (RACRouter) and Swift (HybridSTTRouter). Commons owns ALL
 * routing; this package only marshals proto, attaches services, and decodes
 * results. See HybridWasmModule.ts for the WASM build delta this needs to run.
 */

export { HybridSttRouter } from './HybridSttRouter';
export { CloudSTT, cloud } from './CloudSTT';
export type { CloudModelEntry, CloudSTTConfig } from './CloudSTT';
export {
  setHybridDeviceStateProvider,
  registerHybridCustomFilter,
  unregisterHybridCustomFilter,
  browserDeviceStateProvider,
} from './HybridDeviceState';
export type { HybridDeviceStateProvider } from './HybridDeviceState';
export {
  HybridBackendKind,
  HybridModelType,
  HybridRank,
  DEFAULT_CLOUD_PROVIDER,
  HYBRID_STT_CONFIDENCE_THRESHOLD,
  networkFilter,
  batteryFilter,
  customFilter,
  confidenceCascade,
  offlineSherpa,
  onlineCloud,
} from './HybridTypes';
export type {
  HybridFilterSpec,
  HybridCascadeSpec,
  HybridRoutingPolicySpec,
  HybridModelSpec,
  HybridTranscribeOptions,
  HybridTranscribeResult,
  HybridRoutedMetadata,
} from './HybridTypes';
export {
  hasHybridRouterExports,
  hybridRouterRequirementMessage,
} from './HybridWasmModule';
