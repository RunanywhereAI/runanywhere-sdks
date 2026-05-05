/**
 * RunAnywhere React Native SDK - Internal Event Bus
 *
 * Minimal internal event bus used by AudioCaptureManager / AudioPlaybackManager
 * to emit voice-session lifecycle signals (`recordingStarted`, `playbackStopped`,
 * ...) for in-process observers.
 *
 * Public SDK event streaming has moved to the proto-byte pipe exposed via
 * `RunAnywhere.subscribeSDKEvents(...)`. This façade retains only the
 * fire-and-forget `publish()` surface actually used by the audio managers.
 */

type EventPayload = unknown;

/**
 * Minimal publish-only event bus.
 * No subscribers, no native fan-out — publish is a no-op façade today,
 * kept as an integration seam for future audio-internal consumers.
 */
class EventBusImpl {
  /**
   * Publish an event locally.
   * Currently a no-op — there are no in-process subscribers.
   */
  publish(_eventType: string, _event: EventPayload): void {
    // Intentionally a no-op: audio managers fire informational events,
    // but public subscribers consume the proto-byte SDK event stream.
  }
}

// Singleton instance
const instance: EventBusImpl = new EventBusImpl();

/**
 * Singleton EventBus exposing only the `publish` method.
 */
export const EventBus = {
  publish: instance.publish.bind(instance),
} as const;

// Export type for the EventBus (kept for import stability)
export type { EventBusImpl };
