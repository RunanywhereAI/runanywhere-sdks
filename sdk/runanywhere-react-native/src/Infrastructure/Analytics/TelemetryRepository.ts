/**
 * TelemetryRepository.ts
 *
 * Repository for telemetry data persistence and sync.
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Analytics/Protocol/TelemetryRepository.swift
 */

import type { TelemetryData } from '../../types/analytics';
import type { APIClient } from '../../Data/Network/Services/APIClient';
import { analyticsEndpointForEnvironment } from '../../Data/Network/APIEndpoint';
import { SDKEnvironment } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('TelemetryRepository');

/**
 * Telemetry event types
 * Matches iOS: TelemetryEventType
 */
export enum TelemetryEventType {
  ModelLoaded = 'model_loaded',
  ModelUnloaded = 'model_unloaded',
  GenerationStarted = 'generation_started',
  GenerationCompleted = 'generation_completed',
  GenerationFailed = 'generation_failed',
  TranscriptionStarted = 'transcription_started',
  TranscriptionCompleted = 'transcription_completed',
  TranscriptionFailed = 'transcription_failed',
  SynthesisStarted = 'synthesis_started',
  SynthesisCompleted = 'synthesis_completed',
  SynthesisFailed = 'synthesis_failed',
  VADStarted = 'vad_started',
  VADStopped = 'vad_stopped',
  Error = 'error',
  Custom = 'custom',
}

/**
 * Full telemetry event data with persistence fields
 * Matches iOS: TelemetryData
 */
export interface TelemetryDataEntity {
  id: string;
  eventType: string;
  properties: Record<string, string>;
  timestamp: Date;
  createdAt: Date;
  updatedAt: Date;
  syncPending: boolean;
}

/**
 * Storage interface for telemetry persistence
 */
export interface TelemetryStorage {
  getAll(): Promise<TelemetryDataEntity[]>;
  save(entity: TelemetryDataEntity): Promise<void>;
  delete(id: string): Promise<void>;
  deleteOlderThan(date: Date): Promise<void>;
  markSynced(ids: string[]): Promise<void>;
}

/**
 * In-memory telemetry storage (fallback when no persistent storage available)
 */
class InMemoryTelemetryStorage implements TelemetryStorage {
  private events: Map<string, TelemetryDataEntity> = new Map();

  async getAll(): Promise<TelemetryDataEntity[]> {
    return Array.from(this.events.values());
  }

  async save(entity: TelemetryDataEntity): Promise<void> {
    this.events.set(entity.id, entity);
  }

  async delete(id: string): Promise<void> {
    this.events.delete(id);
  }

  async deleteOlderThan(date: Date): Promise<void> {
    for (const [id, entity] of this.events.entries()) {
      if (entity.timestamp < date) {
        this.events.delete(id);
      }
    }
  }

  async markSynced(ids: string[]): Promise<void> {
    for (const id of ids) {
      const entity = this.events.get(id);
      if (entity) {
        entity.syncPending = false;
        entity.updatedAt = new Date();
      }
    }
  }
}

/**
 * TelemetryRepository implementation
 *
 * Provides telemetry data persistence and sync operations.
 * Matches iOS: TelemetryRepositoryImpl
 */
export class TelemetryRepository {
  private storage: TelemetryStorage;
  private apiClient: APIClient | null;
  private environment: SDKEnvironment;

  constructor(
    apiClient: APIClient | null = null,
    environment: SDKEnvironment = SDKEnvironment.Development,
    storage?: TelemetryStorage
  ) {
    this.apiClient = apiClient;
    this.environment = environment;
    this.storage = storage ?? new InMemoryTelemetryStorage();
  }

  // ============================================================================
  // Repository Operations (matching iOS Repository protocol)
  // ============================================================================

  /**
   * Save a telemetry entity
   * Matches iOS: save(_ entity: TelemetryData)
   */
  async save(entity: TelemetryDataEntity): Promise<void> {
    await this.storage.save(entity);
    logger.debug(`Saved telemetry event: ${entity.id}`);
  }

  /**
   * Fetch all telemetry events
   * Matches iOS: fetchAll()
   */
  async fetchAll(): Promise<TelemetryDataEntity[]> {
    return this.storage.getAll();
  }

  /**
   * Delete a telemetry event
   * Matches iOS: delete(id: String)
   */
  async delete(id: string): Promise<void> {
    await this.storage.delete(id);
  }

  // ============================================================================
  // TelemetryRepository Protocol Methods
  // ============================================================================

