/**
 * ManagedLifecycle.ts
 *
 * Unified lifecycle management with integrated event tracking.
 * Tracks lifecycle events directly via EventPublisher.
 *
 * Matches iOS: Core/Capabilities/ManagedLifecycle.swift
 */

import type { LoadResourceFn, UnloadResourceFn } from './ModelLifecycleManager';
import { ModelLifecycleManager } from './ModelLifecycleManager';
import type {
  CapabilityLoadingState,
  ComponentConfiguration,
} from './CapabilityProtocols';
import { CapabilityResourceType } from './ResourceTypes';
import {
  createLLMModelLoadStartedEvent,
  createLLMModelLoadCompletedEvent,
  createLLMModelLoadFailedEvent,
  createLLMModelUnloadedEvent,
  createSTTModelLoadStartedEvent,
  createSTTModelLoadCompletedEvent,
  createSTTModelLoadFailedEvent,
  createSTTModelUnloadedEvent,
  createTTSModelLoadStartedEvent,
  createTTSModelLoadCompletedEvent,
  createTTSModelLoadFailedEvent,
  createTTSModelUnloadedEvent,
  createVADModelLoadStartedEvent,
  createVADModelLoadCompletedEvent,
  createVADModelLoadFailedEvent,
  createVADModelUnloadedEvent,
  createSpeakerDiarizationModelLoadStartedEvent,
  createSpeakerDiarizationModelLoadCompletedEvent,
  createSpeakerDiarizationModelLoadFailedEvent,
  createSpeakerDiarizationModelUnloadedEvent,
} from './LifecycleEvents';
import {
  createModelDownloadStartedEvent,
  createModelDownloadCompletedEvent,
  createModelDownloadFailedEvent,
  createModelDeletedEvent,
  createErrorEvent,
} from '../../Infrastructure/Events/CommonEvents';
import { EventPublisher } from '../../Infrastructure/Events/EventPublisher';
import type { SDKEvent } from '../../Infrastructure/Events/SDKEvent';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type { ModelLifecycleMetrics } from './Analytics/CoreAnalyticsTypes';
import { InferenceFrameworkType } from './Analytics/CoreAnalyticsTypes';

// ============================================================================
// ManagedLifecycle Options
// ============================================================================

/**
 * Options for creating a ManagedLifecycle
 */
export interface ManagedLifecycleOptions<TService> {
  /**
   * The underlying lifecycle manager
   */
  lifecycle: ModelLifecycleManager<TService>;

  /**
   * The type of resource being managed
   */
  resourceType: CapabilityResourceType;

  /**
   * Logger category for debug output
   */
  loggerCategory: string;
}

// ============================================================================
// Lifecycle Event Type (Internal)
// ============================================================================

type LifecycleEventType =
  | 'loadStarted'
  | 'loadCompleted'
  | 'loadFailed'
  | 'unloaded';

// ============================================================================
// ManagedLifecycle Class
// ============================================================================

/**
 * Wraps ModelLifecycleManager with integrated event tracking.
 *
 * Lifecycle events (load, unload) are published directly to EventPublisher,
 * which routes them to both public EventBus and Analytics automatically.
 *
 * @example
 * ```typescript
 * // Use factory method to create
 * const lifecycle = ManagedLifecycle.forLLM(llmServiceLoader, llmServiceUnloader);
 *
 * // Load model - events are tracked automatically
 * const service = await lifecycle.load('llama-7b');
 *
 * // Unload - events are tracked automatically
 * await lifecycle.unload();
 * ```
 */
export class ManagedLifecycle<TService> {
  // MARK: - Properties

  private readonly lifecycle: ModelLifecycleManager<TService>;
  private readonly resourceType: CapabilityResourceType;
  private readonly loggerCategory: string;

  // Metrics
  private loadCount = 0;
  private totalLoadTime = 0;
  private failedLoadCount = 0;
  private unloadCount = 0;
  private downloadCount = 0;
  private successfulDownloadCount = 0;
  private failedDownloadCount = 0;
  private totalBytesDownloaded = 0;
  private lastEventTime: Date | null = null;
  private readonly startTime = new Date();
  private framework: InferenceFrameworkType = InferenceFrameworkType.UNKNOWN;

  // MARK: - Initialization

