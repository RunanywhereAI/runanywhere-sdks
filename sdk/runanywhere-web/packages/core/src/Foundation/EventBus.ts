/**
 * RunAnywhere Web SDK - Event Bus
 *
 * Central event system matching the pattern across all SDKs.
 * Provides typed event subscription and publishing.
 */

import type { SDKEventType } from '../types/enums';
import { SDKLogger } from './SDKLogger';

const logger = new SDKLogger('EventBus');

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

/** Known SDK event types and their payload shapes. */
export interface SDKEventMap {
  // SDK lifecycle
  'sdk.initialized': { environment: string };
  'sdk.accelerationMode': { mode: string };

  // Model management
  'model.registered': { count: number };
  'model.downloadStarted': { modelId: string; url: string };
  'model.downloadProgress': { modelId: string; progress: number; bytesDownloaded: number; totalBytes: number; stage?: string };
  'model.downloadCompleted': { modelId: string; sizeBytes?: number; localPath?: string };
  'model.downloadFailed': { modelId: string; error: string };
  'model.loadStarted': { modelId: string; component?: string; category?: string };
  'model.loadCompleted': { modelId: string; component?: string; category?: string; loadTimeMs?: number };
  'model.loadFailed': { modelId: string; error: string };
  'model.unloaded': { modelId: string; category: string };
  'model.quotaExceeded': { modelId: string; availableBytes: number; neededBytes: number };
  'model.evicted': { modelId: string; modelName: string; freedBytes: number };

  // Text generation
  'generation.started': { prompt: string };
  'generation.completed': { tokensUsed: number; latencyMs: number };
  'generation.failed': { error: string };

  // Speech-to-text
  'stt.transcribed': { text: string; confidence: number; audioDurationMs?: number; wordCount?: number };
  'stt.transcriptionFailed': { error: string };

  // Text-to-speech
  'tts.synthesized': { durationMs: number; sampleRate: number; characterCount?: number; processingMs?: number; charsPerSec?: number; textLength?: number };
  'tts.synthesisFailed': { error: string };

  // Voice activity detection
  'vad.speechStarted': { activity: string };
  'vad.speechEnded': { activity: string; speechDurationMs?: number };

  // Voice agent
  'voice.turnCompleted': { speechDetected: boolean; transcription: string; response: string };

  // Embeddings
  'embeddings.generated': { numEmbeddings: number; dimension: number; processingTimeMs: number };

  // Diffusion
  'diffusion.generated': { width: number; height: number; generationTimeMs: number };

  // Vision-language model
  'vlm.processed': { tokensPerSecond: number; totalTokens: number; hardwareUsed: string };

  // Audio playback
  'playback.started': { durationMs: number; sampleRate: number };
  'playback.completed': { durationMs: number };

  // Allow custom events
  [key: string]: Record<string, unknown>;
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
  on<K extends keyof SDKEventMap>(eventType: K, listener: EventListener<SDKEventMap[K]>): Unsubscribe {
    const key = eventType as string;
    if (!this.listeners.has(key)) {
      this.listeners.set(key, new Set());
    }
    const set = this.listeners.get(key)!;
    set.add(listener as EventListener);

    return () => {
      set.delete(listener as EventListener);
      if (set.size === 0) {
        this.listeners.delete(key);
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
  once<K extends keyof SDKEventMap>(eventType: K, listener: EventListener<SDKEventMap[K]>): Unsubscribe {
    const unsubscribe = this.on(eventType, (event) => {
      unsubscribe();
      listener(event);
    });
    return unsubscribe;
  }

  /**
   * Emit an event.
   */
  emit<K extends keyof SDKEventMap>(eventType: K, category: SDKEventType, data?: SDKEventMap[K]): void {
    const key = eventType as string;
    const payload = (data ?? {}) as Record<string, unknown>;
    const envelope: SDKEventEnvelope = {
      type: key,
      category,
      timestamp: Date.now(),
      data: payload,
    };

    // Notify specific listeners
    const specific = this.listeners.get(key);
    if (specific) {
      for (const listener of specific) {
        try {
          listener(payload);
        } catch (error) {
          logger.error(`Listener error for ${key}: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
    }

    // Notify wildcard listeners
    for (const listener of this.wildcardListeners) {
      try {
        listener(envelope);
      } catch (error) {
        logger.error(`Wildcard listener error: ${error instanceof Error ? error.message : String(error)}`);
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
