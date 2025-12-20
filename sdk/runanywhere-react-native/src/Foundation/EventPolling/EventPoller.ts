/**
 * EventPoller.ts
 *
 * Manages polling for queued events from the native C++ module.
 * This solves the use-after-free issue with the jsi::Runtime reference.
 *
 * Instead of capturing RT by reference in async lambdas,
 * native code now queues events safely and JS polls them periodically.
 *
 * Pattern: Option A (Event Queue Pattern)
 * - Native emitEvent() queues events thread-safely
 * - JS polls periodically via pollEvents()
 * - No JSI Runtime lifetime issues
 * - Clean separation of concerns
 */

import { NativeRunAnywhere } from '../../native/NativeRunAnywhere';
import { EventBus } from '../../Public/Events/EventBus';
import type { SDKModelEvent, SDKVoiceEvent } from '../../types';

export interface QueuedEvent {
  eventName: string;
  eventData: string; // JSON string
}

/**
 * Manages polling for native events without JSI Runtime capture issues
 */
export class EventPoller {
  private pollInterval: NodeJS.Timeout | null = null;
  private pollIntervalMs: number = 100; // Poll every 100ms
  private isPolling: boolean = false;

  constructor(pollIntervalMs: number = 100) {
    this.pollIntervalMs = pollIntervalMs;
  }

  /**
   * Start polling for events from native
   */
  startPolling(): void {
    if (this.isPolling) return;
    this.isPolling = true;

    // Poll immediately on first call
    this.pollOnce();

    // Then set up interval for ongoing polling
    this.pollInterval = setInterval(() => {
      this.pollOnce();
    }, this.pollIntervalMs);
  }

  /**
   * Stop polling for events
   */
  stopPolling(): void {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    this.isPolling = false;
  }

  /**
   * Single poll iteration - fetch and process queued events
   */
  private pollOnce(): void {
    NativeRunAnywhere.pollEvents()
      .then((eventsJsonString) => {
        this.processQueuedEvents(eventsJsonString);
      })
      .catch((error) => {
        console.error('[RunAnywhere] Error polling events:', error);
      });
  }

  /**
   * Process a batch of queued events from native
   */
  private processQueuedEvents(eventsJsonString: string): void {
    try {
      // Parse JSON array of events
      const events: QueuedEvent[] = JSON.parse(eventsJsonString);

      if (!Array.isArray(events)) {
        console.error(
          '[RunAnywhere] pollEvents returned non-array:',
          eventsJsonString
        );
        return;
      }

      // Process each event
      for (const event of events) {
        this.handleQueuedEvent(event);
      }
    } catch (error) {
      console.error(
        '[RunAnywhere] Error parsing polled events:',
        error,
        eventsJsonString
      );
    }
  }

  /**
   * Handle a single queued event - route to appropriate handler
   */
  private handleQueuedEvent(event: QueuedEvent): void {
    try {
      const { eventName, eventData } = event;

      // Parse the event data JSON
      let parsedData: Record<string, unknown>;
      try {
        parsedData = JSON.parse(eventData) as Record<string, unknown>;
      } catch {
        parsedData = { raw: eventData };
      }

      // Route to appropriate event bus based on event name
      this.routeEvent(eventName, parsedData);
    } catch (error) {
      console.error('[RunAnywhere] Error handling queued event:', error, event);
    }
  }

