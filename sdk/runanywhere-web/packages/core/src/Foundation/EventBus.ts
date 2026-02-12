/**
 * RunAnywhere Web SDK - Event Bus
 *
 * Central event system matching the pattern across all SDKs.
 * Provides typed event subscription and publishing.
 */

import type { SDKEventType } from '../types/enums';

/** Generic event listener */
export type EventListener<T = unknown> = (event: T) => void;

/** Unsubscribe function returned by subscribe */
export type Unsubscribe = () => void;

/** Event envelope wrapping all emitted events */
export interface SDKEventEnvelope {
  type: string;
  category: SDKEventType;
  timestamp: number;
  data: Record<string, unknown>;
}

/**
 * EventBus - Central event system for the SDK.
 *
 * Mirrors the EventBus pattern used in Swift, Kotlin, React Native, and Flutter SDKs.
 * On web, this is a pure TypeScript implementation (no C++ bridge needed for events
 * since we subscribe to RACommons events via rac_event_subscribe and re-emit here).
 */
export class EventBus {
  private static _instance: EventBus | null = null;

  private listeners = new Map<string, Set<EventListener>>();
  private wildcardListeners = new Set<EventListener<SDKEventEnvelope>>();

  static get shared(): EventBus {
    if (!EventBus._instance) {
      EventBus._instance = new EventBus();
    }
    return EventBus._instance;
  }

  /**
   * Subscribe to events of a specific type.
   * @returns Unsubscribe function
   */
  on<T = unknown>(eventType: string, listener: EventListener<T>): Unsubscribe {
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, new Set());
    }
    const set = this.listeners.get(eventType)!;
    set.add(listener as EventListener);

    return () => {
      set.delete(listener as EventListener);
      if (set.size === 0) {
        this.listeners.delete(eventType);
      }
    };
  }

  /**
   * Subscribe to ALL events (wildcard).
   * @returns Unsubscribe function
   */
  onAny(listener: EventListener<SDKEventEnvelope>): Unsubscribe {
    this.wildcardListeners.add(listener);
    return () => {
      this.wildcardListeners.delete(listener);
    };
  }

  /**
   * Subscribe to events once (auto-unsubscribe after first event).
   */
  once<T = unknown>(eventType: string, listener: EventListener<T>): Unsubscribe {
    const unsubscribe = this.on<T>(eventType, (event) => {
      unsubscribe();
      listener(event);
    });
    return unsubscribe;
  }

  /**
   * Emit an event.
   */
  emit(eventType: string, category: SDKEventType, data: Record<string, unknown> = {}): void {
    const envelope: SDKEventEnvelope = {
      type: eventType,
      category,
      timestamp: Date.now(),
      data,
    };

    // Notify specific listeners
    const specific = this.listeners.get(eventType);
    if (specific) {
      for (const listener of specific) {
        try {
          listener(data);
        } catch (error) {
          console.error(`[EventBus] Listener error for ${eventType}:`, error);
        }
      }
    }

    // Notify wildcard listeners
    for (const listener of this.wildcardListeners) {
      try {
        listener(envelope);
      } catch (error) {
        console.error('[EventBus] Wildcard listener error:', error);
      }
    }
  }

  /**
   * Remove all listeners.
   */
  removeAll(): void {
    this.listeners.clear();
    this.wildcardListeners.clear();
  }

  /** Reset singleton (for testing) */
  static reset(): void {
    if (EventBus._instance) {
      EventBus._instance.removeAll();
    }
    EventBus._instance = null;
  }
}
