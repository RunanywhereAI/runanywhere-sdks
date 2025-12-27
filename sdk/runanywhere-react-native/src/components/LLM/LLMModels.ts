/**
 * LLMModels.ts
 *
 * Input/Output models for LLM component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift
 */

import type { ComponentInput, ComponentOutput } from '../../Core/Components/BaseComponent';

/**
 * Message role
 */
export enum MessageRole {
  System = 'system',
  User = 'user',
  Assistant = 'assistant',
}

/**
 * Message in a conversation
 */
export interface Message {
  readonly role: MessageRole;
  readonly content: string;
}

/**
 * Context for conversation
 */
export interface Context {
  readonly systemPrompt?: string | null;
  readonly messages?: Message[];
}

/**
 * Generation options
 */
export interface RunAnywhereGenerationOptions {
  readonly maxTokens?: number;
  readonly temperature?: number;
  readonly topP?: number;
  readonly topK?: number;
  readonly repetitionPenalty?: number;
  readonly systemPrompt?: string | null;
  readonly stopSequences?: string[];
  readonly streamingEnabled?: boolean;
  readonly executionTarget?: string;
  readonly modelId?: string | null;
  readonly sessionId?: string | null;
  readonly userId?: string | null;
  readonly organizationId?: string | null;
  readonly metadata?: Record<string, unknown>;
  readonly debug?: boolean;
  readonly preferredFramework?: string | null;
}

/**
 * Input for Language Model generation (conforms to ComponentInput protocol)
 */
export interface LLMInput extends ComponentInput {
  /** Messages in the conversation */
  readonly messages: Message[];
  /** Optional system prompt override */
  readonly systemPrompt: string | null;
  /** Optional context for conversation */
  readonly context: Context | null;
  /** Optional generation options override */
  readonly options: RunAnywhereGenerationOptions | null;
}

/**
 * Output from Language Model generation (conforms to ComponentOutput protocol)
 */
export interface LLMOutput extends ComponentOutput {
  /** Generated text */
  readonly text: string;
  /** Token usage statistics */
  readonly tokenUsage: TokenUsage;
  /** Generation metadata */
  readonly metadata: GenerationMetadata;
  /** Finish reason */
  readonly finishReason: FinishReason;
}

/**
 * Token usage statistics
 */
export interface TokenUsage {
  readonly promptTokens: number;
  readonly completionTokens: number;
  readonly totalTokens: number;
}

/**
 * Generation metadata
 */
export interface GenerationMetadata {
  readonly modelId: string;
  readonly temperature: number;
  readonly generationTime: number; // seconds
  readonly tokensPerSecond: number;
}

/**
 * Finish reason
 */
export enum FinishReason {
  Completed = 'completed',
  Stopped = 'stopped',
  Length = 'length',
  Error = 'error',
}

/**
 * Token emitted during streaming generation
 */
export interface LLMStreamToken {
  /** The token text */
  readonly token: string;
  /** Whether this is the last token */
  readonly isLast: boolean;
  /** Index of this token in the sequence */
  readonly tokenIndex: number;
  /** Timestamp when this token was generated */
  readonly timestamp: Date;
}

/**
 * Performance metrics for streaming generation
 */
export interface LLMStreamMetrics {
  /** Time to first token in milliseconds */
  readonly timeToFirstTokenMs: number;
  /** Tokens generated per second */
  readonly tokensPerSecond: number;
  /** Total number of tokens generated */
  readonly totalTokens: number;
  /** Total generation time in milliseconds */
  readonly totalTimeMs: number;
}

/**
 * Result of streaming generation with both tokens and final output
 */
export interface LLMStreamResult {
  /** Async generator yielding tokens */
  readonly stream: AsyncGenerator<LLMStreamToken, void, unknown>;
  /** Promise that resolves to final output with metrics */
  readonly result: Promise<LLMOutput>;
}
