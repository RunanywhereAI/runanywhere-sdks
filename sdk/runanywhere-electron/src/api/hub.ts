// hub.ts — the SdkEvent fan-out behind `RunAnywhere.events`.
//
// Each subscriber gets its own buffered stream, so a slow consumer cannot drop a
// fast one's events. The legacy `EventBus` (RunAnywhere.legacyEvents) is fed from
// the same emit so existing listeners keep working.

import { bridgeStream } from './iter';
import type { SdkEvent } from './types';

/** Broadcasts {@link SdkEvent}s to every open subscriber. */
export class SdkEventHub {
  private readonly sinks = new Set<{ push(e: SdkEvent): void }>();
  private readonly mirrors = new Set<(e: SdkEvent) => void>();

  /** Deliver `event` to every subscriber; a throwing mirror never blocks the rest. */
  emit(event: SdkEvent): void {
    for (const sink of [...this.sinks]) sink.push(event);
    for (const mirror of [...this.mirrors]) {
      try {
        mirror(event);
      } catch {
        // A misbehaving listener must not disrupt the others.
      }
    }
  }

  /** Forward every event to `listener` as well; returns an unsubscribe function. */
  mirror(listener: (e: SdkEvent) => void): () => void {
    this.mirrors.add(listener);
    return () => this.mirrors.delete(listener);
  }

  /** A fresh stream of events from the moment it is first iterated. */
  stream(): AsyncIterableIterator<SdkEvent> {
    let registered: { push(e: SdkEvent): void } | null = null;
    return bridgeStream<SdkEvent>(
      (sink) => {
        registered = sink;
        this.sinks.add(sink);
      },
      () => {
        if (registered) this.sinks.delete(registered);
      }
    );
  }

  /** Drop every subscriber (used by reset()). */
  clear(): void {
    this.sinks.clear();
  }
}
