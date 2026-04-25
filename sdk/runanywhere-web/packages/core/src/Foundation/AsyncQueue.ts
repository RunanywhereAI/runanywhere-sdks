/**
 * AsyncQueue.ts
 *
 * v2 close-out Phase 14 helper. Extracts the `tokenQueue: T[] +
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
  private resolveNext: ((v: IteratorResult<T>) => void) | null = null;
  private done = false;
  private error: Error | null = null;

  /** Producer: push the next value. Discarded if the queue is closed. */
  push(value: T): void {
    if (this.done) return;
    if (this.resolveNext) {
      const r = this.resolveNext;
      this.resolveNext = null;
      r({ value, done: false });
    } else {
      this.buffer.push(value);
    }
  }

  /** Producer: signal normal end-of-stream. Idempotent. */
  complete(): void {
    if (this.done) return;
    this.done = true;
    if (this.resolveNext) {
      const r = this.resolveNext;
      this.resolveNext = null;
      r({ value: undefined as unknown as T, done: true });
    }
  }

  /** Producer: signal abnormal termination. Next consumer await throws. */
  fail(error: Error): void {
    if (this.done) return;
    this.done = true;
    this.error = error;
    if (this.resolveNext) {
      const r = this.resolveNext;
      this.resolveNext = null;
      r({ value: undefined as unknown as T, done: true });
    }
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: (): Promise<IteratorResult<T>> => {
        if (this.buffer.length > 0) {
          return Promise.resolve({ value: this.buffer.shift()!, done: false });
        }
        if (this.error) return Promise.reject(this.error);
        if (this.done) return Promise.resolve({ value: undefined as unknown as T, done: true });
        return new Promise((r) => { this.resolveNext = r; });
      },
    };
  }
}
