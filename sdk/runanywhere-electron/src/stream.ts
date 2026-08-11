// stream.ts — adapt an addon streaming call (callback-per-token + a completion
// Promise) into a lazily-consumed AsyncIterable of tokens. Kept separate from
// bridge.ts (which force-loads the native addon on import) so this pure adapter
// can be used and unit-tested without the .node present.
//
// Deliberately local (not `@runanywhere/proto-ts/streams/push`):
//   - eager `start()` at construction (shared `bridgeStream` is lazy)
//   - sticky rejection across subsequent `next()` calls
//   - tokens pushed after the completion Promise resolves are still yielded
// Shared helpers are used by `api/iter.ts` for the public streaming verbs.
//
// Terminal TTFT / tok/s / token counts / wall time come from commons on the
// completed stream event (llm-abi / text.ts). This module only moves token
// strings — it does not fabricate metrics.

import { asSDKException } from './errors';

/**
 * Adapt an addon streaming call — `start(onToken) -> Promise<void>` — into a
 * lazily-consumed AsyncIterable of tokens. Tokens buffer as they arrive; the
 * iterator ends when the promise resolves and rejects if it rejects.
 */
export function toAsyncIterable(
  start: (onToken: (t: string) => void) => Promise<unknown>
): AsyncIterableIterator<string> {
  const queue: string[] = [];
  let done = false;
  let err: unknown = null;
  let wake: (() => void) | null = null;
  const signal = (): void => {
    const w = wake;
    wake = null;
    if (w) w();
  };

  start((t) => {
    queue.push(t);
    signal();
  }).then(
    () => {
      done = true;
      signal();
    },
    (e: unknown) => {
      err = e;
      done = true;
      signal();
    }
  );

  // Own-property methods (same shape as shared `bridgeIterator`) so a copy that
  // crossed `contextBridge` would still be iterable — though this helper is
  // main/utility-process only today.
  const iterator: AsyncIterableIterator<string> = {
    [Symbol.asyncIterator]: () => iterator,
    async next(): Promise<IteratorResult<string>> {
      for (;;) {
        if (queue.length) return { value: queue.shift() as string, done: false };
        if (err) throw asSDKException(err);
        if (done) return { value: undefined as unknown as string, done: true };
        await new Promise<void>((resolve) => {
          wake = resolve;
        });
      }
    },
  };
  return iterator;
}
