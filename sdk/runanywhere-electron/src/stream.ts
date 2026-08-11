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

import { asSDKException } from './errors';

/** Aggregate metrics for a completed generation (mirrors the other SDKs' result). */
export interface LLMGenerationResult {
  text: string;
  tokenCount: number;
  timeToFirstTokenMs: number;
  tokensPerSecond: number;
  totalTimeMs: number;
}

/**
 * A streamed generation event (mirrors the Swift/Kotlin/RN `LLMStreamEvent`):
 * non-final events carry a `token`; the final event carries the aggregated
 * `result` with timing metrics and an empty token.
 */
export interface LLMStreamEvent {
  token: string;
  isFinal: boolean;
  result?: LLMGenerationResult;
}

/**
 * Wrap a token AsyncIterable as a stream of LLMStreamEvent, computing time-to-
 * first-token and tokens/second — so callers get the same metrics the other
 * SDKs surface. `now` is injectable for deterministic tests.
 */
export async function* streamWithMetrics(
  source: AsyncIterable<string>,
  now: () => number = () => Date.now()
): AsyncIterableIterator<LLMStreamEvent> {
  const start = now();
  let firstAt = -1;
  let count = 0;
  let text = '';
  for await (const token of source) {
    if (firstAt < 0) firstAt = now();
    count += 1;
    text += token;
    yield { token, isFinal: false };
  }
  const end = now();
  const genMs = firstAt < 0 ? 0 : end - firstAt;
  yield {
    token: '',
    isFinal: true,
    result: {
      text,
      tokenCount: count,
      timeToFirstTokenMs: firstAt < 0 ? 0 : firstAt - start,
      tokensPerSecond: genMs > 0 ? count / (genMs / 1000) : 0,
      totalTimeMs: end - start,
    },
  };
}

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
