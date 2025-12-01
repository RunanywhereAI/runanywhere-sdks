/**
 * GenerationOptions.ts
 *
 * Options for text generation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/GenerationOptions.swift
 */

import { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';

/**
 * Execution target for model inference
 */
export enum ExecutionTarget {
  OnDevice = 'onDevice',
  Cloud = 'cloud',
  Hybrid = 'hybrid',
}

/**
 * Hardware acceleration options
 */
export enum HardwareAcceleration {
  CPU = 'CPU',
  GPU = 'GPU',
  NeuralEngine = 'NeuralEngine',
  Metal = 'Metal',
  CoreML = 'CoreML',
  Auto = 'Auto',
}

/**
 * Structured output configuration
 */
export interface StructuredOutputConfig {
  readonly type: any; // Generatable type
  readonly includeSchemaInPrompt: boolean;
}

/**
 * Options for text generation
 */
export interface GenerationOptions {
  /** Maximum number of tokens to generate */
  readonly maxTokens: number;

  /** Temperature for sampling (0.0 - 1.0) */
  readonly temperature: number;

  /** Top-p sampling parameter */
  readonly topP: number;

  /** Enable real-time tracking for cost dashboard */
  readonly enableRealTimeTracking: boolean;

  /** Stop sequences */
  readonly stopSequences: string[];

  /** Enable streaming mode */
  readonly streamingEnabled: boolean;

  /** Preferred execution target */
  readonly preferredExecutionTarget: ExecutionTarget | null;

  /** Preferred framework for generation */
  readonly preferredFramework: LLMFramework | null;

  /** Structured output configuration (optional) */
  readonly structuredOutput: StructuredOutputConfig | null;

  /** System prompt to define AI behavior and formatting rules */
  readonly systemPrompt: string | null;
}

/**
 * Create generation options
 */
export class GenerationOptionsImpl implements GenerationOptions {
  public readonly maxTokens: number;
  public readonly temperature: number;
  public readonly topP: number;
  public readonly enableRealTimeTracking: boolean;
  public readonly stopSequences: string[];
  public readonly streamingEnabled: boolean;
  public readonly preferredExecutionTarget: ExecutionTarget | null;
  public readonly preferredFramework: LLMFramework | null;
  public readonly structuredOutput: StructuredOutputConfig | null;
  public readonly systemPrompt: string | null;

  constructor(options: {
    maxTokens?: number;
    temperature?: number;
    topP?: number;
    enableRealTimeTracking?: boolean;
    stopSequences?: string[];
    streamingEnabled?: boolean;
    preferredExecutionTarget?: ExecutionTarget | null;
    preferredFramework?: LLMFramework | null;
    structuredOutput?: StructuredOutputConfig | null;
    systemPrompt?: string | null;
  } = {}) {
    this.maxTokens = options.maxTokens ?? 100;
    this.temperature = options.temperature ?? 0.8;
    this.topP = options.topP ?? 1.0;
    this.enableRealTimeTracking = options.enableRealTimeTracking ?? true;
    this.stopSequences = options.stopSequences ?? [];
    this.streamingEnabled = options.streamingEnabled ?? false;
    this.preferredExecutionTarget = options.preferredExecutionTarget ?? null;
    this.preferredFramework = options.preferredFramework ?? null;
    this.structuredOutput = options.structuredOutput ?? null;
    this.systemPrompt = options.systemPrompt ?? null;
  }
}

