/**
 * RunAnywhere React Native SDK - Event Types
 *
 * These event types match the iOS Swift SDK event system.
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Events/SDKEvent.swift
 */

import type { LLMFramework, SDKComponent, SDKEventType } from './enums';
import type {
  DefaultGenerationSettings,
  DeviceInfoData,
  FrameworkAvailability,
  InitializationResult,
  ModelInfo,
  StorageInfo,
  StoredModel,
} from './models';

// ============================================================================
// Base Event Interface
// ============================================================================

/**
 * Base interface for all SDK events
 */
export interface SDKEvent {
  /** Event timestamp */
  timestamp: string;

  /** Event type category */
  eventType: SDKEventType;
}

// ============================================================================
// Initialization Events
// ============================================================================

export type SDKInitializationEvent =
  | { type: 'started' }
  | { type: 'configurationLoaded'; source: string }
  | { type: 'servicesBootstrapped' }
  | { type: 'completed' }
  | { type: 'failed'; error: string };

// ============================================================================
// Configuration Events
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
// Generation Events
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
// Model Events
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
// Voice Events
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
  | { type: 'audioGenerated'; data: string } // base64 encoded
  | { type: 'synthesisCompleted' }
  | { type: 'pipelineError'; error: string }
  | { type: 'pipelineStarted' }
  | { type: 'pipelineCompleted' }
  | { type: 'vadStarted' }
  | { type: 'vadDetected' }
  | { type: 'vadEnded' }
  | { type: 'sttProcessing' }
  | { type: 'llmProcessing' }
  | { type: 'ttsProcessing' };

// ============================================================================
// Performance Events
// ============================================================================

export type SDKPerformanceEvent =
  | { type: 'memoryWarning'; usage: number }
  | { type: 'thermalStateChanged'; state: string }
  | { type: 'latencyMeasured'; operation: string; milliseconds: number }
  | { type: 'throughputMeasured'; tokensPerSecond: number };

// ============================================================================
// Network Events
// ============================================================================

export type SDKNetworkEvent =
  | { type: 'requestStarted'; url: string }
  | { type: 'requestCompleted'; url: string; statusCode: number }
  | { type: 'requestFailed'; url: string; error: string }
  | { type: 'connectivityChanged'; isOnline: boolean };

// ============================================================================
// Storage Events
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
// Framework Events
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
// Device Events
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
// Component Initialization Events
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
// Union Type for All Events
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
// Event Listener Types
// ============================================================================

export type SDKEventListener<T> = (event: T) => void;

export type UnsubscribeFunction = () => void;
