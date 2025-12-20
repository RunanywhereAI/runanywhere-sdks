/**
 * Core/Capabilities/index.ts
 *
 * Exports all capability-related types, protocols, and managers.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Capabilities/
 */

// Capability Protocols and Types
export {
  // Loading State
  CapabilityLoadingState,
  idleState,
  loadingState,
  loadedState,
  failedState,
  isIdle,
  isLoading,
  isLoaded,
  isFailed,
  getResourceId,
  // Operation Result
  CapabilityOperationResult,
  createOperationResult,
  // Configuration
  ComponentConfiguration,
  // Capability Protocols
  Capability,
  ModelLoadableCapability,
  ServiceBasedCapability,
  CompositeCapability,
  // Metrics
  CapabilityMetrics,
  // Errors
  CapabilityError,
  CapabilityErrorCode,
} from './CapabilityProtocols';

// Resource Types
export { CapabilityResourceType, getResourceTypeDisplayName } from './ResourceTypes';

// Model Lifecycle Manager
export {
  ModelLifecycleManager,
  LoadResourceFn,
  UnloadResourceFn,
  ModelLifecycleManagerOptions,
} from './ModelLifecycleManager';

// Managed Lifecycle
export {
  ManagedLifecycle,
  ManagedLifecycleOptions,
  ModelLifecycleMetrics,
} from './ManagedLifecycle';

// Lifecycle Events
export {
  // LLM Events
  LLMLifecycleEventType,
  createLLMModelLoadStartedEvent,
  createLLMModelLoadCompletedEvent,
  createLLMModelLoadFailedEvent,
  createLLMModelUnloadedEvent,
  // STT Events
  STTLifecycleEventType,
  createSTTModelLoadStartedEvent,
  createSTTModelLoadCompletedEvent,
  createSTTModelLoadFailedEvent,
  createSTTModelUnloadedEvent,
  // TTS Events
  TTSLifecycleEventType,
  createTTSModelLoadStartedEvent,
  createTTSModelLoadCompletedEvent,
  createTTSModelLoadFailedEvent,
  createTTSModelUnloadedEvent,
  // VAD Events
  VADLifecycleEventType,
  createVADModelLoadStartedEvent,
  createVADModelLoadCompletedEvent,
  createVADModelLoadFailedEvent,
  createVADModelUnloadedEvent,
  // SpeakerDiarization Events
  SpeakerDiarizationLifecycleEventType,
  createSpeakerDiarizationModelLoadStartedEvent,
  createSpeakerDiarizationModelLoadCompletedEvent,
  createSpeakerDiarizationModelLoadFailedEvent,
  createSpeakerDiarizationModelUnloadedEvent,
  // Combined
  LifecycleEventType,
} from './LifecycleEvents';
