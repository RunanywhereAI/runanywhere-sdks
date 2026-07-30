/**
 * Push-based `AsyncIterable` plumbing shared by every streaming verb.
 *
 * Native proto-byte callbacks are push sources; consumers pull. Each factory
 * here bridges the two, starts the native work lazily on the first `next()`,
 * and routes `iterator.return()` to the cancel hook so breaking out of a loop
 * tears the native subscription down.
 */

/** Sink handed to a stream producer. */
export interface StreamController<T> {
  /** Deliver one value to the consumer. */
  push(value: T): void;
  /** Throw into the consumer and end the stream. */
  fail(error: unknown): void;
  /** End the stream normally. */
  finish(): void;
  /** True once the stream has ended or been cancelled. */
  readonly closed: boolean;
}

/**
 * Build an `AsyncIterable` fed by `start`, which runs on the first `next()`.
 *
 * `cancel` runs when the consumer breaks out of the loop or the stream ends
 * early, and is the hook that cancels the underlying native work.
 */
export function pushStream<T>(
  start: (controller: StreamController<T>) => void | Promise<void>,
  cancel?: () => void | Promise<void>
): AsyncIterable<T> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<T> {
      const queue: T[] = [];
      let resolver: ((result: IteratorResult<T>) => void) | null = null;
      let done = false;
      let started = false;
      let failure: unknown = null;

      const endResult = (): IteratorResult<T> => ({
        value: undefined as unknown as T,
        done: true,
      });

      const controller: StreamController<T> = {
        get closed() {
          return done;
        },
        push(value: T): void {
          if (done) return;
          if (resolver) {
            const resolve = resolver;
            resolver = null;
            resolve({ value, done: false });
          } else {
            queue.push(value);
          }
        },
        fail(error: unknown): void {
          if (done) return;
          failure = error;
          controller.finish();
        },
        finish(): void {
          if (done) return;
          done = true;
          if (resolver) {
            const resolve = resolver;
            resolver = null;
            resolve(endResult());
          }
        },
      };

      const ensureStarted = async (): Promise<void> => {
        if (started) return;
        started = true;
        try {
          await start(controller);
        } catch (error) {
          controller.fail(error);
        }
      };

      const throwIfFailed = (): void => {
        if (failure === null) return;
        const error = failure;
        failure = null;
        throw error;
      };

      return {
        async next(): Promise<IteratorResult<T>> {
          await ensureStarted();
          if (queue.length > 0) {
            return { value: queue.shift() as T, done: false };
          }
          throwIfFailed();
          if (done) return endResult();
          const result = await new Promise<IteratorResult<T>>((resolve) => {
            resolver = resolve;
          });
          throwIfFailed();
          return result;
        },
        async return(): Promise<IteratorResult<T>> {
          const wasStarted = started;
          controller.finish();
          if (wasStarted && cancel) {
            try {
              await cancel();
            } catch {
              // Cancel is best-effort; the consumer already stopped listening.
            }
          }
          return endResult();
        },
      };
    },
  };
}

/**
 * Project every value of a stream through `transform`, dropping the ones it
 * maps to `undefined`.
 */
export function mapStream<T, U>(
  source: AsyncIterable<T>,
  transform: (value: T) => U | undefined
): AsyncIterable<U> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<U> {
      const iterator = source[Symbol.asyncIterator]();
      return {
        async next(): Promise<IteratorResult<U>> {
          for (;;) {
            const step = await iterator.next();
            if (step.done) {
              return { value: undefined as unknown as U, done: true };
            }
            const mapped = transform(step.value);
            if (mapped !== undefined) return { value: mapped, done: false };
          }
        },
        async return(): Promise<IteratorResult<U>> {
          await iterator.return?.();
          return { value: undefined as unknown as U, done: true };
        },
      };
    },
  };
}

/**
 * Flatten a stream that can only be built after an async preflight into a
 * plain `AsyncIterable`, so consumers never await before iterating.
 */
export function deferStream<T>(
  factory: () => Promise<AsyncIterable<T>>
): AsyncIterable<T> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<T> {
      let inner: AsyncIterator<T> | null = null;
      const ensureInner = async (): Promise<AsyncIterator<T>> => {
        if (!inner) {
          inner = (await factory())[Symbol.asyncIterator]();
        }
        return inner;
      };
      return {
        async next(): Promise<IteratorResult<T>> {
          return (await ensureInner()).next();
        },
        async return(): Promise<IteratorResult<T>> {
          if (inner) await inner.return?.();
          return { value: undefined as unknown as T, done: true };
        },
      };
    },
  };
}

/**
 * Drive an `AsyncIterable` to completion with a manual `next()` loop.
 *
 * Hermes cannot iterate the Nitro-backed streams with `for await...of`, so
 * every consumer inside the SDK goes through this helper.
 */
export async function forEachStream<T>(
  source: AsyncIterable<T>,
  handle: (value: T) => void | Promise<void>
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
