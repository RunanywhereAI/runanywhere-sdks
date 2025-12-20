/**
 * AnalyticsQueueManager.ts
 *
 * Centralized queue management for all analytics events with batching and retry
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Analytics/Services/AnalyticsQueueManager.swift
 */

import type { AnalyticsEvent, TelemetryData } from '../../types/analytics';
import type { APIClient } from '../../Data/Network/Services/APIClient';
import { analyticsEndpointForEnvironment } from '../../Data/Network/APIEndpoint';
import { SDKEnvironment } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AnalyticsQueueManager');

const STORAGE_KEY = '@runanywhere:analytics_queue';

/**
 * Storage interface for platform-agnostic persistence
 */
interface Storage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/**
 * In-memory storage fallback
 */
class InMemoryStorage implements Storage {
  private storage = new Map<string, string>();

  async getItem(key: string): Promise<string | null> {
    return this.storage.get(key) || null;
  }

  async setItem(key: string, value: string): Promise<void> {
    this.storage.set(key, value);
  }

  async removeItem(key: string): Promise<void> {
    this.storage.delete(key);
  }
}

/**
 * Central queue for all analytics - handles batching and retry logic
 */
export class AnalyticsQueueManager {
  private static sharedInstance: AnalyticsQueueManager | null = null;
  private eventQueue: AnalyticsEvent[] = [];
  private readonly batchSize: number = 50;
  private readonly flushInterval: number = 30 * 1000; // 30 seconds in ms
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- TelemetryRepository type not yet defined
  private telemetryRepository: any | null = null;
  private flushTimer: NodeJS.Timeout | null = null;
  private readonly maxRetries: number = 3;
  private isProcessing: boolean = false;
  private storage: Storage = new InMemoryStorage();

  /**
   * API client for sending analytics events to backend
   * Matches iOS pattern of using APIClient via RemoteTelemetryDataSource
   */
  private _apiClient: APIClient | null = null;

