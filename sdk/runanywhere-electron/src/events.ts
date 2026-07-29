// events.ts — a small typed event bus for lifecycle + telemetry, mirroring the
// other SDKs' `RunAnywhere.events`. Consumers subscribe to model-lifecycle and
// generation events (e.g. to record on-device analytics). Pure + no addon, so it
// is importable and testable everywhere.
import type { LLMGenerationResult } from './stream';

export type Modality = 'llm' | 'vlm' | 'embedder' | 'stt' | 'tts';

export interface LifecycleEvent {
  type: 'initialized' | 'servicesReady' | 'shutdown';
}
export interface ModelLoadedEvent {
  type: 'modelLoaded';
  modality: Modality;
  id: string;
}
export interface ModelUnloadedEvent {
  type: 'modelUnloaded';
  modality: Modality;
}
/** Emitted after a generateStream completes — carries the timing/throughput metrics. */
export interface GenerationEvent {
  type: 'generation';
  result: LLMGenerationResult;
}

export type RunAnywhereEvent =
  | LifecycleEvent
  | ModelLoadedEvent
  | ModelUnloadedEvent
  | GenerationEvent;

export type EventListener = (event: RunAnywhereEvent) => void;

export class EventBus {
  private readonly listeners = new Set<EventListener>();

  /** Subscribe to all events; returns an unsubscribe function. */
  on(listener: EventListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** Subscribe to the next event only; returns an unsubscribe function. */
  once(listener: EventListener): () => void {
    const off = this.on((event) => {
      off();
      listener(event);
    });
    return off;
  }

  off(listener: EventListener): void {
    this.listeners.delete(listener);
  }

  /** Emit an event to all listeners; a throwing listener never breaks the emit. */
  emit(event: RunAnywhereEvent): void {
    for (const listener of [...this.listeners]) {
      try {
        listener(event);
      } catch {
        /* a misbehaving listener must not disrupt the others */
      }
    }
  }

  removeAll(): void {
    this.listeners.clear();
  }

  get listenerCount(): number {
    return this.listeners.size;
  }
}

/** Process-wide singleton exposed as RunAnywhere.events. */
export const bus = new EventBus();
