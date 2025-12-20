/**
 * SDKEvent Protocol
 *
 * Unified event interface for the RunAnywhere SDK.
 * All events conform to this protocol for consistent routing and handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/SDKEvent.swift
 */

// ============================================================================
// Event Destination
// ============================================================================

/**
 * Determines where an event should be routed.
 *
 * - `publicOnly`: Only to EventBus (for app developers to consume)
 * - `analyticsOnly`: Only to analytics/telemetry (internal metrics to backend)
 * - `all`: Both EventBus and Analytics (default)
 */
export enum EventDestination {
  /** Only route to EventBus (public API for app developers) */
  PublicOnly = 'publicOnly',

  /** Only route to Analytics backend (internal telemetry) */
  AnalyticsOnly = 'analyticsOnly',

  /** Route to both EventBus and Analytics (default) */
  All = 'all',
}

// ============================================================================
// Event Category
// ============================================================================

/**
 * Categories for SDK events.
 * Used for filtering and routing events to appropriate handlers.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/SDKEvent.swift
 */
export enum EventCategory {
  /** SDK lifecycle events (init, shutdown) */
  SDK = 'sdk',

  /** Model download, load, unload events */
  Model = 'model',

  /** LLM generation events */
  LLM = 'llm',

  /** Speech-to-text events */
  STT = 'stt',

  /** Text-to-speech events */
  TTS = 'tts',

  /** Voice pipeline events (VAD, voice agent) */
  Voice = 'voice',

  /** Storage and cache events */
  Storage = 'storage',

  /** Device registration and info events */
  Device = 'device',

  /** Network connectivity and request events */
  Network = 'network',

  /** Error events */
  Error = 'error',
}

// ============================================================================
// SDKEvent Interface
// ============================================================================

/**
 * Core SDKEvent interface.
 *
 * All SDK events must conform to this interface for unified handling.
 * The interface provides:
 * - Unique identification (id)
 * - Type categorization (type, category)
 * - Temporal tracking (timestamp)
 * - Session grouping (sessionId)
 * - Routing control (destination)
 * - Serializable properties for analytics
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/SDKEvent.swift
 */
export interface SDKEvent {
  /**
   * Unique identifier for the event.
   * Default: Auto-generated UUID
   */
  readonly id: string;

  /**
   * Event type string (e.g., "llm_generation_started", "model_load_completed").
   * Used for event identification and analytics.
   */
  readonly type: string;

  /**
   * Event category for filtering and routing.
   */
  readonly category: EventCategory;

  /**
   * When the event occurred.
   * Default: Current timestamp
   */
  readonly timestamp: Date;

  /**
   * Optional session ID for grouping related events.
   * Useful for tracking events across a user session or operation.
   */
  readonly sessionId?: string;

  /**
   * Where this event should be routed.
   * Default: EventDestination.All
   */
  readonly destination: EventDestination;

  /**
   * Key-value properties for analytics serialization.
   * All values are strings for universal backend compatibility.
   */
  readonly properties: Record<string, string>;
}

// ============================================================================
// Factory Helpers
// ============================================================================

/**
 * Generate a unique event ID.
 */
function generateEventId(): string {
  // Use crypto.randomUUID if available, otherwise fallback
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  // Fallback for environments without crypto.randomUUID
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Create an SDKEvent with default values filled in.
 *
 * @param type - Event type string
 * @param category - Event category
 * @param properties - Event properties
 * @param options - Optional overrides for id, timestamp, sessionId, destination
 */
export function createSDKEvent(
  type: string,
  category: EventCategory,
  properties: Record<string, string> = {},
  options: {
    id?: string;
    timestamp?: Date;
    sessionId?: string;
    destination?: EventDestination;
  } = {}
): SDKEvent {
  return {
    id: options.id ?? generateEventId(),
    type,
    category,
    timestamp: options.timestamp ?? new Date(),
    sessionId: options.sessionId,
    destination: options.destination ?? EventDestination.All,
    properties,
  };
}

// ============================================================================
// Type Guards
// ============================================================================

/**
 * Check if an object conforms to the SDKEvent interface.
 */
export function isSDKEvent(obj: unknown): obj is SDKEvent {
  if (typeof obj !== 'object' || obj === null) {
    return false;
  }

  const event = obj as Record<string, unknown>;

  return (
    typeof event.id === 'string' &&
    typeof event.type === 'string' &&
    typeof event.category === 'string' &&
    Object.values(EventCategory).includes(event.category as EventCategory) &&
    event.timestamp instanceof Date &&
    typeof event.destination === 'string' &&
    Object.values(EventDestination).includes(
      event.destination as EventDestination
    ) &&
    typeof event.properties === 'object' &&
    event.properties !== null
  );
}
