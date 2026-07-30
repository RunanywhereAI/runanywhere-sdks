// iter.ts — AsyncIterable plumbing for the streaming verbs.
//
// Every stream the SDK returns must be *bridge safe*: Electron's contextBridge
// cannot clone a generator object, so an iterator has to be a plain object whose
// `Symbol.asyncIterator` returns `this` and whose `next()` resolves a plain
// `{ value, done }`. `bridgeStream` is the only constructor used for public
// streams, which is why the main-process and renderer surfaces can share one
// implementation.

import { asSDKException } from '../errors';

/** Where a producer pushes stream items. */
export interface StreamSink<T> {
  push(value: T): void;
  end(): void;
  fail(error: unknown): void;
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
      try {
        await onCancel?.();
      } catch {
        // A cancel that itself fails must not mask the caller's own control flow.
      }
    }
    return { value: undefined as unknown as T, done: true };
  };

  return {
    [Symbol.asyncIterator]() {
      return this;
    },
    async next(): Promise<IteratorResult<T>> {
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
    },
    return: finish,
    async throw(error?: unknown): Promise<IteratorResult<T>> {
      await finish();
      throw asSDKException(error);
    },
  };
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
