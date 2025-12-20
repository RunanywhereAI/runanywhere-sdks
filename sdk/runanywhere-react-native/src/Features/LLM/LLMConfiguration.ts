/**
 * LLMConfiguration.ts
 *
 * Configuration for LLM component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import type { LLMFramework } from '../../Core/Models/Framework/LLMFramework';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * LLM Quantization Level (component-specific)
 */
export enum LLMQuantizationLevel {
  Q4V0 = 'Q4_0',
  Q4KM = 'Q4_K_M',
  Q5KM = 'Q5_K_M',
  Q6K = 'Q6_K',
  Q8V0 = 'Q8_0',
  F16 = 'F16',
  F32 = 'F32',
}

/**
 * Configuration for LLM component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
 */
export interface LLMConfiguration
  extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null;
  readonly contextLength: number;
  readonly useGPUIfAvailable: boolean;
  readonly quantizationLevel: LLMQuantizationLevel | null;
  readonly cacheSize: number; // Token cache size in MB
  readonly preloadContext: string | null; // Optional system prompt to preload
  readonly temperature: number;
  readonly maxTokens: number;
  readonly systemPrompt: string | null;
  readonly streamingEnabled: boolean;
  readonly preferredFramework: LLMFramework | null;
}

/**
 * Create LLM configuration
 */
export class LLMConfigurationImpl implements LLMConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.LLM;
  public readonly modelId: string | null;
  public readonly contextLength: number;
  public readonly useGPUIfAvailable: boolean;
  public readonly quantizationLevel: LLMQuantizationLevel | null;
  public readonly cacheSize: number;
  public readonly preloadContext: string | null;
  public readonly temperature: number;
  public readonly maxTokens: number;
  public readonly systemPrompt: string | null;
  public readonly streamingEnabled: boolean;
  public readonly preferredFramework: LLMFramework | null;

  constructor(
    options: {
      modelId?: string | null;
      contextLength?: number;
      useGPUIfAvailable?: boolean;
      quantizationLevel?: LLMQuantizationLevel | null;
      cacheSize?: number;
      preloadContext?: string | null;
      temperature?: number;
      maxTokens?: number;
      systemPrompt?: string | null;
      streamingEnabled?: boolean;
      preferredFramework?: LLMFramework | null;
    } = {}
  ) {
    this.modelId = options.modelId ?? null;
    this.contextLength = options.contextLength ?? 2048;
    this.useGPUIfAvailable = options.useGPUIfAvailable ?? true;
    this.quantizationLevel = options.quantizationLevel ?? null;
    this.cacheSize = options.cacheSize ?? 100;
    this.preloadContext = options.preloadContext ?? null;
    this.temperature = options.temperature ?? 0.7;
    this.maxTokens = options.maxTokens ?? 100;
    this.systemPrompt = options.systemPrompt ?? options.preloadContext ?? null;
    this.streamingEnabled = options.streamingEnabled ?? true;
    this.preferredFramework = options.preferredFramework ?? null;
  }

  public validate(): void {
    if (this.contextLength <= 0 || this.contextLength > 32768) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Context length must be between 1 and 32768'
      );
    }
    if (this.cacheSize < 0 || this.cacheSize > 1000) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Cache size must be between 0 and 1000 MB'
      );
    }
    if (this.temperature < 0 || this.temperature > 2.0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Temperature must be between 0 and 2.0'
      );
    }
    if (this.maxTokens <= 0 || this.maxTokens > this.contextLength) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Max tokens must be between 1 and context length'
      );
    }
  }
}
