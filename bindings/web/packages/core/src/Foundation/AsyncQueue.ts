/**
 * AsyncQueue.ts
 *
 * Helper that extracts the `tokenQueue: T[] +
 * resolveNext` async-iteration pattern that was inlined inside multiple
 * Web SDK files (RunAnywhere+TextGeneration.ts, RunAnywhere+STT.ts, etc.)
 * into one reusable producer/consumer pair.
 *
 * Pattern:
 *   const q = new AsyncQueue<string>();
 *   // Producer side (e.g. an Emscripten WASM token callback):
 *   q.push(token);
 *   // ...later:
 *   q.complete();          // signal end-of-stream
 *   q.fail(error);         // signal abnormal termination
 *
 *   // Consumer side:
 *   for await (const v of q) { ... }   // breaks when complete() is called
 *
 * Replaces the boilerplate in `streamGenerate()` (token queue), `streamSTT`,
 * and similar Web-SDK iterator constructions. ~50 LOC of duplicated
 * scaffolding becomes 3-4 lines per call site.
 */

/** Async queue with a single producer + single consumer (for-await). */
export class AsyncQueue<T> implements AsyncIterable<T> {
  private buffer: T[] = [];
  private wake: (() => void) | null = null;
  private done = false;
  private error: Error | null = null;

  /**
   * Wake a parked consumer. Producers only ever signal; `next()` re-reads the
   * queue state itself, which is what keeps `fail()` from having to resolve a
   * waiter it cannot reject. Mirrors `AsyncQueue` in
   * `@runanywhere/proto-ts/streams/push`.
   */
  private signal(): void {
    const wake = this.wake;
    this.wake = null;
    if (wake) wake();
  }

  /** Producer: push the next value. Discarded if the queue is closed. */
  push(value: T): void {
    if (this.done) return;
    this.buffer.push(value);
    this.signal();
  }

  /** Producer: signal normal end-of-stream. Idempotent. */
  complete(): void {
    if (this.done) return;
    this.done = true;
    this.signal();
  }

  /** Producer: signal abnormal termination. Next consumer await throws. */
  fail(error: Error): void {
    if (this.done) return;
    this.done = true;
    this.error = error;
    this.signal();
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: async (): Promise<IteratorResult<T>> => {
        for (;;) {
          if (this.buffer.length > 0) {
            return { value: this.buffer.shift()!, done: false };
          }
          if (this.error) throw this.error;
          if (this.done) return { value: undefined as unknown as T, done: true };
          await new Promise<void>((r) => { this.wake = r; });
        }
      },
    };
  }
}
