/**
 * STTAnalyticsService.ts
 *
 * STT-specific analytics service with event tracking and batch submission
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Analytics/STT/STTAnalyticsService.swift
 */

import type {
  AnalyticsContext,
  AnalyticsEvent,
  ErrorEventData,
  FinalTranscriptData,
  LanguageDetectionData,
  PartialTranscriptData,
  SessionMetadata,
  SpeakerChangeData,
  SpeakerDetectionData,
  STTMetrics,
  STTTranscriptionData,
  TranscriptionStartData,
} from '../../../types/analytics';
import { STTEventType } from '../../../types/analytics';
import { AnalyticsQueueManager } from '../AnalyticsQueueManager';

/**
 * STT-specific analytics event
 */
interface STTEvent extends AnalyticsEvent {
  type: string;
}

/**
 * Session information
 */
interface SessionInfo {
  id: string;
  modelId?: string;
  startTime: Date;
}

/**
 * STT analytics service
 */
export class STTAnalyticsService {
  private static sharedInstance: STTAnalyticsService | null = null;
  private queueManager: AnalyticsQueueManager;
  private currentSession: SessionInfo | null = null;
  private events: STTEvent[] = [];

  // Metrics tracking
  private metricsStartTime: Date = new Date();
  private transcriptionCount: number = 0;
  private totalConfidence: number = 0;
  private totalLatency: number = 0;

  /**
   * Get shared instance
   */
  public static get shared(): STTAnalyticsService {
    if (!STTAnalyticsService.sharedInstance) {
      STTAnalyticsService.sharedInstance = new STTAnalyticsService();
    }
    return STTAnalyticsService.sharedInstance;
  }

  private constructor(queueManager?: AnalyticsQueueManager) {
    this.queueManager = queueManager || AnalyticsQueueManager.shared;
  }

  /**
   * Track an event
   */
  public async track(event: STTEvent): Promise<void> {
    this.events.push(event);
    await this.queueManager.enqueue(event);
    await this.processEvent(event);
  }

  /**
   * Track a batch of events
   */
  public async trackBatch(events: STTEvent[]): Promise<void> {
    this.events.push(...events);
    await this.queueManager.enqueueBatch(events);
    for (const event of events) {
      await this.processEvent(event);
    }
  }

  /**
   * Get metrics
   */
  public getMetrics(): STTMetrics {
    return {
      totalEvents: this.events.length,
      startTime: this.metricsStartTime,
      lastEventTime:
        this.events.length > 0
          ? this.events[this.events.length - 1].timestamp
          : undefined,
      totalTranscriptions: this.transcriptionCount,
      averageConfidence:
        this.transcriptionCount > 0
          ? this.totalConfidence / this.transcriptionCount
          : 0,
      averageLatency:
        this.transcriptionCount > 0
          ? this.totalLatency / this.transcriptionCount
          : 0,
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

  // MARK: - STT-Specific Methods

  /**
   * Track transcription started
   */
  public async trackTranscriptionStarted(audioLength: number): Promise<void> {
    const eventData: TranscriptionStartData = {
      audioLengthMs: audioLength,
      startTimestamp: Date.now(),
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.TRANSCRIPTION_STARTED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track transcription completion
   */
  public async trackTranscription(
    text: string,
    confidence: number,
    duration: number,
    audioLength: number,
    speaker?: string
  ): Promise<void> {
    const wordCount = text
      .split(/\s+/)
      .filter((word) => word.length > 0).length;

    const eventData: STTTranscriptionData = {
      wordCount,
      confidence,
      durationMs: duration * 1000,
      audioLengthMs: audioLength * 1000,
      realTimeFactor: audioLength > 0 ? duration / audioLength : 0,
      speakerId: speaker || 'unknown',
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.TRANSCRIPTION_COMPLETED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);

    // Update metrics
    this.transcriptionCount++;
    this.totalConfidence += confidence;
    this.totalLatency += duration;
  }

  /**
   * Track final transcript
   */
  public async trackFinalTranscript(
    text: string,
    confidence: number,
    speaker?: string
  ): Promise<void> {
    const wordCount = text
      .split(/\s+/)
      .filter((word) => word.length > 0).length;

    const eventData: FinalTranscriptData = {
      textLength: text.length,
      wordCount,
      confidence,
      speakerId: speaker || 'unknown',
      timestamp: Date.now(),
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.FINAL_TRANSCRIPT,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track partial transcript
   */
  public async trackPartialTranscript(text: string): Promise<void> {
    const wordCount = text
      .split(/\s+/)
      .filter((word) => word.length > 0).length;

    const eventData: PartialTranscriptData = {
      textLength: text.length,
      wordCount,
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.PARTIAL_TRANSCRIPT,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track speaker detection
   */
  public async trackSpeakerDetection(
    speaker: string,
    confidence: number
  ): Promise<void> {
    const eventData: SpeakerDetectionData = {
      speakerId: speaker,
      confidence,
      timestamp: Date.now(),
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.SPEAKER_DETECTED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track speaker change
   */
  public async trackSpeakerChange(
    from: string | null,
    to: string
  ): Promise<void> {
    const eventData: SpeakerChangeData = {
      fromSpeaker: from || 'none',
      toSpeaker: to,
      timestamp: Date.now(),
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.SPEAKER_CHANGED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track language detection
   */
  public async trackLanguageDetection(
    language: string,
    confidence: number
  ): Promise<void> {
    const eventData: LanguageDetectionData = {
      language,
      confidence,
    };

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.LANGUAGE_DETECTED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
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

    const event: STTEvent = {
      id: this.generateEventId(),
      type: STTEventType.ERROR,
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
  private async processEvent(_event: STTEvent): Promise<void> {
    // Custom processing for STT events if needed
    // This is called after each event is tracked
  }

  /**
   * Generate unique event ID
   */
  private generateEventId(): string {
    return `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
  }
}
