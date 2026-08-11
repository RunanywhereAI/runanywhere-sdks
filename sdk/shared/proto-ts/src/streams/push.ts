/**
 * Hand-authored push → AsyncIterable helpers for Web / React Native / Electron.
 *
 * Kept in a file that `idl/codegen/generate_streams.sh` does NOT touch (that
 * script only writes `*_service_stream.ts`). Generated wrappers live beside
 * this file and import `_streamFactory.ts`.
 *
 * Constraints preserved across all three SDKs:
 *   - Lazy start: the producer runs on the first `next()`, not on construction.
 *   - Cancel/cleanup on iterator `return()`.
 *   - Hermes-safe: consumers may drive via manual `iterator.next()` loops;
 *     nothing here requires `for await...of` over a Nitro iterable.
 *   - Electron `contextBridge`-safe: iterators are plain object literals with
 *     `next` / `return` / `throw` / `Symbol.asyncIterator` as OWN properties
 *     (prototype methods are stripped by contextBridge).
 *   - No platform APIs (no Worker, JSI, Node built-ins).
 */

/** Sink handed to a push-style stream producer. */
export interface StreamSink<T> {
  /** Deliver one value to the consumer. */
  push(value: T): void;
  /** End the stream normally. */
  end(): void;
  /** Throw into the consumer and end the stream. */
  fail(error: unknown): void;
  /** True once the stream has ended or been cancelled. */
  readonly closed: boolean;
}

/** Alias kept for RN call-site familiarity (`StreamController`). */
export type StreamController<T> = StreamSink<T>;

/**
 * Own-property AsyncIterableIterator that survives Electron `contextBridge`.
 *
 * `Symbol.asyncIterator` closes over `iterator` rather than returning `this`,
 * because a bridged copy is a different object.
 */
function bridgeIterator<T>(
  next: () => Promise<IteratorResult<T>>,
  finish: () => Promise<IteratorResult<T>>,
): AsyncIterableIterator<T> {
  const iterator: AsyncIterableIterator<T> = {
    [Symbol.asyncIterator]: () => iterator,
    next,
    return: finish,
    async throw(error?: unknown): Promise<IteratorResult<T>> {
      await finish();
      throw error;
    },
  };
  return iterator;
}

const doneResult = <T>(): IteratorResult<T> => ({
  value: undefined as unknown as T,
  done: true,
});

/**
 * Adapt a push-style producer into a lazily consumed AsyncIterableIterator.
 *
 * `producer` starts on the first `next()`. If it returns a Promise, the sink
 * auto-`end()`s when that Promise settles (Electron pattern); a synchronous
 * producer must call `end()` / `fail()` itself (RN pattern). Breaking the
 * consumer loop calls `onCancel` and drains waiters.
 */
