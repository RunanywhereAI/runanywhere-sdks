/**
 * LLMTypes.ts
 *
 * Re-exports proto-canonical LLM types and defines RN-only streaming
 * primitives that have no proto counterpart.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift
 */

// Proto-canonical types — single source of truth.
export type {
  LLMGenerationOptions,
  LLMGenerationResult,
  LLMConfiguration,
  StreamToken,
} from '@runanywhere/proto-ts/llm_options';

/**
 * LLM streaming result
 * Contains both a stream for real-time tokens and a promise for final metrics.
 */
export interface LLMStreamingResult {
  /** Async iterator for tokens */
  stream: AsyncIterable<string>;

  /** Promise that resolves to final result with metrics */
  result: Promise<import('@runanywhere/proto-ts/llm_options').LLMGenerationResult>;

  /** Cancel the generation */
  cancel: () => void;
}

/**
 * LLM streaming metrics collector state
 */
export interface LLMStreamingMetrics {
  /** Full generated text */
  fullText: string;

  /** Total token count */
  tokenCount: number;

  /** Time to first token in ms */
  timeToFirstTokenMs?: number;

  /** Total generation time in ms */
  totalTimeMs: number;

  /** Tokens per second */
  tokensPerSecond: number;

  /** Whether generation completed successfully */
  completed: boolean;

  /** Error if generation failed */
  error?: string;
}

/**
 * Token callback for streaming
 */
export type LLMTokenCallback = (token: string) => void;

/**
 * Stream completion callback
 */
export type LLMStreamCompleteCallback = (result: import('@runanywhere/proto-ts/llm_options').LLMGenerationResult) => void;

/**
 * Stream error callback
 */
export type LLMStreamErrorCallback = (error: Error) => void;