  /**
   * Route event to the appropriate EventBus method
   */
  private routeEvent(
    eventName: string,
    eventData: Record<string, unknown>
  ): void {
    // Model load events - use SDKModelEvent type
    if (eventName === 'onGenerationStart') {
      const modelEvent: SDKModelEvent = {
        type: 'loadStarted',
        modelId: String(eventData.modelId ?? eventData.prompt ?? ''),
      };
      EventBus.emitModel(modelEvent);
      return;
    }
    if (eventName === 'onGenerationToken') {
      const modelEvent: SDKModelEvent = {
        type: 'loadProgress',
        modelId: String(eventData.modelId ?? ''),
        progress: Number(eventData.progress ?? 0),
      };
      EventBus.emitModel(modelEvent);
      return;
    }
    if (eventName === 'onGenerationComplete') {
      const modelEvent: SDKModelEvent = {
        type: 'loadCompleted',
        modelId: String(eventData.modelId ?? ''),
      };
      EventBus.emitModel(modelEvent);
      return;
    }

    // TTS events
    if (eventName === 'onTTSAudio') {
      const ttsEvent: SDKVoiceEvent = {
        type: 'audioGenerated',
        data: String(eventData.data ?? ''),
      };
      EventBus.emitVoice(ttsEvent);
      return;
    }
    if (eventName === 'onTTSComplete') {
      const ttsEvent: SDKVoiceEvent = { type: 'synthesisCompleted' };
      EventBus.emitVoice(ttsEvent);
      return;
    }
    if (eventName === 'onTTSError') {
      const ttsEvent: SDKVoiceEvent = {
        type: 'pipelineError',
        error: String(eventData.error ?? 'Unknown TTS error'),
      };
      EventBus.emitVoice(ttsEvent);
      return;
    }

    // Voice events (STT, VAD)
    if (eventName === 'onTranscriptionUpdate') {
      const voiceEvent: SDKVoiceEvent = {
        type: 'transcriptionPartial',
        text: String(eventData.text ?? ''),
      };
      EventBus.emitVoice(voiceEvent);
      return;
    }
    if (eventName === 'onTranscriptionComplete') {
      const voiceEvent: SDKVoiceEvent = {
        type: 'transcriptionFinal',
        text: String(eventData.text ?? ''),
      };
      EventBus.emitVoice(voiceEvent);
      return;
    }
    if (eventName === 'onVADStateChange') {
      // VAD state changes map to different event types
      const vadState = String(eventData.state ?? 'unknown');
      let voiceEvent: SDKVoiceEvent;
      if (vadState === 'detected') {
        voiceEvent = { type: 'vadDetected' };
      } else if (vadState === 'ended') {
        voiceEvent = { type: 'vadEnded' };
      } else {
        voiceEvent = { type: 'vadStarted' };
      }
      EventBus.emitVoice(voiceEvent);
      return;
    }

    // Generic model events
    if (eventName === 'onModelLoaded') {
      const modelEvent: SDKModelEvent = {
        type: 'loadCompleted',
        modelId: String(eventData.modelId ?? ''),
      };
      EventBus.emitModel(modelEvent);
      return;
    }
    if (eventName === 'onModelUnloaded') {
      const modelEvent: SDKModelEvent = {
        type: 'unloadCompleted',
      };
      EventBus.emitModel(modelEvent);
      return;
    }

    // Unknown event - emit to all events
    EventBus.publish(eventName, {
      type: eventName,
      timestamp: Date.now(),
      ...eventData,
    });
  }

  /**
   * Cleanup - stop polling and clear queue
   */
  cleanup(): void {
    this.stopPolling();

    // Clear any remaining events from the queue
    try {
      NativeRunAnywhere.clearEventQueue();
    } catch (error) {
      console.error('[RunAnywhere] Error clearing event queue:', error);
    }
  }

  /**
   * Check if currently polling
   */
  getIsPolling(): boolean {
    return this.isPolling;
  }

  /**
   * Change polling interval
   */
  setPollingInterval(intervalMs: number): void {
    this.pollIntervalMs = intervalMs;
    if (this.isPolling) {
      this.stopPolling();
      this.startPolling();
    }
  }
}

// Singleton instance
let eventPollerInstance: EventPoller | null = null;

/**
 * Get or create the singleton EventPoller
 */
export function getEventPoller(): EventPoller {
  if (!eventPollerInstance) {
    eventPollerInstance = new EventPoller();
  }
  return eventPollerInstance;
}

/**
 * Singleton wrapper for convenience
 */
export const EventPollerSingleton = {
  getInstance(): EventPoller {
    return getEventPoller();
  },

  startPolling(): void {
    getEventPoller().startPolling();
  },

  stopPolling(): void {
    getEventPoller().stopPolling();
  },

  cleanup(): void {
    if (eventPollerInstance) {
      eventPollerInstance.cleanup();
      eventPollerInstance = null;
    }
  },

  setPollingInterval(intervalMs: number): void {
    getEventPoller().setPollingInterval(intervalMs);
  },

  isPolling(): boolean {
    return eventPollerInstance?.getIsPolling() ?? false;
  },
};
