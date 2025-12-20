/**
 * GenerationResult.ts
 *
 * Result of a text generation request
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/GenerationResult.swift
 */

import type { ExecutionTarget } from './GenerationOptions';
import type { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';
import type { HardwareAcceleration } from './GenerationOptions';
import type { PerformanceMetrics } from './PerformanceMetrics';
import type { StructuredOutputValidation } from '../../StructuredOutput/Services/StructuredOutputHandler';

/**
 * Result of a text generation request
 */
export interface GenerationResult {
  /** Generated text (with thinking content removed if extracted) */
  readonly text: string;

  /** Thinking/reasoning content extracted from the response */
  readonly thinkingContent: string | null;

  /** Number of tokens used */
  readonly tokensUsed: number;

  /** Model used for generation */
  readonly modelUsed: string;

  /** Latency in milliseconds */
  readonly latencyMs: number;

  /** Execution target (device/cloud/hybrid) */
  readonly executionTarget: ExecutionTarget;

  /** Amount saved by using on-device execution */
  readonly savedAmount: number;

  /** Framework used for generation (if on-device) */
  readonly framework: LLMFramework | null;

  /** Hardware acceleration used */
  readonly hardwareUsed: HardwareAcceleration;

  /** Memory used during generation (in bytes) */
  readonly memoryUsed: number; // Int64

  /** Detailed performance metrics */
  readonly performanceMetrics: PerformanceMetrics;

  /** Structured output validation result (if structured output was requested) */
  readonly structuredOutputValidation: StructuredOutputValidation | null;

  /** Number of tokens used for thinking/reasoning (if model supports thinking mode) */
  readonly thinkingTokens: number | null;

  /** Number of tokens in the actual response content (excluding thinking) */
  readonly responseTokens: number;
}
