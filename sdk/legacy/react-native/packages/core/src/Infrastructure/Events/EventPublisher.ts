/**
 * EventPublisher
 *
 * Single entry point for all SDK event tracking.
 * Routes events to EventBus for public consumption.
 * Analytics/telemetry is now handled by native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/EventPublisher.swift
 */

import { EventDestination, type SDKEvent } from './SDKEvent';
import { EventBus } from '../../Public/Events/EventBus';
import type { AnySDKEvent } from '../../types/events';
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
 * - Routes to EventBus for public events
 * - Analytics/telemetry is handled by native commons
 *
 * Usage:
 * ```typescript
 * // Track an event
 * EventPublisher.shared.track(myEvent);
 * ```
 */
class EventPublisherImpl {
  private isInitialized = false;

  /**
   * Initialize the publisher.
   * Should be called during SDK startup.
   */
  initialize(): void {
    this.isInitialized = true;
    logger.debug('EventPublisher initialized');
  }

  /**
   * Check if the publisher is initialized.
   */
  get initialized(): boolean {
    return this.isInitialized;
  }

  /**
   * Track an event synchronously.
   * Routes to EventBus based on event.destination.
   *
   * @param event - The SDK event to track
   */
  track(event: SDKEvent): void {
    const destination = event.destination;

    // Route to EventBus (public) - unless analyticsOnly
    if (destination !== EventDestination.AnalyticsOnly) {
      this.publishToEventBus(event);
    }

    // Analytics events are now handled by native commons via
    // the rac_* API - no JS-side analytics queue needed
  }

  /**
   * Track an event asynchronously.
   * Use this in async contexts.
   *
   * @param event - The SDK event to track
   */
  async trackAsync(event: SDKEvent): Promise<void> {
    this.track(event);
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
    } as AnySDKEvent;

    EventBus.publish(eventType, busEvent);
  }

  /**
   * Flush all pending analytics events.
   * No-op since analytics is now in native commons.
   */
  async flush(): Promise<void> {
    // Analytics flushing is handled by native commons
  }

  /**
   * Reset the publisher state.
   * Primarily used for testing.
   */
  reset(): void {
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
 * EventPublisher.shared.initialize();
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