  /**
   * SDK environment for endpoint selection
   */
  private _environment: SDKEnvironment = SDKEnvironment.Development;

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
    this.loadPersistedEvents();
  }

  /**
   * Initialize with telemetry repository and optional storage
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- TelemetryRepository type not yet defined
  public initialize(telemetryRepository: any, storage?: Storage): void {
    this.telemetryRepository = telemetryRepository;
    if (storage) {
      this.storage = storage;
    }
  }

  /**
   * Set the API client for sending analytics to backend
   *
   * This is called by ServiceContainer during SDK initialization.
   * Matches iOS pattern where RemoteTelemetryDataSource receives APIClient.
   *
   * @param apiClient - The APIClient instance for HTTP requests
   * @param environment - SDK environment for endpoint selection
   */
  public setAPIClient(apiClient: APIClient, environment: SDKEnvironment): void {
    this._apiClient = apiClient;
    this._environment = environment;
  }

  /**
   * Set custom storage implementation
   */
  public setStorage(storage: Storage): void {
    this.storage = storage;
  }

  /**
   * Enqueue an event
   */
  public async enqueue(event: AnalyticsEvent): Promise<void> {
    this.eventQueue.push(event);
    await this.persistQueue();

    if (this.eventQueue.length >= this.batchSize) {
      await this.flushBatch();
    }
  }

  /**
   * Enqueue a batch of events
   */
  public async enqueueBatch(events: AnalyticsEvent[]): Promise<void> {
    this.eventQueue.push(...events);
    await this.persistQueue();

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
    if (this.flushTimer) {
      clearInterval(this.flushTimer);
    }

    this.flushTimer = setInterval(() => {
      this.flushBatch().catch((error) => {
        console.warn('[AnalyticsQueue] Failed to flush batch:', error);
      });
    }, this.flushInterval);
  }

  /**
   * Stop flush timer
   */
  public stopFlushTimer(): void {
    if (this.flushTimer) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
  }

  /**
   * Flush batch
   */
  private async flushBatch(): Promise<void> {
    if (this.eventQueue.length === 0 || this.isProcessing) {
      return;
    }

    this.isProcessing = true;

    try {
      const batch = this.eventQueue.splice(0, this.batchSize);
      await this.processBatch(batch);
      await this.persistQueue();
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * Process batch with retry logic
   */
  private async processBatch(batch: AnalyticsEvent[]): Promise<void> {
    // Check if we have either an API client or a telemetry repository
    if (!this._apiClient && !this.telemetryRepository) {
      console.warn(
        '[AnalyticsQueue] No API client or telemetry repository configured - events will be dropped'
      );
      return;
    }

    // Convert to telemetry events
    const telemetryEvents = batch.map((event) =>
      this.convertToTelemetryEvent(event)
    );

    let success = false;
    let attempt = 0;

    while (attempt < this.maxRetries && !success) {
      try {
        // Send to backend
        await this.sendBatch(telemetryEvents);
        success = true;
      } catch (error) {
        attempt++;
        console.warn(
          `[AnalyticsQueue] Failed to process batch (attempt ${attempt}/${this.maxRetries}):`,
          error
        );

        if (attempt < this.maxRetries) {
          // Exponential backoff
          const delay = Math.pow(2, attempt) * 1000;
          await this.sleep(delay);
        } else {
          console.error(
            `[AnalyticsQueue] Failed to send batch after ${this.maxRetries} attempts, events stored locally for later sync`
          );
          // Re-queue the events for later
          this.eventQueue.unshift(...batch);
          await this.persistQueue();
        }
      }
    }
  }

  /**
   * Convert analytics event to telemetry event
   */
  private convertToTelemetryEvent(event: AnalyticsEvent): TelemetryData {
    const properties: Record<string, string> = {};

    // Convert event data to properties
    if (event.eventData) {
      for (const [key, value] of Object.entries(event.eventData)) {
        if (value !== null && value !== undefined) {
          properties[this.camelToSnake(key)] = String(value);
        }
      }
    }

    // Add session ID if present
    if (event.sessionId) {
      properties.session_id = event.sessionId;
    }

    return {
      eventType: event.type,
      properties,
      timestamp: event.timestamp,
    };
  }

  /**
   * Send batch to backend
   *
   * Uses APIClient when available (preferred), falls back to telemetry repository.
   * Matches iOS pattern where RemoteTelemetryDataSource uses APIClient.post()
   */
  private async sendBatch(telemetryEvents: TelemetryData[]): Promise<void> {
    // Prefer APIClient (iOS parity - RemoteTelemetryDataSource uses APIClient)
    if (this._apiClient) {
      await this.sendBatchViaAPIClient(telemetryEvents);
      return;
    }

    // Fallback to legacy telemetry repository if available
    if (this.telemetryRepository && this.telemetryRepository.sendBatch) {
      await this.telemetryRepository.sendBatch(telemetryEvents);
      return;
    }

    throw new Error('No API client or telemetry repository configured');
  }

  /**
   * Send batch via APIClient
   *
   * Matches iOS RemoteTelemetryDataSource.sendBatch() pattern.
   */
  private async sendBatchViaAPIClient(
    telemetryEvents: TelemetryData[]
  ): Promise<void> {
    if (!this._apiClient) {
      throw new Error('API client not configured');
    }

    if (telemetryEvents.length === 0) {
      return;
    }

    // Build batch request matching iOS TelemetryBatchRequest
    const batchRequest = {
      events: telemetryEvents.map((event) => ({
        event_type: event.eventType,
        properties: event.properties,
        timestamp: event.timestamp.toISOString(),
      })),
      timestamp: new Date().toISOString(),
    };

    // Use environment-aware analytics endpoint (matches iOS)
    const endpoint = analyticsEndpointForEnvironment(this._environment);

    // In development, auth is not required (matches iOS)
    const requiresAuth = this._environment !== 'development';

    interface AnalyticsBatchResponse {
      success: boolean;
      errors?: string[];
    }

    const response = await this._apiClient.post<
      typeof batchRequest,
      AnalyticsBatchResponse
    >(endpoint, batchRequest, requiresAuth);

    if (!response.success) {
      console.warn(
        '[AnalyticsQueue] Batch send partial failure:',
        response.errors?.join(', ') ?? 'unknown'
      );
    }
  }

  /**
   * Persist queue to local storage
   */
  private async persistQueue(): Promise<void> {
    try {
      // Convert events to serializable format
      const serializedEvents = this.eventQueue.map((event) => ({
        ...event,
        timestamp: event.timestamp.toISOString(),
      }));

      await this.storage.setItem(STORAGE_KEY, JSON.stringify(serializedEvents));
    } catch (error) {
      console.warn('[AnalyticsQueue] Failed to persist queue:', error);
    }
  }

  /**
   * Load persisted events from local storage
   */
  private async loadPersistedEvents(): Promise<void> {
    try {
      const stored = await this.storage.getItem(STORAGE_KEY);
      if (stored) {
        const serializedEvents = JSON.parse(stored) as Array<
          Omit<AnalyticsEvent, 'timestamp'> & { timestamp: string }
        >;
        this.eventQueue = serializedEvents.map((event) => ({
          ...event,
          timestamp: new Date(event.timestamp),
        }));

        logger.debug(`Loaded ${this.eventQueue.length} persisted events`);
      }
    } catch (error) {
      logger.warning(
        `Failed to load persisted events: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Clear persisted queue
   */
  public async clearPersistedQueue(): Promise<void> {
    try {
      await this.storage.removeItem(STORAGE_KEY);
      this.eventQueue = [];
    } catch (error) {
      console.warn('[AnalyticsQueue] Failed to clear persisted queue:', error);
    }
  }

  /**
   * Get queue size
   */
  public getQueueSize(): number {
    return this.eventQueue.length;
  }

  /**
   * Convert camelCase to snake_case
   */
  private camelToSnake(str: string): string {
    return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
  }

  /**
   * Sleep utility
   */
  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Cleanup
   */
  public async cleanup(): Promise<void> {
    this.stopFlushTimer();
    await this.flush();
    await this.persistQueue();
  }
}
