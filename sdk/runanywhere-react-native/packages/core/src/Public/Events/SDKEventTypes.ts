/**
 * SDKEventTypes.ts
 *
 * JS-runtime event payload shapes emitted by native modules across the
 * RN bridge. These describe the in-process JSON objects that flow
 * through `NativeEventEmitter` into `EventBus`. They are intentionally
 * decoupled from `@runanywhere/proto-ts/sdk_events` (the wire envelope
 * `SDKEvent` with `kind` enums + oneof payload) — bridges marshal the
 * runtime shape directly to keep RN consumers free of proto decoding
 * on the hot path.
 *
 * Canonical wire shapes are re-exported from `types/index.ts` under the
 * proto-ts names (e.g. `SDKEvent`, `GenerationEvent`, `ModelEvent`, …).
 * Use those when serializing for analytics or transport. Use these
 * runtime shapes when writing in-process subscribers / dispatchers.
 *
 * Legacy location: `types/events.ts` (deleted in Phase C4).
 */

import type {
  LLMFramework,
  SDKComponent,
  SDKEventType,
} from '../../types/enums';
import type {
  DefaultGenerationSettings,
  DeviceInfoData,
  FrameworkAvailability,
  InitializationResult,
  ModelInfo,
  StorageInfo,
  StoredModel,
} from '../../types/models';

// ============================================================================
// Base runtime envelope
// ============================================================================

/**
 * Minimal runtime envelope — every payload carries an event type tag and
 * an ISO-8601 timestamp.
 */
export interface SDKRuntimeEvent {
  /** Event timestamp (ISO-8601 string) */
  timestamp: string;
  /** Event type category */
  eventType: SDKEventType;
}

// ============================================================================
// Initialization
// ============================================================================

export type SDKInitializationEvent =
  | { type: 'started' }
  | { type: 'configurationLoaded'; source: string }
  | { type: 'servicesBootstrapped' }
  | { type: 'completed' }
  | { type: 'failed'; error: string };

// ============================================================================
// Configuration
// ============================================================================

export type SDKConfigurationEvent =
  | { type: 'fetchStarted' }
  | { type: 'fetchCompleted'; source: string }
  | { type: 'fetchFailed'; error: string }
  | { type: 'loaded'; configuration: Record<string, unknown> | null }
  | { type: 'updated'; changes: string[] }
  | { type: 'syncStarted' }
  | { type: 'syncCompleted' }
  | { type: 'syncFailed'; error: string }
  | { type: 'settingsRequested' }
  | { type: 'settingsRetrieved'; settings: DefaultGenerationSettings }
  | { type: 'routingPolicyRequested' }
  | { type: 'routingPolicyRetrieved'; policy: string }
  | { type: 'privacyModeRequested' }
  | { type: 'privacyModeRetrieved'; mode: string }
  | { type: 'analyticsStatusRequested' }
  | { type: 'analyticsStatusRetrieved'; enabled: boolean }
  | { type: 'syncRequested' };

// ============================================================================
// Generation
// ============================================================================

export type SDKGenerationEvent =
  | { type: 'sessionStarted'; sessionId: string }
  | { type: 'sessionEnded'; sessionId: string }
  | { type: 'started'; prompt: string; sessionId?: string }
  | { type: 'firstTokenGenerated'; token: string; latencyMs: number }
  | { type: 'tokenGenerated'; token: string }
  | { type: 'streamingUpdate'; text: string; tokensCount: number }
  | {
      type: 'completed';
      response: string;
      tokensUsed: number;
      latencyMs: number;
    }
  | { type: 'failed'; error: string }
  | { type: 'modelLoaded'; modelId: string }
  | { type: 'modelUnloaded'; modelId: string }
  | { type: 'costCalculated'; amount: number; savedAmount: number }
  | { type: 'routingDecision'; target: string; reason: string };

// ============================================================================
// Model
// ============================================================================

