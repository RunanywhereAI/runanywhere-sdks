/**
 * CommonEvents
 *
 * SDK-wide event definitions for the RunAnywhere SDK.
 * These are common events used across the SDK (initialization, storage, device, network).
 *
 * For capability-specific events (LLM, STT, TTS), see the respective capability modules.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/CommonEvents.swift
 */

import type { SDKEvent } from './SDKEvent';
import { EventCategory, EventDestination, createSDKEvent } from './SDKEvent';

// ============================================================================
// SDK Lifecycle Events
// ============================================================================

/**
 * SDK Lifecycle Event Types
 */
export type SDKLifecycleEventType =
  | 'sdk_init_started'
  | 'sdk_init_completed'
  | 'sdk_init_failed'
  | 'sdk_models_loaded';

/**
 * Create SDK initialization started event.
 */
export function createSDKInitStartedEvent(sessionId?: string): SDKEvent {
  return createSDKEvent(
    'sdk_init_started',
    EventCategory.SDK,
    {},
    { sessionId }
  );
}

/**
 * Create SDK initialization completed event.
 * @param durationMs - Time taken to initialize in milliseconds
 */
export function createSDKInitCompletedEvent(
  durationMs: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'sdk_init_completed',
    EventCategory.SDK,
    { duration_ms: durationMs.toFixed(1) },
    { sessionId }
  );
}

/**
 * Create SDK initialization failed event.
 * @param error - Error message
 */
export function createSDKInitFailedEvent(
  error: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'sdk_init_failed',
    EventCategory.SDK,
    { error },
    { sessionId }
  );
}

/**
 * Create SDK models loaded event.
 * @param count - Number of models loaded
 */
export function createSDKModelsLoadedEvent(
  count: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'sdk_models_loaded',
    EventCategory.SDK,
    { count: String(count) },
    { sessionId }
  );
}

// ============================================================================
// Model Events
// ============================================================================

/**
 * Model Event Types
 *
 * Common model lifecycle events (download, extraction, delete).
 * For capability-specific load/unload, use LLMEvent, STTEvent, TTSEvent.
 */
export type ModelEventType =
  | 'model_download_started'
  | 'model_download_progress'
  | 'model_download_completed'
  | 'model_download_failed'
  | 'model_download_cancelled'
  | 'model_extraction_started'
  | 'model_extraction_progress'
  | 'model_extraction_completed'
  | 'model_extraction_failed'
  | 'model_deleted';

/**
 * Create model download started event.
 */
export function createModelDownloadStartedEvent(
  modelId: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_download_started',
    EventCategory.Model,
    { model_id: modelId },
    { sessionId }
  );
}

/**
 * Create model download progress event.
 * Note: Progress events are analytics-only (too chatty for public EventBus).
 */
export function createModelDownloadProgressEvent(
  modelId: string,
  progress: number,
  bytesDownloaded: number,
  totalBytes: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_download_progress',
    EventCategory.Model,
    {
      model_id: modelId,
      progress: progress.toFixed(1),
      bytes_downloaded: String(bytesDownloaded),
      total_bytes: String(totalBytes),
    },
    { sessionId, destination: EventDestination.AnalyticsOnly }
  );
}

/**
 * Create model download completed event.
 */
export function createModelDownloadCompletedEvent(
  modelId: string,
  durationMs: number,
  sizeBytes: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_download_completed',
    EventCategory.Model,
    {
      model_id: modelId,
      duration_ms: durationMs.toFixed(1),
      size_bytes: String(sizeBytes),
    },
    { sessionId }
  );
}

/**
 * Create model download failed event.
 */
export function createModelDownloadFailedEvent(
  modelId: string,
  error: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_download_failed',
    EventCategory.Model,
    { model_id: modelId, error },
    { sessionId }
  );
}

/**
 * Create model download cancelled event.
 */
export function createModelDownloadCancelledEvent(
  modelId: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_download_cancelled',
    EventCategory.Model,
    { model_id: modelId },
    { sessionId }
  );
}

