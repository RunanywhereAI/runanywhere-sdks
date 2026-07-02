export class AsyncQueue<T> implements AsyncIterable<T> {
  private buffer: T[] = [];
  private resolveNext: ((v: IteratorResult<T>) => void) | null = null;
  private done = false;
  private error: Error | null = null;

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

  complete(): void {
    if (this.done) return;
    this.done = true;
    if (this.resolveNext) {
      const r = this.resolveNext;
      this.resolveNext = null;
      r({ value: undefined as unknown as T, done: true });
    }
  }

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