  constructor(options: ManagedLifecycleOptions<TService>) {
    this.lifecycle = options.lifecycle;
    this.resourceType = options.resourceType;
    this.loggerCategory = options.loggerCategory;
  }

  // MARK: - State Properties

  /**
   * Whether a resource is currently loaded
   */
  get isLoaded(): boolean {
    return this.lifecycle.isLoaded;
  }

  /**
   * The currently loaded resource ID
   */
  get currentResourceId(): string | null {
    return this.lifecycle.currentResourceId;
  }

  /**
   * The currently loaded service
   */
  get currentService(): TService | null {
    return this.lifecycle.currentService;
  }

  /**
   * Current loading state
   */
  get state(): CapabilityLoadingState {
    return this.lifecycle.state;
  }

  // MARK: - Configuration

  /**
   * Set configuration for loading
   */
  configure(config: ComponentConfiguration | null): void {
    this.lifecycle.configure(config);
  }

  // MARK: - Lifecycle Operations

  /**
   * Load a resource with automatic event tracking.
   *
   * @param resourceId - The resource identifier
   * @returns The loaded service
   */
  async load(resourceId: string): Promise<TService> {
    const startTime = Date.now();
    this.log(`Loading ${this.resourceType}: ${resourceId}`);

    // Track load started
    this.trackEvent('loadStarted', resourceId);

    try {
      const service = await this.lifecycle.load(resourceId);
      const loadTime = Date.now() - startTime;

      // Track load completed
      this.trackEvent('loadCompleted', resourceId, loadTime);

      // Update metrics
      this.loadCount += 1;
      this.totalLoadTime += loadTime;

      this.log(`Loaded ${this.resourceType}: ${resourceId} in ${loadTime}ms`);
      return service;
    } catch (error) {
      const loadTime = Date.now() - startTime;

      // Track load failed
      this.trackEvent(
        'loadFailed',
        resourceId,
        loadTime,
        error instanceof Error ? error : undefined
      );

      // Update metrics
      this.failedLoadCount += 1;

      this.logError(`Failed to load ${this.resourceType}: ${error}`);
      throw error;
    }
  }

  /**
   * Unload the currently loaded resource.
   */
  async unload(): Promise<void> {
    const resourceId = this.lifecycle.currentResourceId;
    if (resourceId) {
      this.log(`Unloading ${this.resourceType}: ${resourceId}`);
      await this.lifecycle.unload();
      this.trackEvent('unloaded', resourceId);
    } else {
      await this.lifecycle.unload();
    }
  }

  /**
   * Reset all state.
   */
  async reset(): Promise<void> {
    const resourceId = this.lifecycle.currentResourceId;
    if (resourceId) {
      this.trackEvent('unloaded', resourceId);
    }
    await this.lifecycle.reset();
  }

  /**
   * Get service or throw if not loaded.
   */
  requireService(): TService {
    return this.lifecycle.requireService();
  }

  /**
   * Track an operation error.
   */
  trackOperationError(error: Error, operation: string): void {
    const event = createErrorEvent(operation, error.message);
    EventPublisher.shared.track(event);
  }

  /**
   * Get current resource ID with fallback.
   */
  resourceIdOrUnknown(): string {
    return this.lifecycle.currentResourceId ?? 'unknown';
  }

  // MARK: - Metrics

  /**
   * Get lifecycle metrics
   */
  getLifecycleMetrics(): ModelLifecycleMetrics {
    const successfulLoads = this.loadCount - this.failedLoadCount;
    const totalEvents =
      this.loadCount +
      this.unloadCount +
      this.downloadCount;

    return {
      totalEvents,
      startTime: this.startTime,
      lastEventTime: this.lastEventTime,
      totalLoads: this.loadCount,
      successfulLoads,
      failedLoads: this.failedLoadCount,
      averageLoadTimeMs:
        successfulLoads > 0 ? this.totalLoadTime / successfulLoads : -1,
      totalUnloads: this.unloadCount,
      totalDownloads: this.downloadCount,
      successfulDownloads: this.successfulDownloadCount,
      failedDownloads: this.failedDownloadCount,
      totalBytesDownloaded: this.totalBytesDownloaded,
      framework: this.framework,
    };
  }

  /**
   * Set the inference framework type for metrics tracking
   */
  setFramework(framework: InferenceFrameworkType): void {
    this.framework = framework;
  }