export function pushStream<T>(
  producer: (sink: StreamSink<T>) => void | Promise<void>,
  onCancel?: () => void | Promise<void>,
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
    get closed() {
      return done || cancelled;
    },
    push(value: T): void {
      if (cancelled || done) return;
      queue.push(value);
      signal();
    },
    end(): void {
      if (done) return;
      done = true;
      signal();
    },
    fail(error: unknown): void {
      if (done) return;
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
      if (maybe != null && typeof (maybe as Promise<void>).then === 'function') {
        (maybe as Promise<void>).then(
          () => sink.end(),
          (e: unknown) => sink.fail(e),
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
      // Wake a parked `next()` so cancel from outside the consumer loop
      // (Stop button / unmount) does not hang forever.
      signal();
      if (started && onCancel) {
        try {
          await onCancel();
        } catch {
          // Cancel is best-effort; the consumer already stopped listening.
        }
      }
    }
    return doneResult<T>();
  };

  return bridgeIterator<T>(async (): Promise<IteratorResult<T>> => {
    start();
    for (;;) {
      if (queue.length > 0) return { value: queue.shift() as T, done: false };
      if (failure !== null) {
        const error = failure;
        failure = null;
        throw error;
      }
      if (done || cancelled) return doneResult<T>();
      await new Promise<void>((resolve) => {
        wake = resolve;
      });
    }
  }, finish);
}

/** Alias matching Electron's historical name. */
export const bridgeStream = pushStream;

/**
 * Build an AsyncIterable over a push subscription (EventBus pattern).
 *
 * The subscription is created on the first `next()` and released via
 * `return()`. Multiple concurrent `next()` waiters resolve in FIFO order.
 */
export function iterableFromSubscription<T>(
  subscribe: (listener: (value: T) => void) => () => void,
): AsyncIterableIterator<T> {
  const queue: T[] = [];
  const waiters: Array<(value: IteratorResult<T>) => void> = [];
  let closed = false;
  let unsubscribe: (() => void) | null = null;

  const ensureSubscribed = (): void => {
    if (unsubscribe !== null || closed) return;
    unsubscribe = subscribe((value) => {
      if (waiters.length > 0) {
        waiters.shift()!({ value, done: false });
      } else {
        queue.push(value);
      }
    });
  };

  return bridgeIterator<T>(
    (): Promise<IteratorResult<T>> => {
      ensureSubscribed();
      if (queue.length > 0) {
        return Promise.resolve({ value: queue.shift() as T, done: false });
      }
      if (closed) return Promise.resolve(doneResult<T>());
      return new Promise((resolve) => {
        waiters.push(resolve);
      });
    },
    (): Promise<IteratorResult<T>> => {
      closed = true;
      if (unsubscribe !== null) {
        unsubscribe();
        unsubscribe = null;
      }
      const result = doneResult<T>();
      for (const waiter of waiters.splice(0)) {
        waiter(result);
      }
      return Promise.resolve(result);
    },
  );
}

/**
 * Project every value of a stream through `transform`, dropping the ones it
 * maps to `undefined`.
 */
export function mapStream<T, U>(
  source: AsyncIterable<T>,
  transform: (value: T) => U | undefined,
): AsyncIterableIterator<U> {
  const iterator = source[Symbol.asyncIterator]();
  return bridgeIterator<U>(
    async (): Promise<IteratorResult<U>> => {
      for (;;) {
        const step = await iterator.next();
        if (step.done) return doneResult<U>();
        const mapped = transform(step.value);
        if (mapped !== undefined) return { value: mapped, done: false };
      }
    },
    async (): Promise<IteratorResult<U>> => {
      await iterator.return?.();
      return doneResult<U>();
    },
  );
}

/**
 * Flatten a stream that can only be built after an async preflight into a
 * plain AsyncIterable, so consumers never await before iterating.
 */
export function deferStream<T>(
  factory: () => Promise<AsyncIterable<T>>,
): AsyncIterableIterator<T> {
  let inner: AsyncIterator<T> | null = null;
  const ensureInner = async (): Promise<AsyncIterator<T>> => {
    if (!inner) {
      inner = (await factory())[Symbol.asyncIterator]();
    }
    return inner;
  };
  return bridgeIterator<T>(
    async (): Promise<IteratorResult<T>> => (await ensureInner()).next(),
    async (): Promise<IteratorResult<T>> => {
      if (inner) await inner.return?.();
      return doneResult<T>();
    },
  );
}

/**
 * Drive an AsyncIterable to completion with a manual `next()` loop.
 *
 * Hermes cannot iterate Nitro-backed streams with `for await...of`, so
 * SDK-internal consumers should prefer this helper (or an equivalent loop).
 */
export async function forEachStream<T>(
  source: AsyncIterable<T>,
  handle: (value: T) => void | Promise<void>,
): Promise<void> {
  const iterator = source[Symbol.asyncIterator]();
  try {
    for (;;) {
      const step = await iterator.next();
      if (step.done) return;
      await handle(step.value);
    }
  } finally {
    await iterator.return?.();
  }
}

/** Wrap a ready array as a bridge-safe stream (synthetic events / tests). */
export function streamOf<T>(values: readonly T[]): AsyncIterableIterator<T> {
  return pushStream<T>((sink) => {
    for (const v of values) sink.push(v);
    sink.end();
  });
}

/** Drain a stream, returning every item. Uses {@link forEachStream} (Hermes-safe). */
export async function collect<T>(source: AsyncIterable<T>): Promise<T[]> {
  const out: T[] = [];
  await forEachStream(source, (item) => {
    out.push(item);
  });
  return out;
}

/**
 * A push queue that is also an AsyncIterable. Unlike {@link pushStream},
 * `push` works before the consumer ever calls `next()` — nothing is lost when
 * a producer starts feeding it before the caller starts reading.
 */
export class AsyncQueue<T> implements AsyncIterable<T> {
  private readonly buffer: T[] = [];
  private wake: (() => void) | null = null;
  private ended = false;
  private failure: unknown = null;

  /**
   * Own property (not a prototype method) so a queue handed to
   * `contextBridge` keeps its iterability.
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

  /** Bridge-safe view that drains this queue's buffer. */
  stream(): AsyncIterableIterator<T> {
    return bridgeIterator<T>(
      async (): Promise<IteratorResult<T>> => {
        for (;;) {
          if (this.buffer.length > 0) {
            return { value: this.buffer.shift() as T, done: false };
          }
          if (this.failure !== null) {
            const error = this.failure;
            this.failure = null;
            throw error;
          }
          if (this.ended) return doneResult<T>();
          await new Promise<void>((resolve) => {
            this.wake = resolve;
          });
        }
      },
      // Walking away stops delivery but does not end the queue: the producer
      // is outside it and may still be pushing.
      async (): Promise<IteratorResult<T>> => doneResult<T>(),
    );
  }
}
