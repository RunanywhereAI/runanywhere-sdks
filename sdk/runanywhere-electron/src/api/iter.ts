// iter.ts — AsyncIterable plumbing for the streaming verbs.
//
// Every stream the SDK returns must be *bridge safe*. `contextBridge` walks an
// exposed value's OWN properties and rebuilds it in the page; a generator object
// cannot survive that at all, and neither can a class instance — its `next` and
// its `[Symbol.asyncIterator]` live on the prototype, which is not walked, so
// what arrives in the renderer is an object with no methods and no iterability.
// `for await (… of stream)` then fails on a value that worked perfectly in the
// main process.
//
// {@link bridgeIterator} is the single answer: one plain object literal carrying
// `next`, `return`, `throw`, and `Symbol.asyncIterator` as its own properties.
// Everything public goes through it — {@link bridgeStream} for pull-style
// producers, {@link AsyncQueue.stream} for push-style ones — which is why the
// main-process and renderer surfaces can share one implementation.

import { asSDKException } from '../errors';

/** Where a producer pushes stream items. */
export interface StreamSink<T> {
  push(value: T): void;
  end(): void;
  fail(error: unknown): void;
}

/**
 * The one iterator shape that survives `contextBridge`.
 *
 * `Symbol.asyncIterator` is installed on the returned literal rather than
 * inherited, and it closes over `iterator` instead of returning `this` — a
 * bridged copy is a different object, and `this` inside it would be that copy
 * rather than the one holding the queue.
 */
function bridgeIterator<T>(
  next: () => Promise<IteratorResult<T>>,
  finish: () => Promise<IteratorResult<T>>
): AsyncIterableIterator<T> {
  const iterator: AsyncIterableIterator<T> = {
    [Symbol.asyncIterator]: () => iterator,
    next,
    return: finish,
    async throw(error?: unknown): Promise<IteratorResult<T>> {
      await finish();
      throw asSDKException(error);
    },
  };
  return iterator;
}

/**
 * Adapt a push-style producer into a lazily consumed AsyncIterable. `producer`
 * starts on the first `next()`, so nothing runs for a stream that is never
 * iterated. Breaking the loop calls `onCancel` and drains the producer.
 */
export function bridgeStream<T>(
  producer: (sink: StreamSink<T>) => void | Promise<void>,
  onCancel?: () => void | Promise<void>
): AsyncIterableIterator<T> {
  const queue: T[] = [];
  let done = false;
  let failure: unknown = null;
  let started = false;
  let cancelled = false;
  let wake: (() => void) | null = null;

  const signal = (): void => {
    const w = wake;
    wake = null;
    if (w) w();
  };

  const sink: StreamSink<T> = {
    push(value) {
      if (cancelled) return;
      queue.push(value);
      signal();
    },
    end() {
      done = true;
      signal();
    },
    fail(error) {
      failure = error;
      done = true;
      signal();
    },
  };

  const start = (): void => {
    if (started) return;
    started = true;
    try {
      const maybe = producer(sink);
      if (maybe && typeof (maybe as Promise<void>).then === 'function') {
        (maybe as Promise<void>).then(
          () => sink.end(),
          (e) => sink.fail(e)
        );
      }
    } catch (e) {
      sink.fail(e);
    }
  };

  const finish = async (): Promise<IteratorResult<T>> => {
    if (!cancelled) {
      cancelled = true;
      queue.length = 0;
      // Wake a `next()` that is parked waiting for an item, so it returns
      // `{done:true}` instead of hanging forever. `return()` is not always
      // called from inside the consumer's own loop: `for await` cannot reach a
      // page (contextBridge drops `Symbol.asyncIterator`), so a renderer drives
      // `next()` in one place and cancels from another — a Stop button, an
      // unmount, an unsubscribe. Without this signal that cancel strands the
      // reader on a promise nothing will ever resolve.
      signal();
      try {
        await onCancel?.();
      } catch {
        // A cancel that itself fails must not mask the caller's own control flow.
      }
    }
    return { value: undefined as unknown as T, done: true };
  };

  return bridgeIterator<T>(async (): Promise<IteratorResult<T>> => {
    start();
    for (;;) {
      if (queue.length) return { value: queue.shift() as T, done: false };
      if (failure) {
        const error = failure;
        failure = null;
        throw asSDKException(error);
      }
      if (done || cancelled) return { value: undefined as unknown as T, done: true };
      await new Promise<void>((resolve) => {
        wake = resolve;
      });
    }
  }, finish);
}

/** Wrap a ready array as a bridge-safe stream (used for synthetic events). */
export function streamOf<T>(values: T[]): AsyncIterableIterator<T> {
  return bridgeStream<T>((sink) => {
    for (const v of values) sink.push(v);
    sink.end();
  });
}

/** Drain a stream, returning every item. */
export async function collect<T>(source: AsyncIterable<T>): Promise<T[]> {
  const out: T[] = [];
  for await (const item of source) out.push(item);
  return out;
}

/**
 * A push queue that is also an `AsyncIterable`. Unlike {@link bridgeStream},
 * `push` works before the consumer ever calls `next()` — nothing is lost when
 * a producer (e.g. `SttStream.pushFrame`) starts feeding it before the
 * caller starts reading `events`. Used by the live `stt.openStream` /
 * `vad.openStream` sessions, which are pushed into from outside their own
 * async iteration.
 */
export class AsyncQueue<T> implements AsyncIterable<T> {
  private readonly buffer: T[] = [];
  private wake: (() => void) | null = null;
  private ended = false;
  private failure: unknown = null;

  /**
   * An own property, not a prototype method: a queue handed straight to
   * `contextBridge` would otherwise arrive in the page without iterability.
   * Public streams still cross as {@link stream}'s plain object — this only
   * keeps the class itself honest when it is iterated directly.
   */
  readonly [Symbol.asyncIterator] = (): AsyncIterableIterator<T> => this.stream();

  /** Enqueue one item. A no-op once the queue has ended. */
  push(value: T): void {
    if (this.ended) return;
    this.buffer.push(value);
    this.signal();
  }

  /** End the queue with a terminal error; the next `next()` throws it. */
  fail(error: unknown): void {
    if (this.ended) return;
    this.failure = error;
    this.ended = true;
    this.signal();
  }

  /** End the queue normally once every buffered item has been read. */
  complete(): void {
    if (this.ended) return;
    this.ended = true;
    this.signal();
  }

  private signal(): void {
    const wake = this.wake;
    this.wake = null;
    if (wake) wake();
  }

  /**
   * A bridge-safe view of this queue, and the shape `SttStream.events` /
   * `VadStream.events` publish. Iterating it drains the same buffer, so two
   * views compete for items rather than each seeing every one — a queue has one
   * consumer by construction.
   */
  stream(): AsyncIterableIterator<T> {
    return bridgeIterator<T>(
      async (): Promise<IteratorResult<T>> => {
        for (;;) {
          if (this.buffer.length) return { value: this.buffer.shift() as T, done: false };
          if (this.failure) {
            const error = this.failure;
            this.failure = null;
            throw asSDKException(error);
          }
          if (this.ended) return { value: undefined as unknown as T, done: true };
          await new Promise<void>((resolve) => {
            this.wake = resolve;
          });
        }
      },
      // Walking away from the loop stops delivery but does not end the queue:
      // the producer is outside it and may still be pushing, and `complete()` /
      // `fail()` are what say the session is over.
      async (): Promise<IteratorResult<T>> => ({ value: undefined as unknown as T, done: true })
    );
  }
}
