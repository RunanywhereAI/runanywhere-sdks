/**
 * StreamAccumulator.ts
 *
 * Accumulates tokens during streaming for later parsing
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/StreamAccumulator.swift
 */

/**
 * Accumulates tokens during streaming for later parsing
 * Matches iOS StreamAccumulator actor
 *
 * Note: TypeScript doesn't have actors, but this class provides
 * similar functionality with promises for synchronization
 */
export class StreamAccumulator {
  private text: string = '';
  private isComplete: boolean = false;
  private completionResolvers: Array<() => void> = [];

  /**
   * Append a token to the accumulator
   */
  public append(token: string): void {
    this.text += token;
  }

  /**
   * Get the full accumulated text
   */
  public get fullText(): string {
    return this.text;
  }

  /**
   * Mark the stream as complete
   */
  public markComplete(): void {
    if (this.isComplete) {
      return;
    }

    this.isComplete = true;

    // Resolve all waiting promises
    for (const resolver of this.completionResolvers) {
      resolver();
    }
    this.completionResolvers = [];
  }

  /**
   * Wait for the stream to complete
   * Returns a promise that resolves when markComplete() is called
   */
  public async waitForCompletion(): Promise<void> {
    if (this.isComplete) {
      return Promise.resolve();
    }

    return new Promise<void>((resolve) => {
      this.completionResolvers.push(resolve);
    });
  }

  /**
   * Reset the accumulator for reuse
   */
  public reset(): void {
    this.text = '';
    this.isComplete = false;
    this.completionResolvers = [];
  }

  /**
   * Check if the stream is complete
   */
  public get complete(): boolean {
    return this.isComplete;
  }
}