  /**
   * Track a new telemetry event
   * Matches iOS: trackEvent(_ type: TelemetryEventType, properties: [String: String])
   */
  async trackEvent(
    type: TelemetryEventType,
    properties: Record<string, string> = {}
  ): Promise<void> {
    const now = new Date();
    const entity: TelemetryDataEntity = {
      id: this.generateId(),
      eventType: type,
      properties,
      timestamp: now,
      createdAt: now,
      updatedAt: now,
      syncPending: true,
    };

    await this.save(entity);
  }

  /**
   * Fetch telemetry events within a date range
   * Matches iOS: fetchByDateRange(from: Date, to: Date)
   */
  async fetchByDateRange(from: Date, to: Date): Promise<TelemetryDataEntity[]> {
    const allEvents = await this.storage.getAll();
    return allEvents
      .filter((event) => event.timestamp >= from && event.timestamp <= to)
      .sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());
  }

  /**
   * Fetch unsent telemetry events
   * Matches iOS: fetchUnsent()
   */
  async fetchUnsent(): Promise<TelemetryDataEntity[]> {
    const allEvents = await this.storage.getAll();
    return allEvents.filter((event) => event.syncPending);
  }

  /**
   * Fetch pending sync items (alias for fetchUnsent)
   * Matches iOS: fetchPendingSync()
   */
  async fetchPendingSync(): Promise<TelemetryDataEntity[]> {
    return this.fetchUnsent();
  }

  /**
   * Mark telemetry events as sent/synced
   * Matches iOS: markAsSent(_ ids: [String])
   */
  async markAsSent(ids: string[]): Promise<void> {
    await this.storage.markSynced(ids);
    logger.info(`Marked ${ids.length} telemetry events as sent`);
  }

  /**
   * Mark telemetry events as synced (alias)
   * Matches iOS: markSynced(_ ids: [String])
   */
  async markSynced(ids: string[]): Promise<void> {
    await this.markAsSent(ids);
  }

  /**
   * Clean up telemetry events older than specified date
   * Matches iOS: cleanup(olderThan date: Date)
   */
  async cleanup(olderThan: Date): Promise<void> {
    await this.storage.deleteOlderThan(olderThan);
    logger.info(`Cleaned up telemetry events older than ${olderThan.toISOString()}`);
  }

  // ============================================================================
  // Sync Operations
  // ============================================================================

  /**
   * Sync unsent events to backend
   * Matches iOS: RemoteTelemetryDataSource.syncBatch()
   */
  async syncUnsent(): Promise<string[]> {
    if (!this.apiClient) {
      logger.debug('No API client configured - skipping sync');
      return [];
    }

    const pending = await this.fetchUnsent();
    if (pending.length === 0) {
      logger.debug('No pending telemetry events to sync');
      return [];
    }

    try {
      const syncedIds = await this.sendBatch(pending);
      if (syncedIds.length > 0) {
        await this.markSynced(syncedIds);
      }
      return syncedIds;
    } catch (error) {
      logger.error(`Failed to sync telemetry: ${error}`);
      return [];
    }
  }

  /**
   * Send batch to backend
   * Matches iOS: RemoteTelemetryDataSource.sendBatch()
   */
  private async sendBatch(events: TelemetryDataEntity[]): Promise<string[]> {
    if (!this.apiClient || events.length === 0) {
      return [];
    }

    const batchRequest = {
      events: events.map((event) => ({
        id: event.id,
        event_type: event.eventType,
        properties: event.properties,
        timestamp: event.timestamp.toISOString(),
      })),
      timestamp: new Date().toISOString(),
    };

    const endpoint = analyticsEndpointForEnvironment(this.environment);
    const requiresAuth = this.environment !== SDKEnvironment.Development;

    interface SyncResponse {
      success: boolean;
      synced_ids?: string[];
      errors?: string[];
    }

    const response = await this.apiClient.post<typeof batchRequest, SyncResponse>(
      endpoint,
      batchRequest,
      requiresAuth
    );

    if (response.success && response.synced_ids) {
      return response.synced_ids;
    }

    // If no specific IDs returned but success, assume all synced
    if (response.success) {
      return events.map((e) => e.id);
    }

    logger.warning(`Partial sync failure: ${response.errors?.join(', ') ?? 'unknown'}`);
    return response.synced_ids ?? [];
  }

  // ============================================================================
  // Helpers
  // ============================================================================

  private generateId(): string {
    return `${Date.now()}-${Math.random().toString(36).substring(2, 11)}`;
  }

  /**
   * Set custom storage
   */
  setStorage(storage: TelemetryStorage): void {
    this.storage = storage;
  }

  /**
   * Set API client for sync operations
   */
  setAPIClient(apiClient: APIClient, environment: SDKEnvironment): void {
    this.apiClient = apiClient;
    this.environment = environment;
  }
}
