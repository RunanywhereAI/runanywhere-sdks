/**
 * LLMAnalyticsService.ts
 *
 * LLM/Generation-specific analytics service with event tracking and batch submission
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Analytics/Generation/GenerationAnalyticsService.swift
 */

import type {
  AnalyticsContext,
  AnalyticsEvent,
  ErrorEventData,
  FirstTokenData,
  GenerationCompletionData,
  GenerationMetrics,
  GenerationStartData,
  ModelLoadingData,
  ModelUnloadingData,
  SessionEndedData,
  SessionMetadata,
  SessionStartedData,
  StreamingUpdateData,
} from '../../../types/analytics';
import { GenerationEventType } from '../../../types/analytics';
import { AnalyticsQueueManager } from '../AnalyticsQueueManager';

/**
 * Generation-specific analytics event
 */
interface GenerationEvent extends AnalyticsEvent {
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
 * Generation tracker
 */
interface GenerationTracker {
  id: string;
  startTime: Date;
  firstTokenTime?: Date;
  endTime?: Date;
  inputTokens: number;
  outputTokens: number;
}

/**
 * LLM/Generation analytics service
 */
export class LLMAnalyticsService {
  private static sharedInstance: LLMAnalyticsService | null = null;
  private queueManager: AnalyticsQueueManager;
  private currentSession: SessionInfo | null = null;
  private events: GenerationEvent[] = [];

  // Metrics tracking
  private metricsStartTime: Date = new Date();
  private totalGenerations: number = 0;
  private totalTimeToFirstToken: number = 0;
  private totalTokensPerSecond: number = 0;
  private totalInputTokens: number = 0;
  private totalOutputTokens: number = 0;

  // Generation tracking
  private activeGenerations: Map<string, GenerationTracker> = new Map();

  /**
   * Get shared instance
   */
  public static get shared(): LLMAnalyticsService {
    if (!LLMAnalyticsService.sharedInstance) {
      LLMAnalyticsService.sharedInstance = new LLMAnalyticsService();
    }
    return LLMAnalyticsService.sharedInstance;
  }

  private constructor(queueManager?: AnalyticsQueueManager) {
    this.queueManager = queueManager || AnalyticsQueueManager.shared;
  }

  /**
   * Track an event
   */
  public async track(event: GenerationEvent): Promise<void> {
    this.events.push(event);
    await this.queueManager.enqueue(event);
    await this.processEvent(event);
  }

  /**
   * Track a batch of events
   */
  public async trackBatch(events: GenerationEvent[]): Promise<void> {
    this.events.push(...events);
    await this.queueManager.enqueueBatch(events);
    for (const event of events) {
      await this.processEvent(event);
    }
  }

