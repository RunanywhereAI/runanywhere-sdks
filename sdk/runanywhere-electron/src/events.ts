// The SdkEvent fan-out behind RunAnywhere.events. Each subscriber gets its own
// buffered, bridge-safe stream, so a slow consumer cannot drop a fast one's
// events.
import { bridgeStream } from './stream.js';
import type { SdkEvent } from './types.js';

export class SdkEventHub {
  private readonly sinks = new Set<{ push(e: SdkEvent): void; end(): void }>();

  /** Deliver `event` to every open subscriber. */
  emit(event: SdkEvent): void {
    for (const sink of [...this.sinks]) sink.push(event);
  }

  /** A fresh event stream, live from the moment it is first iterated. */
  stream(): AsyncIterableIterator<SdkEvent> {
    let registered: { push(e: SdkEvent): void; end(): void } | null = null;
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

  /** End every open stream and drop subscribers (used by reset()). */
  clear(): void {
    for (const sink of [...this.sinks]) sink.end();
    this.sinks.clear();
  }
}
