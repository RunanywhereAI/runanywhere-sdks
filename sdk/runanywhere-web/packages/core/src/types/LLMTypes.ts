/**
 * RunAnywhere Web SDK - LLM Types
 *
 * Mirrored from: sdk/runanywhere-react-native/packages/core/src/types/LLMTypes.ts
 * Source of truth: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift
 */

import type { HardwareAcceleration, LLMFramework } from './enums';

export interface LLMGenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  stopSequences?: string[];
  systemPrompt?: string;
  streamingEnabled?: boolean;
  /** Preferred inference framework (mirrors Swift `LLMGenerationOptions.preferredFramework`) */
  preferredFramework?: LLMFramework;
  /**
   * Optional structured-output config (Web carries this on
   * `StructuredOutputConfig` from the llamacpp pkg; field reserved for parity).
   */
  structuredOutput?: unknown;
}

/**
 * Default values aligned with Swift `LLMGenerationOptions` defaults.
 * Use `applyLLMGenerationDefaults(opts)` to merge defaults into a partial
 * options object.
 */
export const LLM_GENERATION_DEFAULTS = Object.freeze({
  maxTokens: 100,
  temperature: 0.8,
  topP: 1.0,
  stopSequences: [] as readonly string[],
  streamingEnabled: false,
}) as Readonly<{
  maxTokens: number;
  temperature: number;
  topP: number;
  stopSequences: readonly string[];
  streamingEnabled: boolean;
}>;

/**
 * Merge Swift-aligned defaults into the user-supplied options.
 * Returns a new object so the caller's input is not mutated.
 */
export function applyLLMGenerationDefaults(
  options: LLMGenerationOptions = {},
): LLMGenerationOptions {
  return {
    ...options,
    maxTokens: options.maxTokens ?? LLM_GENERATION_DEFAULTS.maxTokens,
    temperature: options.temperature ?? LLM_GENERATION_DEFAULTS.temperature,
    topP: options.topP ?? LLM_GENERATION_DEFAULTS.topP,
    stopSequences: options.stopSequences ?? [...LLM_GENERATION_DEFAULTS.stopSequences],
    streamingEnabled: options.streamingEnabled ?? LLM_GENERATION_DEFAULTS.streamingEnabled,
  };
}

export interface LLMGenerationResult {
  [key: string]: unknown;
  text: string;
  thinkingContent?: string;
  inputTokens: number;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  /** Inference framework that produced this result (optional — aligned to Swift). */
  framework?: LLMFramework;
  hardwareUsed: HardwareAcceleration;
  tokensPerSecond: number;
  timeToFirstTokenMs?: number;
  thinkingTokens: number;
  responseTokens: number;
}

export interface LLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<LLMGenerationResult>;
  cancel: () => void;
}

export interface LLMStreamingMetrics {
  fullText: string;
  tokenCount: number;
  timeToFirstTokenMs?: number;
  totalTimeMs: number;
  tokensPerSecond: number;
  completed: boolean;
  error?: string;
}

export type LLMTokenCallback = (token: string) => void;
export type LLMStreamCompleteCallback = (result: LLMGenerationResult) => void;
export type LLMStreamErrorCallback = (error: Error) => void;