export type SDKModelEvent =
  | { type: 'loadStarted'; modelId: string }
  | { type: 'loadProgress'; modelId: string; progress: number }
  | { type: 'loadCompleted'; modelId: string }
  | { type: 'loadFailed'; modelId: string; error: string }
  | { type: 'unloadStarted' }
  | { type: 'unloadCompleted' }
  | { type: 'unloadFailed'; error: string }
  | { type: 'downloadStarted'; modelId: string; taskId?: string }
  | {
      type: 'downloadProgress';
      modelId: string;
      taskId?: string;
      progress: number;
      bytesDownloaded?: number;
      totalBytes?: number;
      downloadState?: string;
      error?: string;
    }
  | {
      type: 'downloadCompleted';
      modelId: string;
      taskId?: string;
      localPath?: string;
    }
  | { type: 'downloadFailed'; modelId: string; taskId?: string; error: string }
  | { type: 'downloadCancelled'; modelId: string; taskId?: string }
  | { type: 'listRequested' }
  | { type: 'listCompleted'; models: ModelInfo[] }
  | { type: 'listFailed'; error: string }
  | { type: 'catalogLoaded'; models: ModelInfo[] }
  | { type: 'deleteStarted'; modelId: string }
  | { type: 'deleteCompleted'; modelId: string }
  | { type: 'deleteFailed'; modelId: string; error: string }
  | { type: 'customModelAdded'; name: string; url: string }
  | { type: 'builtInModelRegistered'; modelId: string };

// ============================================================================
// Voice (high-level lifecycle)
// ============================================================================

export type SDKVoiceEvent =
  | { type: 'listeningStarted' }
  | { type: 'listeningEnded' }
  | { type: 'speechDetected' }
  | { type: 'transcriptionStarted' }
  | { type: 'transcriptionPartial'; text: string }
  | { type: 'transcriptionFinal'; text: string }
  | { type: 'responseGenerated'; text: string }
  | { type: 'synthesisStarted' }
  | { type: 'audioGenerated'; data: string }
  | { type: 'synthesisCompleted' }
  | { type: 'pipelineError'; error: string }
  | { type: 'pipelineStarted' }
  | { type: 'pipelineCompleted' }
  | { type: 'vadStarted' }
  | { type: 'vadDetected' }
  | { type: 'vadEnded' }
  | { type: 'sttProcessing' }
  | { type: 'llmProcessing' }
  | { type: 'ttsProcessing' }
  // Recording
  | { type: 'recordingStarted' }
  | { type: 'recordingStopped'; duration?: number }
  // Playback
  | { type: 'playbackStarted'; duration?: number }
  | { type: 'playbackCompleted'; duration?: number }
  | { type: 'playbackStopped' }
  | { type: 'playbackPaused' }
  | { type: 'playbackResumed' }
  | { type: 'playbackFailed'; error: string }
  // VAD
  | { type: 'vadInitialized' }
  | { type: 'vadStopped' }
  | { type: 'vadCleanedUp' }
  | { type: 'speechStarted' }
  | { type: 'speechEnded' }
  // STT partials
  | { type: 'sttPartialResult'; text?: string; confidence?: number }
  | { type: 'sttCompleted'; text?: string; confidence?: number }
  | { type: 'sttFailed'; error?: string }
  // Voice session
  | { type: 'voiceSession_started' }
  | { type: 'voiceSession_listening'; audioLevel?: number }
  | { type: 'voiceSession_speechStarted' }
  | { type: 'voiceSession_speechEnded' }
  | { type: 'voiceSession_processing' }
  | { type: 'voiceSession_transcribed'; transcription?: string }
  | { type: 'voiceSession_responded'; response?: string }
  | { type: 'voiceSession_speaking' }
  | {
      type: 'voiceSession_turnCompleted';
      transcription?: string;
      response?: string;
      audio?: string;
    }
  | { type: 'voiceSession_stopped' }
  | { type: 'voiceSession_error'; error?: string };

// ============================================================================
// Performance
// ============================================================================

export type SDKPerformanceEvent =
  | { type: 'memoryWarning'; usage: number }
  | { type: 'thermalStateChanged'; state: string }
  | { type: 'latencyMeasured'; operation: string; milliseconds: number }
  | { type: 'throughputMeasured'; tokensPerSecond: number };

// ============================================================================
// Network
// ============================================================================

export type SDKNetworkEvent =
  | { type: 'requestStarted'; url: string }
  | { type: 'requestCompleted'; url: string; statusCode: number }
  | { type: 'requestFailed'; url: string; error: string }
  | { type: 'connectivityChanged'; isOnline: boolean };

// ============================================================================
// Storage
// ============================================================================

