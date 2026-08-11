// hub.ts — the SdkEvent fan-out behind `RunAnywhere.events`.
//
// Each subscriber gets its own buffered stream, so a slow consumer cannot drop a
// fast one's events.

import { bridgeStream } from './iter';
import type { SdkEvent } from './types';

/** Broadcasts {@link SdkEvent}s to every open subscriber. */
export class SdkEventHub {
  private readonly sinks = new Set<{ push(e: SdkEvent): void }>();

  /** Deliver `event` to every subscriber. */
  emit(event: SdkEvent): void {
    for (const sink of [...this.sinks]) sink.push(event);
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
