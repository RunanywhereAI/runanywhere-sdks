/**
 * PerformanceMetrics.ts
 *
 * Detailed performance metrics
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/PerformanceMetrics.swift
 */

/**
 * Detailed performance metrics
 */
export interface PerformanceMetrics {
  /** Time spent on tokenization (milliseconds) */
  readonly tokenizationTimeMs: number;

  /** Time spent on inference (milliseconds) */
  readonly inferenceTimeMs: number;

  /** Time spent on post-processing (milliseconds) */
  readonly postProcessingTimeMs: number;

  /** Tokens generated per second */
  readonly tokensPerSecond: number;

  /** Peak memory usage during generation */
  readonly peakMemoryUsage: number; // Int64

  /** Queue wait time if any (milliseconds) */
  readonly queueWaitTimeMs: number;

  // MARK: - Thinking Mode Metrics

  /** Time to first token (milliseconds) - time from request start to first token */
  readonly timeToFirstTokenMs: number | null;

  /** Time spent in thinking mode (milliseconds) - only if model uses thinking */
  readonly thinkingTimeMs: number | null;

  /** Time spent generating response content after thinking (milliseconds) */
  readonly responseTimeMs: number | null;

  /** Timestamp when thinking started (relative to generation start, in milliseconds) */
  readonly thinkingStartTimeMs: number | null;

  /** Timestamp when thinking ended (relative to generation start, in milliseconds) */
  readonly thinkingEndTimeMs: number | null;

  /** Timestamp when first response token arrived (relative to generation start, in milliseconds) */
  readonly firstResponseTokenTimeMs: number | null;
}

/**
 * Create performance metrics
 */
export class PerformanceMetricsImpl implements PerformanceMetrics {
  public readonly tokenizationTimeMs: number;
  public readonly inferenceTimeMs: number;
  public readonly postProcessingTimeMs: number;
  public readonly tokensPerSecond: number;
  public readonly peakMemoryUsage: number;
  public readonly queueWaitTimeMs: number;
  public readonly timeToFirstTokenMs: number | null;
  public readonly thinkingTimeMs: number | null;
  public readonly responseTimeMs: number | null;
  public readonly thinkingStartTimeMs: number | null;
  public readonly thinkingEndTimeMs: number | null;
  public readonly firstResponseTokenTimeMs: number | null;

  constructor(options: {
    tokenizationTimeMs?: number;
    inferenceTimeMs?: number;
    postProcessingTimeMs?: number;
    tokensPerSecond?: number;
    peakMemoryUsage?: number;
    queueWaitTimeMs?: number;
    timeToFirstTokenMs?: number | null;
    thinkingTimeMs?: number | null;
    responseTimeMs?: number | null;
    thinkingStartTimeMs?: number | null;
    thinkingEndTimeMs?: number | null;
    firstResponseTokenTimeMs?: number | null;
  } = {}) {
    this.tokenizationTimeMs = options.tokenizationTimeMs ?? 0;
    this.inferenceTimeMs = options.inferenceTimeMs ?? 0;
    this.postProcessingTimeMs = options.postProcessingTimeMs ?? 0;
    this.tokensPerSecond = options.tokensPerSecond ?? 0;
    this.peakMemoryUsage = options.peakMemoryUsage ?? 0;
    this.queueWaitTimeMs = options.queueWaitTimeMs ?? 0;
    this.timeToFirstTokenMs = options.timeToFirstTokenMs ?? null;
    this.thinkingTimeMs = options.thinkingTimeMs ?? null;
    this.responseTimeMs = options.responseTimeMs ?? null;
    this.thinkingStartTimeMs = options.thinkingStartTimeMs ?? null;
    this.thinkingEndTimeMs = options.thinkingEndTimeMs ?? null;
    this.firstResponseTokenTimeMs = options.firstResponseTokenTimeMs ?? null;
  }
}