export type SDKStorageEvent =
  | { type: 'infoRequested' }
  | { type: 'infoRetrieved'; info: StorageInfo }
  | { type: 'modelsRequested' }
  | { type: 'modelsRetrieved'; models: StoredModel[] }
  | { type: 'clearCacheStarted' }
  | { type: 'clearCacheCompleted' }
  | { type: 'clearCacheFailed'; error: string }
  | { type: 'cleanTempStarted' }
  | { type: 'cleanTempCompleted' }
  | { type: 'cleanTempFailed'; error: string }
  | { type: 'deleteModelStarted'; modelId: string }
  | { type: 'deleteModelCompleted'; modelId: string }
  | { type: 'deleteModelFailed'; modelId: string; error: string };

// ============================================================================
// Framework
// ============================================================================

export type SDKFrameworkEvent =
  | { type: 'adapterRegistered'; framework: LLMFramework; name: string }
  | { type: 'adaptersRequested' }
  | { type: 'adaptersRetrieved'; count: number }
  | { type: 'frameworksRequested' }
  | { type: 'frameworksRetrieved'; frameworks: LLMFramework[] }
  | { type: 'availabilityRequested' }
  | { type: 'availabilityRetrieved'; availability: FrameworkAvailability[] }
  | { type: 'modelsForFrameworkRequested'; framework: LLMFramework }
  | {
      type: 'modelsForFrameworkRetrieved';
      framework: LLMFramework;
      models: ModelInfo[];
    }
  | { type: 'frameworksForModalityRequested'; modality: string }
  | {
      type: 'frameworksForModalityRetrieved';
      modality: string;
      frameworks: LLMFramework[];
    };

// ============================================================================
// Device
// ============================================================================

export type SDKDeviceEvent =
  | { type: 'deviceInfoCollected'; deviceInfo: DeviceInfoData }
  | { type: 'deviceInfoCollectionFailed'; error: string }
  | { type: 'deviceInfoRefreshed'; deviceInfo: DeviceInfoData }
  | { type: 'deviceInfoSyncStarted' }
  | { type: 'deviceInfoSyncCompleted' }
  | { type: 'deviceInfoSyncFailed'; error: string }
  | { type: 'deviceStateChanged'; property: string; newValue: string };

// ============================================================================
// Component initialization
// ============================================================================

export type ComponentInitializationEvent =
  | { type: 'initializationStarted'; components: SDKComponent[] }
  | { type: 'initializationCompleted'; result: InitializationResult }
  | {
      type: 'componentStateChanged';
      component: SDKComponent;
      oldState: string;
      newState: string;
    }
  | { type: 'componentChecking'; component: SDKComponent; modelId?: string }
  | {
      type: 'componentDownloadRequired';
      component: SDKComponent;
      modelId: string;
      sizeBytes: number;
    }
  | {
      type: 'componentDownloadStarted';
      component: SDKComponent;
      modelId: string;
    }
  | {
      type: 'componentDownloadProgress';
      component: SDKComponent;
      modelId: string;
      progress: number;
    }
  | {
      type: 'componentDownloadCompleted';
      component: SDKComponent;
      modelId: string;
    }
  | { type: 'componentInitializing'; component: SDKComponent; modelId?: string }
  | { type: 'componentReady'; component: SDKComponent; modelId?: string }
  | { type: 'componentFailed'; component: SDKComponent; error: string }
  | { type: 'parallelInitializationStarted'; components: SDKComponent[] }
  | { type: 'sequentialInitializationStarted'; components: SDKComponent[] }
  | { type: 'allComponentsReady' }
  | {
      type: 'someComponentsReady';
      ready: SDKComponent[];
      pending: SDKComponent[];
    };

// ============================================================================
// Union type
// ============================================================================

export type AnySDKEvent =
  | SDKInitializationEvent
  | SDKConfigurationEvent
  | SDKGenerationEvent
  | SDKModelEvent
  | SDKVoiceEvent
  | SDKPerformanceEvent
  | SDKNetworkEvent
  | SDKStorageEvent
  | SDKFrameworkEvent
  | SDKDeviceEvent
  | ComponentInitializationEvent;

// ============================================================================
// Listener helpers
// ============================================================================

export type SDKEventListener<T> = (event: T) => void;

export type UnsubscribeFunction = () => void;