/**
 * Create model extraction started event.
 */
export function createModelExtractionStartedEvent(
  modelId: string,
  archiveType: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_extraction_started',
    EventCategory.Model,
    { model_id: modelId, archive_type: archiveType },
    { sessionId }
  );
}

/**
 * Create model extraction progress event.
 * Note: Progress events are analytics-only (too chatty for public EventBus).
 */
export function createModelExtractionProgressEvent(
  modelId: string,
  progress: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_extraction_progress',
    EventCategory.Model,
    { model_id: modelId, progress: progress.toFixed(1) },
    { sessionId, destination: EventDestination.AnalyticsOnly }
  );
}

/**
 * Create model extraction completed event.
 */
export function createModelExtractionCompletedEvent(
  modelId: string,
  durationMs: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_extraction_completed',
    EventCategory.Model,
    { model_id: modelId, duration_ms: durationMs.toFixed(1) },
    { sessionId }
  );
}

/**
 * Create model extraction failed event.
 */
export function createModelExtractionFailedEvent(
  modelId: string,
  error: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_extraction_failed',
    EventCategory.Model,
    { model_id: modelId, error },
    { sessionId }
  );
}

/**
 * Create model deleted event.
 */
export function createModelDeletedEvent(
  modelId: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'model_deleted',
    EventCategory.Model,
    { model_id: modelId },
    { sessionId }
  );
}

// ============================================================================
// Storage Events
// ============================================================================

/**
 * Storage Event Types
 */
export type StorageEventType =
  | 'storage_cache_cleared'
  | 'storage_cache_clear_failed'
  | 'storage_temp_cleaned';

/**
 * Create storage cache cleared event.
 */
export function createStorageCacheClearedEvent(
  freedBytes: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'storage_cache_cleared',
    EventCategory.Storage,
    { freed_bytes: String(freedBytes) },
    { sessionId }
  );
}

/**
 * Create storage cache clear failed event.
 */
export function createStorageCacheClearFailedEvent(
  error: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'storage_cache_clear_failed',
    EventCategory.Storage,
    { error },
    { sessionId }
  );
}

/**
 * Create temp files cleaned event.
 */
export function createStorageTempFilesCleanedEvent(
  freedBytes: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'storage_temp_cleaned',
    EventCategory.Storage,
    { freed_bytes: String(freedBytes) },
    { sessionId }
  );
}

// ============================================================================
// Device Events
// ============================================================================

/**
 * Device Event Types
 */
export type DeviceEventType =
  | 'device_registered'
  | 'device_registration_failed';

/**
 * Create device registered event.
 */
export function createDeviceRegisteredEvent(
  deviceId: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'device_registered',
    EventCategory.Device,
    { device_id: deviceId },
    { sessionId }
  );
}

/**
 * Create device registration failed event.
 */
export function createDeviceRegistrationFailedEvent(
  error: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'device_registration_failed',
    EventCategory.Device,
    { error },
    { sessionId }
  );
}

// ============================================================================
// Network Events
// ============================================================================

/**
 * Network Event Types
 */
export type NetworkEventType =
  | 'network_connectivity_changed'
  | 'network_request_failed';

/**
 * Create network connectivity changed event.
 * Note: Network events are analytics-only by default.
 */
export function createNetworkConnectivityChangedEvent(
  isOnline: boolean,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'network_connectivity_changed',
    EventCategory.Network,
    { is_online: String(isOnline) },
    { sessionId, destination: EventDestination.AnalyticsOnly }
  );
}

/**
 * Create network request failed event.
 * Note: Network events are analytics-only by default.
 */
export function createNetworkRequestFailedEvent(
  url: string,
  error: string,
  statusCode?: number,
  sessionId?: string
): SDKEvent {
  const properties: Record<string, string> = { url, error };
  if (statusCode !== undefined) {
    properties.status_code = String(statusCode);
  }

  return createSDKEvent(
    'network_request_failed',
    EventCategory.Network,
    properties,
    {
      sessionId,
      destination: EventDestination.AnalyticsOnly,
    }
  );
}

