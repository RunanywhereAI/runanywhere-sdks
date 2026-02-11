/**
 * LLMTypes.ts
 *
 * Type definitions for LLM streaming functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift
 */

/**
 * LLM generation options
 */
export interface LLMGenerationOptions {
  /** Maximum tokens to generate */
  maxTokens?: number;

  /** Temperature (0.0 - 2.0) */
  temperature?: number;

  /** Top-p sampling */
  topP?: number;

  /** Top-k sampling */
  topK?: number;

  /** Stop sequences */
  stopSequences?: string[];

  /** System prompt */
  systemPrompt?: string;

  /** Enable streaming */
  streamingEnabled?: boolean;

  /** Confidence threshold for cloud handoff (0.0 - 1.0). Used by routing engine. */
  confidenceThreshold?: number;
}

/**
 * LLM generation result
 */
export interface LLMGenerationResult {
  /** Generated text */
  text: string;

  /** Thinking content (for models with reasoning) */
  thinkingContent?: string;

  /** Input tokens count */
  inputTokens: number;

  /** Output tokens count */
  tokensUsed: number;

  /** Model ID used */
  modelUsed: string;

  /** Total latency in ms */
  latencyMs: number;

  /** Framework used */
  framework: string;

  /** Tokens per second */
  tokensPerSecond: number;

  /** Time to first token in ms */
  timeToFirstTokenMs?: number;

  /** Thinking tokens count */
  thinkingTokens: number;

  /** Response tokens count */
  responseTokens: number;

  /** On-device confidence score (0.0 - 1.0). Set by C++ entropy-based scoring. */
  confidence?: number;

  /** Whether cloud handoff was triggered by the on-device engine */
  cloudHandoff?: boolean;

  /** Reason for cloud handoff (maps to HandoffReason enum) */
  handoffReason?: number;
}

/**
 * LLM streaming result
 * Contains both a stream for real-time tokens and a promise for final metrics
 */
export interface LLMStreamingResult {
  /** Async iterator for tokens */
  stream: AsyncIterable<string>;

  /** Promise that resolves to final result with metrics */
  result: Promise<LLMGenerationResult>;

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
export type LLMStreamCompleteCallback = (result: LLMGenerationResult) => void;

/**
 * Stream error callback
 */
export type LLMStreamErrorCallback = (error: Error) => void;
