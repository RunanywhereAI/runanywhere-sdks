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
}

export interface LLMGenerationResult {
  text: string;
  thinkingContent?: string;
  inputTokens: number;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  framework: LLMFramework;
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
