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

