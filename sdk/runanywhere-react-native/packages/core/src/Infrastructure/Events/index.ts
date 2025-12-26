/**
 * Infrastructure Events Module
 *
 * Exports the unified SDK event system:
 * - SDKEvent: Core event interface
 * - EventDestination: Routing control enum
 * - EventCategory: Event categorization enum
 * - EventPublisher: Single entry point for event tracking
 * - CommonEvents: SDK-wide event factory functions
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/
 */

// SDKEvent protocol and related types
export {
  type SDKEvent,
  EventDestination,
  EventCategory,
  createSDKEvent,
  isSDKEvent,
} from './SDKEvent';

// EventPublisher for unified event routing
export { EventPublisher, type EventPublisherImpl } from './EventPublisher';

// CommonEvents - SDK-wide event factory functions
export {
  // Event type definitions
  type SDKLifecycleEventType,
  type ModelEventType,
  type StorageEventType,
  type DeviceEventType,
  type NetworkEventType,
  type ErrorEventType,
  type FrameworkEventType,
  type VoicePipelineEventType,
  type CommonEventType,
  // SDK Lifecycle events
  createSDKInitStartedEvent,
  createSDKInitCompletedEvent,
  createSDKInitFailedEvent,
  createSDKModelsLoadedEvent,
  // Model events
  createModelDownloadStartedEvent,
  createModelDownloadProgressEvent,
  createModelDownloadCompletedEvent,
  createModelDownloadFailedEvent,
  createModelDownloadCancelledEvent,
  createModelExtractionStartedEvent,
  createModelExtractionProgressEvent,
  createModelExtractionCompletedEvent,
  createModelExtractionFailedEvent,
  createModelDeletedEvent,
  // Storage events
  createStorageCacheClearedEvent,
  createStorageCacheClearFailedEvent,
  createStorageTempFilesCleanedEvent,
  // Device events
  createDeviceRegisteredEvent,
  createDeviceRegistrationFailedEvent,
  // Network events
  createNetworkConnectivityChangedEvent,
  createNetworkRequestFailedEvent,
  // Error events
  createErrorEvent,
  // Framework events
  createFrameworkModelsRequestedEvent,
  createFrameworkModelsRetrievedEvent,
  // Voice pipeline events
  createVoicePipelineStartedEvent,
  createVoicePipelineCompletedEvent,
  createVoicePipelineFailedEvent,
  createVADStartedEvent,
  createSpeechDetectedEvent,
  createSpeechEndedEvent,
  createVADStoppedEvent,
} from './CommonEvents';
