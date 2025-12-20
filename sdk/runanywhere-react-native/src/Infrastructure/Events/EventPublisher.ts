/**
 * EventPublisher
 *
 * Single entry point for all SDK event tracking.
 * Routes events to appropriate destinations based on event.destination:
 * - EventBus: Public events for app developers
 * - AnalyticsQueueManager: Internal telemetry for backend
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/EventPublisher.swift
 */

import { EventDestination, type SDKEvent } from './SDKEvent';
import { EventBus } from '../../Public/Events/EventBus';
import type { AnalyticsQueueManager } from '../Analytics/AnalyticsQueueManager';
import type { AnalyticsEvent } from '../../types/analytics';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('EventPublisher');

// ============================================================================
// EventPublisher Class
// ============================================================================

/**
 * Central event publisher that routes SDK events to appropriate destinations.
 *
 * Design:
 * - Single entry point for all event tracking in the SDK
 * - Routes based on event.destination property
 * - Converts SDKEvent to AnalyticsEvent for telemetry backend
 *
 * Usage:
 * ```typescript
 * // Track an event (routes automatically based on destination)
 * EventPublisher.shared.track(myEvent);
 *
 * // Track asynchronously (for use in async contexts)
 * await EventPublisher.shared.trackAsync(myEvent);
 * ```
 */
class EventPublisherImpl {
  private analyticsQueue: AnalyticsQueueManager | null = null;
  private isInitialized = false;

  /**
   * Initialize the publisher with the analytics queue.
   * Should be called during SDK startup.
   *
   * @param analyticsQueue - The analytics queue manager for telemetry
   */
  initialize(analyticsQueue: AnalyticsQueueManager): void {
    this.analyticsQueue = analyticsQueue;
    this.isInitialized = true;
  }

  /**
   * Check if the publisher is initialized.
   */
  get initialized(): boolean {
    return this.isInitialized;
  }

  /**
   * Track an event synchronously.
   * Routes to EventBus and/or AnalyticsQueue based on event.destination.
   *
   * @param event - The SDK event to track
   */
  track(event: SDKEvent): void {
    const destination = event.destination;

    // Route to EventBus (public) - unless analyticsOnly
    if (destination !== EventDestination.AnalyticsOnly) {
      this.publishToEventBus(event);
    }

    // Route to Analytics (telemetry) - unless publicOnly
    if (destination !== EventDestination.PublicOnly) {
      this.enqueueForAnalytics(event);
    }
  }

  /**
   * Track an event asynchronously.
   * Use this in async contexts where you want to await the analytics enqueue.
   *
   * @param event - The SDK event to track
   */
  async trackAsync(event: SDKEvent): Promise<void> {
    const destination = event.destination;

    // Route to EventBus (public) - unless analyticsOnly
    if (destination !== EventDestination.AnalyticsOnly) {
      this.publishToEventBus(event);
    }

    // Route to Analytics (telemetry) - unless publicOnly
    if (destination !== EventDestination.PublicOnly) {
      await this.enqueueForAnalyticsAsync(event);
    }
  }

  /**
   * Track multiple events at once.
   *
   * @param events - Array of SDK events to track
   */
  trackBatch(events: SDKEvent[]): void {
    for (const event of events) {
      this.track(event);
    }
  }

  /**
   * Publish an event to the EventBus for public consumption.
   */
  private publishToEventBus(event: SDKEvent): void {
    // Map category to native event type for EventBus
    const eventTypeMap: Record<string, string> = {
      sdk: 'Initialization',
      model: 'Model',
      llm: 'Generation',
      stt: 'Voice',
      tts: 'Voice',
      voice: 'Voice',
      storage: 'Storage',
      device: 'Device',
      network: 'Network',
      error: 'Initialization', // Errors go through initialization channel
    };

    const eventType = eventTypeMap[event.category] ?? 'Model';

    // Create a simplified event object for EventBus
    // EventBus expects events with { type: string, ...properties }
    const busEvent = {
      type: event.type,
      timestamp: event.timestamp.toISOString(),
      ...event.properties,
    };

    EventBus.publish(eventType, busEvent);
  }

  /**
   * Enqueue an event for analytics processing (sync version).
   */
  private enqueueForAnalytics(event: SDKEvent): void {
    if (!this.analyticsQueue) {
      // Analytics not initialized - log warning but don't block
      if (process.env.NODE_ENV !== 'production') {
        logger.debug(
          `Analytics queue not initialized, event not tracked: ${event.type}`
        );
      }
      return;
    }

    const analyticsEvent = this.convertToAnalyticsEvent(event);
    // Fire and forget - don't await
    this.analyticsQueue.enqueue(analyticsEvent).catch((error) => {
      logger.warning('Failed to enqueue event:', { error });
    });
  }

  /**
   * Enqueue an event for analytics processing (async version).
   */
  private async enqueueForAnalyticsAsync(event: SDKEvent): Promise<void> {
    if (!this.analyticsQueue) {
      if (process.env.NODE_ENV !== 'production') {
        logger.debug(
          `Analytics queue not initialized, event not tracked: ${event.type}`
        );
      }
      return;
    }

    const analyticsEvent = this.convertToAnalyticsEvent(event);
    await this.analyticsQueue.enqueue(analyticsEvent);
  }

  /**
   * Convert SDKEvent to AnalyticsEvent for the queue manager.
   */
  private convertToAnalyticsEvent(event: SDKEvent): AnalyticsEvent {
    return {
      id: event.id,
      type: event.type,
      timestamp: event.timestamp,
      sessionId: event.sessionId,
      eventData: event.properties,
    };
  }

  /**
   * Flush all pending analytics events.
   * Call this before app shutdown or backgrounding.
   */
  async flush(): Promise<void> {
    if (this.analyticsQueue) {
      await this.analyticsQueue.flush();
    }
  }

  /**
   * Reset the publisher state.
   * Primarily used for testing.
   */
  reset(): void {
    this.analyticsQueue = null;
    this.isInitialized = false;
  }
}

// ============================================================================
// Singleton Instance
// ============================================================================

/**
 * Shared EventPublisher singleton.
 *
 * Usage:
 * ```typescript
 * import { EventPublisher } from './Infrastructure/Events';
 *
 * // Initialize once during SDK startup
 * EventPublisher.shared.initialize(AnalyticsQueueManager.shared);
 *
 * // Track events anywhere in the SDK
 * EventPublisher.shared.track(myEvent);
 * ```
 */
export const EventPublisher = {
  /** Singleton instance */
  shared: new EventPublisherImpl(),
};

export type { EventPublisherImpl };
