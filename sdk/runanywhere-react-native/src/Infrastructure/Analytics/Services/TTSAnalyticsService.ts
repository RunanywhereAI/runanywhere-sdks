/**
 * TTSAnalyticsService.ts
 *
 * TTS-specific analytics service with event tracking and batch submission
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Analytics/TTS/TTSAnalyticsService.swift
 */

import type {
  AnalyticsContext,
  AnalyticsEvent,
  ErrorEventData,
  SessionMetadata,
  TTSMetrics,
  TTSSynthesisCompletionData,
  TTSSynthesisStartData,
} from '../../../types/analytics';
import { TTSEventType } from '../../../types/analytics';
import { AnalyticsQueueManager } from '../AnalyticsQueueManager';

/**
 * TTS-specific analytics event
 */
interface TTSEvent extends AnalyticsEvent {
  type: string;
}

/**
 * Session information
 */
interface SessionInfo {
  id: string;
  modelId?: string;
  voice?: string;
  startTime: Date;
}

/**
 * TTS analytics service
 */
export class TTSAnalyticsService {
  private static sharedInstance: TTSAnalyticsService | null = null;
  private queueManager: AnalyticsQueueManager;
  private currentSession: SessionInfo | null = null;
  private events: TTSEvent[] = [];

  // Metrics tracking
  private metricsStartTime: Date = new Date();
  private synthesisCount: number = 0;
  private totalCharacters: number = 0;
  private totalProcessingTime: number = 0;
  private totalCharactersPerSecond: number = 0;

  /**
   * Get shared instance
   */
  public static get shared(): TTSAnalyticsService {
    if (!TTSAnalyticsService.sharedInstance) {
      TTSAnalyticsService.sharedInstance = new TTSAnalyticsService();
    }
    return TTSAnalyticsService.sharedInstance;
  }

  private constructor(queueManager?: AnalyticsQueueManager) {
    this.queueManager = queueManager || AnalyticsQueueManager.shared;
  }

  /**
   * Track an event
   */
  public async track(event: TTSEvent): Promise<void> {
    this.events.push(event);
    await this.queueManager.enqueue(event);
    await this.processEvent(event);
  }

  /**
   * Track a batch of events
   */
  public async trackBatch(events: TTSEvent[]): Promise<void> {
    this.events.push(...events);
    await this.queueManager.enqueueBatch(events);
    for (const event of events) {
      await this.processEvent(event);
    }
  }

  /**
   * Get metrics
   */
  public getMetrics(): TTSMetrics {
    return {
      totalEvents: this.events.length,
      startTime: this.metricsStartTime,
      lastEventTime:
        this.events.length > 0
          ? this.events[this.events.length - 1].timestamp
          : undefined,
      totalSyntheses: this.synthesisCount,
      averageCharactersPerSecond:
        this.synthesisCount > 0
          ? this.totalCharactersPerSecond / this.synthesisCount
          : 0,
      averageProcessingTimeMs:
        this.synthesisCount > 0
          ? this.totalProcessingTime / this.synthesisCount
          : 0,
      totalCharactersProcessed: this.totalCharacters,
    };
  }

  /**
   * Clear old metrics
   */
  public clearMetrics(olderThan: Date): void {
    this.events = this.events.filter((event) => event.timestamp >= olderThan);
  }

  /**
   * Start a session
   */
  public startSession(metadata: SessionMetadata): string {
    this.currentSession = {
      id: metadata.id,
      modelId: metadata.modelId,
      startTime: new Date(),
    };
    return metadata.id;
  }

  /**
   * End a session
   */
  public endSession(sessionId: string): void {
    if (this.currentSession?.id === sessionId) {
      this.currentSession = null;
    }
  }

  /**
   * Check health
   */
  public isHealthy(): boolean {
    return true;
  }

  // MARK: - TTS-Specific Methods

  /**
   * Track synthesis started
   */
  public async trackSynthesisStarted(
    text: string,
    voice: string,
    language: string
  ): Promise<void> {
    const eventData: TTSSynthesisStartData = {
      characterCount: text.length,
      voice,
      language,
      startTimestamp: Date.now(),
    };

    const event: TTSEvent = {
      id: this.generateEventId(),
      type: TTSEventType.SYNTHESIS_STARTED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track synthesis completed
   */
  public async trackSynthesisCompleted(
    characterCount: number,
    audioDurationMs: number,
    audioSizeBytes: number,
    processingTimeMs: number
  ): Promise<void> {
    const charactersPerSecond =
      processingTimeMs > 0 ? (characterCount / processingTimeMs) * 1000 : 0;
    const realTimeFactor =
      audioDurationMs > 0 ? processingTimeMs / audioDurationMs : 0;

    const eventData: TTSSynthesisCompletionData = {
      characterCount,
      audioDurationMs,
      audioSizeBytes,
      processingTimeMs,
      charactersPerSecond,
      realTimeFactor,
    };

    const event: TTSEvent = {
      id: this.generateEventId(),
      type: TTSEventType.SYNTHESIS_COMPLETED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);

    // Update metrics
    this.synthesisCount++;
    this.totalCharacters += characterCount;
    this.totalProcessingTime += processingTimeMs;
    this.totalCharactersPerSecond += charactersPerSecond;
  }

  /**
   * Track synthesis with all parameters
   */
  public async trackSynthesis(
    text: string,
    voice: string,
    language: string,
    audioDurationMs: number,
    audioSizeBytes: number,
    processingTimeMs: number
  ): Promise<void> {
    // Track start
    await this.trackSynthesisStarted(text, voice, language);

    // Track completion
    await this.trackSynthesisCompleted(
      text.length,
      audioDurationMs,
      audioSizeBytes,
      processingTimeMs
    );
  }

  /**
   * Track error
   */
  public async trackError(
    error: Error,
    context: AnalyticsContext
  ): Promise<void> {
    const eventData: ErrorEventData = {
      error: error.message,
      context: context.toString(),
      timestamp: Date.now(),
    };

    const event: TTSEvent = {
      id: this.generateEventId(),
      type: TTSEventType.ERROR,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  // MARK: - Private Methods

  /**
   * Process event for custom analytics
   */
  private async processEvent(_event: TTSEvent): Promise<void> {
    // Custom processing for TTS events if needed
    // This is called after each event is tracked
  }

  /**
   * Generate unique event ID
   */
  private generateEventId(): string {
    return `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
  }
}
