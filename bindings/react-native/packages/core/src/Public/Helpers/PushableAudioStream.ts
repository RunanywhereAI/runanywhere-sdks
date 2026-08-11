/**
 * PushableAudioStream.ts
 *
 * RN platform adaptation of Swift's `AsyncStream<Data>` — JavaScript has no
 * stdlib pushable AsyncIterable, so the SDK ships the adapter every
 * streaming-audio consumer needs (feeding microphone chunks into
 * `RunAnywhere.transcribeStream()` / `RunAnywhere.streamVAD()`).
 *
 * Semantics: single async consumer; `push` drops empty chunks and is a no-op
 * after close; `close` resolves all pending waiters with `done` and makes
 * the iterator return done thereafter; `iterable.return()` also closes.
 */

export interface PushableAudioStream {
  /** Feed to `RunAnywhere.transcribeStream()` / `RunAnywhere.streamVAD()`. */
  iterable: AsyncIterable<Uint8Array>;
  push(chunk: Uint8Array): void;
  close(): void;
}

export function createPushableAudioStream(): PushableAudioStream {
  const queue: Uint8Array[] = [];
  const waiters: Array<(result: IteratorResult<Uint8Array>) => void> = [];
  let closed = false;

  const finish = () => {
    closed = true;
    while (waiters.length > 0) {
      waiters.shift()?.({
        value: undefined as unknown as Uint8Array,
        done: true,
      });
    }
  };

  return {
    iterable: {
      [Symbol.asyncIterator](): AsyncIterator<Uint8Array> {
        return {
          next(): Promise<IteratorResult<Uint8Array>> {
            const chunk = queue.shift();
            if (chunk) return Promise.resolve({ value: chunk, done: false });
            if (closed) {
              return Promise.resolve({
                value: undefined as unknown as Uint8Array,
                done: true,
              });
            }
            return new Promise((resolve) => waiters.push(resolve));
          },
          return(): Promise<IteratorResult<Uint8Array>> {
            finish();
            return Promise.resolve({
              value: undefined as unknown as Uint8Array,
              done: true,
            });
          },
        };
      },
    },
    push(chunk: Uint8Array) {
      if (closed || chunk.byteLength === 0) return;
      const waiter = waiters.shift();
      if (waiter) {
        waiter({ value: chunk, done: false });
      } else {
        queue.push(chunk);
      }
    },
    close: finish,
  };
}
