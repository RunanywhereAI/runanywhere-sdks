// stream.ts — adapt an addon streaming call (callback-per-token + a completion
// Promise) into a lazily-consumed AsyncIterable of tokens. Kept separate from
// bridge.ts (which force-loads the native addon on import) so this pure adapter
// can be used and unit-tested without the .node present.

/**
 * Adapt an addon streaming call — `start(onToken) -> Promise<void>` — into a
 * lazily-consumed AsyncIterable of tokens. Tokens buffer as they arrive; the
 * iterator ends when the promise resolves and rejects if it rejects.
 */
export function toAsyncIterable(
  start: (onToken: (t: string) => void) => Promise<void>
): AsyncIterableIterator<string> {
  const queue: string[] = [];
  let done = false;
  let err: unknown = null;
  let wake: (() => void) | null = null;
  const signal = () => {
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
    (e) => {
      err = e;
      done = true;
      signal();
    }
  );

  return {
    [Symbol.asyncIterator]() {
      return this;
    },
    async next(): Promise<IteratorResult<string>> {
      for (;;) {
        if (queue.length) return { value: queue.shift() as string, done: false };
        if (err) throw err;
        if (done) return { value: undefined as unknown as string, done: true };
        await new Promise<void>((r) => {
          wake = r;
        });
      }
    },
  };
}