  /**
   * Get metrics
   */
  public getMetrics(): GenerationMetrics {
    return {
      totalEvents: this.events.length,
      startTime: this.metricsStartTime,
      lastEventTime:
        this.events.length > 0
          ? this.events[this.events.length - 1].timestamp
          : undefined,
      totalGenerations: this.totalGenerations,
      averageTimeToFirstToken:
        this.totalGenerations > 0
          ? this.totalTimeToFirstToken / this.totalGenerations
          : 0,
      averageTokensPerSecond:
        this.totalGenerations > 0
          ? this.totalTokensPerSecond / this.totalGenerations
          : 0,
      totalInputTokens: this.totalInputTokens,
      totalOutputTokens: this.totalOutputTokens,
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

  // MARK: - LLM-Specific Methods

  /**
   * Start tracking a new generation
   */
  public async startGeneration(
    modelId: string,
    executionTarget: string,
    generationId?: string
  ): Promise<string> {
    const id = generationId || this.generateEventId();

    const tracker: GenerationTracker = {
      id,
      startTime: new Date(),
      inputTokens: 0,
      outputTokens: 0,
    };

    this.activeGenerations.set(id, tracker);

    const eventData: GenerationStartData = {
      generationId: id,
      modelId,
      executionTarget,
      promptTokens: 0, // Will be updated when available
      maxTokens: 0, // Will be updated when available
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.GENERATION_STARTED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
    return id;
  }

  /**
   * Track first token generation
   */
  public async trackFirstToken(generationId: string): Promise<void> {
    const tracker = this.activeGenerations.get(generationId);
    if (!tracker) {
      return;
    }

    tracker.firstTokenTime = new Date();
    this.activeGenerations.set(generationId, tracker);

    const timeToFirstToken =
      tracker.firstTokenTime.getTime() - tracker.startTime.getTime();

    const eventData: FirstTokenData = {
      generationId,
      timeToFirstTokenMs: timeToFirstToken,
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.FIRST_TOKEN_GENERATED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Complete a generation with performance metrics
   */
  public async completeGeneration(
    generationId: string,
    inputTokens: number,
    outputTokens: number,
    modelId: string,
    executionTarget: string
  ): Promise<void> {
    const tracker = this.activeGenerations.get(generationId);
    if (!tracker) {
      return;
    }

    tracker.endTime = new Date();
    tracker.inputTokens = inputTokens;
    tracker.outputTokens = outputTokens;

    const totalTime = tracker.endTime.getTime() - tracker.startTime.getTime();
    const timeToFirstToken = tracker.firstTokenTime
      ? tracker.firstTokenTime.getTime() - tracker.startTime.getTime()
      : 0;
    const tokensPerSecond =
      totalTime > 0 ? (outputTokens / totalTime) * 1000 : 0;

    // Update metrics
    this.totalGenerations++;
    this.totalTimeToFirstToken += timeToFirstToken;
    this.totalTokensPerSecond += tokensPerSecond;
    this.totalInputTokens += inputTokens;
    this.totalOutputTokens += outputTokens;

    const eventData: GenerationCompletionData = {
      generationId,
      modelId,
      executionTarget,
      inputTokens,
      outputTokens,
      totalTimeMs: totalTime,
      timeToFirstTokenMs: timeToFirstToken,
      tokensPerSecond,
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.GENERATION_COMPLETED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);

    // Clean up tracker
    this.activeGenerations.delete(generationId);
  }

  /**
   * Track streaming update
   */
  public async trackStreamingUpdate(
    generationId: string,
    tokensGenerated: number
  ): Promise<void> {
    const eventData: StreamingUpdateData = {
      generationId,
      tokensGenerated,
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.STREAMING_UPDATE,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track model loading
   */
  public async trackModelLoading(
    modelId: string,
    loadTime: number,
    success: boolean,
    errorCode?: string
  ): Promise<void> {
    const eventData: ModelLoadingData = {
      modelId,
      loadTimeMs: loadTime * 1000,
      success,
      errorCode,
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.MODEL_LOADED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Track model unloading
   */
  public async trackModelUnloading(modelId: string): Promise<void> {
    const eventData: ModelUnloadingData = {
      modelId,
      timestamp: Date.now(),
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.MODEL_UNLOADED,
      timestamp: new Date(),
      sessionId: this.currentSession?.id,
      eventData,
    };

    await this.track(event);
  }

  /**
   * Start a generation session
   */
  public async startGenerationSession(
    modelId: string,
    type: string = 'text'
  ): Promise<string> {
    const metadata: SessionMetadata = {
      id: this.generateEventId(),
      modelId,
      type,
    };

    const sessionId = this.startSession(metadata);

    const eventData: SessionStartedData = {
      modelId,
      sessionType: type,
      timestamp: Date.now(),
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.SESSION_STARTED,
      timestamp: new Date(),
      sessionId,
      eventData,
    };

    await this.track(event);
    return sessionId;
  }

  /**
   * End a generation session
   */
  public async endGenerationSession(sessionId: string): Promise<void> {
    const sessionDuration = this.currentSession
      ? Date.now() - this.currentSession.startTime.getTime()
      : 0;

    this.endSession(sessionId);

    const eventData: SessionEndedData = {
      sessionId,
      duration: sessionDuration,
      timestamp: Date.now(),
    };

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.SESSION_ENDED,
      timestamp: new Date(),
      sessionId,
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

    const event: GenerationEvent = {
      id: this.generateEventId(),
      type: GenerationEventType.ERROR,
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
  private async processEvent(_event: GenerationEvent): Promise<void> {
    // Custom processing for generation events if needed
  }

  /**
   * Generate unique event ID
   */
  private generateEventId(): string {
    return `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
  }
}
