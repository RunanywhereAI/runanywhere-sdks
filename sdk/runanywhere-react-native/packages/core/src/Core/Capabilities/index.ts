/**
 * Core/Capabilities/index.ts
 *
 * Exports all capability-related types, protocols, and managers.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Capabilities/
 */

// Capability Protocols and Types - Type exports
export type {
  CapabilityLoadingState,
  CapabilityOperationResult,
  ComponentConfiguration,
  Capability,
  ModelLoadableCapability,
  ServiceBasedCapability,
  CompositeCapability,
} from './CapabilityProtocols';

// Capability Protocols and Types - Value exports
export {
  idleState,
  loadingState,
  loadedState,
  failedState,
  isIdle,
  isLoading,
  isLoaded,
  isFailed,
  getResourceId,
  createOperationResult,
  CapabilityMetrics,
  CapabilityError,
  CapabilityErrorCode,
} from './CapabilityProtocols';

// Resource Types
export {
  CapabilityResourceType,
  getResourceTypeDisplayName,
} from './ResourceTypes';

// Model Lifecycle Manager - Type exports
export type {
  LoadResourceFn,
  UnloadResourceFn,
  ModelLifecycleManagerOptions,
} from './ModelLifecycleManager';

// Model Lifecycle Manager - Value exports
export { ModelLifecycleManager } from './ModelLifecycleManager';

// Managed Lifecycle - Type exports
export type { ManagedLifecycleOptions } from './ManagedLifecycle';

// Managed Lifecycle - Value exports
export { ManagedLifecycle } from './ManagedLifecycle';

// Analytics Types - Type exports
export type { AnalyticsMetrics, ModelLifecycleMetrics } from './Analytics';

// Analytics Types - Value exports
export {
  InferenceFrameworkType,
  ModelLifecycleEventType,
  createModelLifecycleMetrics,
} from './Analytics';

// Lifecycle Events - Type exports
export type {
  LLMLifecycleEventType,
  STTLifecycleEventType,
  TTSLifecycleEventType,
  VADLifecycleEventType,
  SpeakerDiarizationLifecycleEventType,
  LifecycleEventType,
} from './LifecycleEvents';

// Lifecycle Events - Value exports
export {
  // LLM Events
  createLLMModelLoadStartedEvent,
  createLLMModelLoadCompletedEvent,
  createLLMModelLoadFailedEvent,
  createLLMModelUnloadedEvent,
  // STT Events
  createSTTModelLoadStartedEvent,
  createSTTModelLoadCompletedEvent,
  createSTTModelLoadFailedEvent,
  createSTTModelUnloadedEvent,
  // TTS Events
  createTTSModelLoadStartedEvent,
  createTTSModelLoadCompletedEvent,
  createTTSModelLoadFailedEvent,
  createTTSModelUnloadedEvent,
  // VAD Events
  createVADModelLoadStartedEvent,
  createVADModelLoadCompletedEvent,
  createVADModelLoadFailedEvent,
  createVADModelUnloadedEvent,
  // SpeakerDiarization Events
  createSpeakerDiarizationModelLoadStartedEvent,
  createSpeakerDiarizationModelLoadCompletedEvent,
  createSpeakerDiarizationModelLoadFailedEvent,
  createSpeakerDiarizationModelUnloadedEvent,
} from './LifecycleEvents';
