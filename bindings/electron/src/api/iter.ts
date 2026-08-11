// iter.ts — AsyncIterable plumbing for the streaming verbs.
//
// Queue / own-property iterator machinery lives in
// `@runanywhere/proto-ts/streams/push` (contextBridge-safe: `next` / `return` /
// `throw` / `Symbol.asyncIterator` are own properties). This file is a thin
// Electron binding that coerces stream failures through {@link asSDKException}
// so renderer and main consumers always see the house error type.

import {
  AsyncQueue as SharedAsyncQueue,
  bridgeStream as sharedBridgeStream,
  collect as sharedCollect,
  streamOf as sharedStreamOf,
  type StreamSink,
} from '@runanywhere/proto-ts/streams/push';

import { asSDKException } from '../errors';

export type { StreamSink };

/** Wrap a shared sink so `fail` always surfaces an {@link SDKException}. */
function withTypedFail<T>(sink: StreamSink<T>): StreamSink<T> {
  return {
    get closed() {
      return sink.closed;
    },
    push(value) {
      sink.push(value);
    },
    end() {
      sink.end();
    },
    fail(error) {
      sink.fail(asSDKException(error));
    },
  };
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
  return sharedBridgeStream<T>((sink) => producer(withTypedFail(sink)), onCancel);
}

/** Wrap a ready array as a bridge-safe stream (used for synthetic events). */
export function streamOf<T>(values: readonly T[]): AsyncIterableIterator<T> {
  return sharedStreamOf(values);
}

/** Drain a stream, returning every item. */
export async function collect<T>(source: AsyncIterable<T>): Promise<T[]> {
  return sharedCollect(source);
}

/**
 * A push queue that is also an `AsyncIterable`. Unlike {@link bridgeStream},
 * `push` works before the consumer ever calls `next()` — nothing is lost when
 * a producer (e.g. `SttStream.pushFrame`) starts feeding it before the
 * caller starts reading `events`. Used by the live `stt.openStream` /
 * `vad.openStream` sessions, which are pushed into from outside their own
 * async iteration.
 */
export class AsyncQueue<T> extends SharedAsyncQueue<T> {
  /** End the queue with a terminal error; the next `next()` throws it. */
  override fail(error: unknown): void {
    super.fail(asSDKException(error));
  }
}
