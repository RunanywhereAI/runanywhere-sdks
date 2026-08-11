/**
 * Push-based `AsyncIterable` plumbing shared by every streaming verb.
 *
 * Queue / iterator logic lives in `@runanywhere/proto-ts/streams/push`. This
 * module keeps RN's public `StreamController.finish()` name and fire-and-forget
 * producer semantics (async preflight returns before the native stream ends).
 */

import {
  deferStream,
  forEachStream,
  mapStream,
  pushStream as sharedPushStream,
} from '@runanywhere/proto-ts/streams/push';

export { deferStream, forEachStream, mapStream };

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
 *
 * Shared `pushStream` auto-ends when a returned Promise settles (Electron).
 * RN producers are often `async` for preflight but keep the stream open until
 * they call `finish()`/`fail()` themselves — so the returned Promise is never
 * handed to the shared helper.
 */
export function pushStream<T>(
  start: (controller: StreamController<T>) => void | Promise<void>,
  cancel?: () => void | Promise<void>
): AsyncIterable<T> {
  return sharedPushStream<T>((sink) => {
    const controller: StreamController<T> = {
      get closed() {
        return sink.closed;
      },
      push(value: T): void {
        sink.push(value);
      },
      fail(error: unknown): void {
        sink.fail(error);
      },
      finish(): void {
        sink.end();
      },
    };
    void Promise.resolve(start(controller)).catch((error: unknown) => {
      sink.fail(error);
    });
  }, cancel);
}
