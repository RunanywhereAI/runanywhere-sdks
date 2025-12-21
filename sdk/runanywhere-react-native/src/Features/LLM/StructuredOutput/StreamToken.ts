/**
 * StreamToken.ts
 *
 * Token types for streaming structured output
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/StreamToken.swift
 */

import type { Generatable } from './Generatable';

/**
 * Token emitted during streaming
 * Matches iOS StreamToken
 */
export interface StreamToken {
  /** The text content of the token */
  readonly text: string;
  /** Timestamp when token was generated */
  readonly timestamp: Date;
  /** Index of the token in the stream */
  readonly tokenIndex: number;
}

/**
 * Creates a stream token
 */
export function createStreamToken(
  text: string,
  tokenIndex: number,
  timestamp: Date = new Date()
): StreamToken {
  return {
    text,
    timestamp,
    tokenIndex,
  };
}

/**
 * Result containing both the token stream and final parsed result
 * Matches iOS StructuredOutputStreamResult
 */
export interface StructuredOutputStreamResult<T> {
  /**
   * Stream of tokens as they're generated
   * AsyncIterable to match TypeScript async iteration patterns
   */
  readonly tokenStream: AsyncIterable<StreamToken>;

  /**
   * Final parsed result (available after stream completes)
   * Promise that resolves to the parsed structured output
   */
  readonly result: Promise<T>;
}

/**
 * Creates a structured output stream result
 */
export function createStructuredOutputStreamResult<T>(
  tokenStream: AsyncIterable<StreamToken>,
  result: Promise<T>
): StructuredOutputStreamResult<T> {
  return {
    tokenStream,
    result,
  };
}