// ============================================================================
// Error Events
// ============================================================================

/**
 * Error Event Types
 */
export type ErrorEventType = 'error';

/**
 * Create general error event.
 * Note: Error events are analytics-only by default.
 */
export function createErrorEvent(
  operation: string,
  message: string,
  code?: number,
  sessionId?: string
): SDKEvent {
  const properties: Record<string, string> = { operation, message };
  if (code !== undefined) {
    properties.code = String(code);
  }

  return createSDKEvent('error', EventCategory.Error, properties, {
    sessionId,
    destination: EventDestination.AnalyticsOnly,
  });
}

// ============================================================================
// Framework Events
// ============================================================================

/**
 * Framework Event Types
 */
export type FrameworkEventType =
  | 'framework_models_requested'
  | 'framework_models_retrieved';

/**
 * Create framework models requested event.
 * Note: Framework events are analytics-only.
 */
export function createFrameworkModelsRequestedEvent(
  framework: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'framework_models_requested',
    EventCategory.SDK,
    { framework },
    { sessionId, destination: EventDestination.AnalyticsOnly }
  );
}

/**
 * Create framework models retrieved event.
 * Note: Framework events are analytics-only.
 */
export function createFrameworkModelsRetrievedEvent(
  framework: string,
  count: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'framework_models_retrieved',
    EventCategory.SDK,
    { framework, count: String(count) },
    { sessionId, destination: EventDestination.AnalyticsOnly }
  );
}

// ============================================================================
// Voice Pipeline Events
// ============================================================================

/**
 * Voice Pipeline Event Types
 */
export type VoicePipelineEventType =
  | 'voice_pipeline_started'
  | 'voice_pipeline_completed'
  | 'voice_pipeline_failed'
  | 'vad_started'
  | 'vad_speech_detected'
  | 'vad_speech_ended'
  | 'vad_stopped';

/**
 * Create voice pipeline started event.
 */
export function createVoicePipelineStartedEvent(sessionId?: string): SDKEvent {
  return createSDKEvent(
    'voice_pipeline_started',
    EventCategory.Voice,
    {},
    { sessionId }
  );
}

/**
 * Create voice pipeline completed event.
 */
export function createVoicePipelineCompletedEvent(
  durationMs: number,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'voice_pipeline_completed',
    EventCategory.Voice,
    { duration_ms: durationMs.toFixed(1) },
    { sessionId }
  );
}

/**
 * Create voice pipeline failed event.
 */
export function createVoicePipelineFailedEvent(
  error: string,
  sessionId?: string
): SDKEvent {
  return createSDKEvent(
    'voice_pipeline_failed',
    EventCategory.Voice,
    { error },
    { sessionId }
  );
}

/**
 * Create VAD started event.
 */
export function createVADStartedEvent(sessionId?: string): SDKEvent {
  return createSDKEvent('vad_started', EventCategory.Voice, {}, { sessionId });
}

/**
 * Create speech detected event.
 */
export function createSpeechDetectedEvent(sessionId?: string): SDKEvent {
  return createSDKEvent(
    'vad_speech_detected',
    EventCategory.Voice,
    {},
    { sessionId }
  );
}

/**
 * Create speech ended event.
 */
export function createSpeechEndedEvent(sessionId?: string): SDKEvent {
  return createSDKEvent(
    'vad_speech_ended',
    EventCategory.Voice,
    {},
    { sessionId }
  );
}

/**
 * Create VAD stopped event.
 */
export function createVADStoppedEvent(sessionId?: string): SDKEvent {
  return createSDKEvent('vad_stopped', EventCategory.Voice, {}, { sessionId });
}

// ============================================================================
// Combined Event Types (for type guards and filtering)
// ============================================================================

/**
 * All common event types.
 */
export type CommonEventType =
  | SDKLifecycleEventType
  | ModelEventType
  | StorageEventType
  | DeviceEventType
  | NetworkEventType
  | ErrorEventType
  | FrameworkEventType
  | VoicePipelineEventType;