  /**
   * Track a download started event
   */
  trackDownloadStarted(): void {
    this.lastEventTime = new Date();
    this.downloadCount += 1;
  }

  /**
   * Track a download completed event
   */
  trackDownloadCompleted(bytesDownloaded: number): void {
    this.lastEventTime = new Date();
    this.successfulDownloadCount += 1;
    this.totalBytesDownloaded += bytesDownloaded;
  }

  /**
   * Track a download failed event
   */
  trackDownloadFailed(): void {
    this.lastEventTime = new Date();
    this.failedDownloadCount += 1;
  }

  // MARK: - Private Event Tracking

  private trackEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): void {
    // Update last event time
    this.lastEventTime = new Date();

    // Update metrics based on event type
    if (type === 'unloaded') {
      this.unloadCount += 1;
    }

    const event = this.createEvent(type, resourceId, durationMs, error);
    EventPublisher.shared.track(event);
  }

  private createEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    switch (this.resourceType) {
      case CapabilityResourceType.LLMModel:
        return this.createLLMEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.STTModel:
        return this.createSTTEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.TTSVoice:
        return this.createTTSEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.VADModel:
        return this.createVADEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.DiarizationModel:
        return this.createSpeakerDiarizationEvent(
          type,
          resourceId,
          durationMs,
          error
        );
      default:
        return this.createModelEvent(type, resourceId, durationMs, error);
    }
  }

  private createLLMEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    switch (type) {
      case 'loadStarted':
        return createLLMModelLoadStartedEvent(resourceId);
      case 'loadCompleted':
        return createLLMModelLoadCompletedEvent(resourceId, durationMs ?? 0);
      case 'loadFailed':
        return createLLMModelLoadFailedEvent(
          resourceId,
          error?.message ?? 'Unknown error'
        );
      case 'unloaded':
        return createLLMModelUnloadedEvent(resourceId);
    }
  }

  private createSTTEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    switch (type) {
      case 'loadStarted':
        return createSTTModelLoadStartedEvent(resourceId);
      case 'loadCompleted':
        return createSTTModelLoadCompletedEvent(resourceId, durationMs ?? 0);
      case 'loadFailed':
        return createSTTModelLoadFailedEvent(
          resourceId,
          error?.message ?? 'Unknown error'
        );
      case 'unloaded':
        return createSTTModelUnloadedEvent(resourceId);
    }
  }

  private createTTSEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    switch (type) {
      case 'loadStarted':
        return createTTSModelLoadStartedEvent(resourceId);
      case 'loadCompleted':
        return createTTSModelLoadCompletedEvent(resourceId, durationMs ?? 0);
      case 'loadFailed':
        return createTTSModelLoadFailedEvent(
          resourceId,
          error?.message ?? 'Unknown error'
        );
      case 'unloaded':
        return createTTSModelUnloadedEvent(resourceId);
    }
  }

  private createVADEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    switch (type) {
      case 'loadStarted':
        return createVADModelLoadStartedEvent(resourceId);
      case 'loadCompleted':
        return createVADModelLoadCompletedEvent(resourceId, durationMs ?? 0);
      case 'loadFailed':
        return createVADModelLoadFailedEvent(
          resourceId,
          error?.message ?? 'Unknown error'
        );
      case 'unloaded':
        return createVADModelUnloadedEvent(resourceId);
    }
  }

  private createSpeakerDiarizationEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    switch (type) {
      case 'loadStarted':
        return createSpeakerDiarizationModelLoadStartedEvent(resourceId);
      case 'loadCompleted':
        return createSpeakerDiarizationModelLoadCompletedEvent(
          resourceId,
          durationMs ?? 0
        );
      case 'loadFailed':
        return createSpeakerDiarizationModelLoadFailedEvent(
          resourceId,
          error?.message ?? 'Unknown error'
        );
      case 'unloaded':
        return createSpeakerDiarizationModelUnloadedEvent(resourceId);
    }
  }

  private createModelEvent(
    type: LifecycleEventType,
    resourceId: string,
    durationMs?: number,
    error?: Error
  ): SDKEvent {
    // Reuse generic model events for VAD/Diarization
    switch (type) {
      case 'loadStarted':
        return createModelDownloadStartedEvent(resourceId);
      case 'loadCompleted':
        return createModelDownloadCompletedEvent(
          resourceId,
          durationMs ?? 0,
          0
        );
      case 'loadFailed':
        return createModelDownloadFailedEvent(
          resourceId,
          error?.message ?? 'Unknown error'
        );
      case 'unloaded':
        return createModelDeletedEvent(resourceId);
    }
  }

  // MARK: - Private Helpers

  private log(message: string): void {
    const logger = new SDKLogger(this.loggerCategory);
    logger.debug(message);
  }

  private logError(message: string): void {
    const logger = new SDKLogger(this.loggerCategory);
    logger.error(message);
  }

  // ============================================================================
  // Factory Methods
  // ============================================================================

  /**
   * Create a ManagedLifecycle for LLM capabilities.
   *
   * @param loadResource - Function to load LLM service
   * @param unloadResource - Function to unload LLM service
   */
  static forLLM<TService>(
    loadResource: LoadResourceFn<TService>,
    unloadResource: UnloadResourceFn<TService>
  ): ManagedLifecycle<TService> {
    const lifecycle = new ModelLifecycleManager<TService>({
      category: 'LLM.Lifecycle',
      loadResource,
      unloadResource,
    });

    return new ManagedLifecycle({
      lifecycle,
      resourceType: CapabilityResourceType.LLMModel,
      loggerCategory: 'LLM.Lifecycle',
    });
  }

  /**
   * Create a ManagedLifecycle for STT capabilities.
   *
   * @param loadResource - Function to load STT service
   * @param unloadResource - Function to unload STT service
   */
  static forSTT<TService>(
    loadResource: LoadResourceFn<TService>,
    unloadResource: UnloadResourceFn<TService>
  ): ManagedLifecycle<TService> {
    const lifecycle = new ModelLifecycleManager<TService>({
      category: 'STT.Lifecycle',
      loadResource,
      unloadResource,
    });

    return new ManagedLifecycle({
      lifecycle,
      resourceType: CapabilityResourceType.STTModel,
      loggerCategory: 'STT.Lifecycle',
    });
  }

  /**
   * Create a ManagedLifecycle for TTS capabilities.
   *
   * @param loadResource - Function to load TTS service
   * @param unloadResource - Function to unload TTS service
   */
  static forTTS<TService>(
    loadResource: LoadResourceFn<TService>,
    unloadResource: UnloadResourceFn<TService>
  ): ManagedLifecycle<TService> {
    const lifecycle = new ModelLifecycleManager<TService>({
      category: 'TTS.Lifecycle',
      loadResource,
      unloadResource,
    });

    return new ManagedLifecycle({
      lifecycle,
      resourceType: CapabilityResourceType.TTSVoice,
      loggerCategory: 'TTS.Lifecycle',
    });
  }

  /**
   * Create a ManagedLifecycle for VAD capabilities.
   *
   * @param loadResource - Function to load VAD service
   * @param unloadResource - Function to unload VAD service
   */
  static forVAD<TService>(
    loadResource: LoadResourceFn<TService>,
    unloadResource: UnloadResourceFn<TService>
  ): ManagedLifecycle<TService> {
    const lifecycle = new ModelLifecycleManager<TService>({
      category: 'VAD.Lifecycle',
      loadResource,
      unloadResource,
    });

    return new ManagedLifecycle({
      lifecycle,
      resourceType: CapabilityResourceType.VADModel,
      loggerCategory: 'VAD.Lifecycle',
    });
  }

  /**
   * Create a ManagedLifecycle for SpeakerDiarization capabilities.
   *
   * @param loadResource - Function to load SpeakerDiarization service
   * @param unloadResource - Function to unload SpeakerDiarization service
   */
  static forSpeakerDiarization<TService>(
    loadResource: LoadResourceFn<TService>,
    unloadResource: UnloadResourceFn<TService>
  ): ManagedLifecycle<TService> {
    const lifecycle = new ModelLifecycleManager<TService>({
      category: 'SpeakerDiarization.Lifecycle',
      loadResource,
      unloadResource,
    });

    return new ManagedLifecycle({
      lifecycle,
      resourceType: CapabilityResourceType.DiarizationModel,
      loggerCategory: 'SpeakerDiarization.Lifecycle',
    });
  }
}
