/**
 * AnalyticsQueueManager.ts
 *
 * Centralized queue management for all analytics events with batching and retry
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Analytics/AnalyticsQueueManager.swift
 */

/**
 * Analytics event interface
 */
export interface AnalyticsEvent {
  readonly type: string;
  readonly eventData: any;
  readonly timestamp: Date;
}

/**
 * Central queue for all analytics - handles batching and retry logic
 */
export class AnalyticsQueueManager {
  private static sharedInstance: AnalyticsQueueManager | null = null;
  private eventQueue: AnalyticsEvent[] = [];
  private readonly batchSize: number = 50;
  private readonly flushInterval: number = 30 * 1000; // 30 seconds in ms
  private telemetryRepository: any | null = null;
  private flushTimer: NodeJS.Timeout | null = null;
  private readonly maxRetries: number = 3;

  /**
   * Get shared instance
   */
  public static get shared(): AnalyticsQueueManager {
    if (!AnalyticsQueueManager.sharedInstance) {
      AnalyticsQueueManager.sharedInstance = new AnalyticsQueueManager();
    }
    return AnalyticsQueueManager.sharedInstance;
  }

  private constructor() {
    this.startFlushTimer();
  }

  /**
   * Initialize with telemetry repository
   */
  public initialize(telemetryRepository: any): void {
    this.telemetryRepository = telemetryRepository;
  }

  /**
   * Enqueue an event
   */
  public async enqueue(event: AnalyticsEvent): Promise<void> {
    this.eventQueue.push(event);

    if (this.eventQueue.length >= this.batchSize) {
      await this.flushBatch();
    }
  }

  /**
   * Enqueue a batch of events
   */
  public async enqueueBatch(events: AnalyticsEvent[]): Promise<void> {
    this.eventQueue.push(...events);

    if (this.eventQueue.length >= this.batchSize) {
      await this.flushBatch();
    }
  }

  /**
   * Force flush all pending events
   */
  public async flush(): Promise<void> {
    await this.flushBatch();
  }

  /**
   * Start flush timer
   */
  private startFlushTimer(): void {
    this.flushTimer = setInterval(() => {
      this.flushBatch();
    }, this.flushInterval);
  }

  /**
   * Flush batch
   */
  private async flushBatch(): Promise<void> {
    if (this.eventQueue.length === 0) {
      return;
    }

    const batch = this.eventQueue.splice(0, this.batchSize);
    await this.processBatch(batch);
  }

  /**
   * Process batch
   */
  private async processBatch(batch: AnalyticsEvent[]): Promise<void> {
    if (!this.telemetryRepository) {
      // Events will be dropped if no repository configured
      return;
    }

    // Convert to telemetry events
    const telemetryEvents = batch.map((event) => {
      // Extract properties from event data
      const properties: { [key: string]: string } = {};

      // Convert event data to properties
      if (event.eventData) {
        for (const [key, value] of Object.entries(event.eventData)) {
          if (value !== null && value !== undefined) {
            properties[this.camelToSnake(key)] = String(value);
          }
        }
      }

      return {
        eventType: event.type,
        properties,
        timestamp: event.timestamp,
      };
    });

    // Store and send to backend
    let success = false;
    let attempt = 0;

    while (attempt < this.maxRetries && !success) {
      try {
        // Store locally first
        // await this.telemetryRepository.store(telemetryEvents);

        // Send to backend
        // await this.telemetryRepository.send(telemetryEvents);

        success = true;
      } catch (error) {
        attempt++;
        if (attempt >= this.maxRetries) {
          // Failed after max retries - events will be lost
          // In production, might want to persist to local storage for retry later
        }
      }
    }
  }

  /**
   * Convert camelCase to snake_case
   */
  private camelToSnake(str: string): string {
    return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
  }
}
