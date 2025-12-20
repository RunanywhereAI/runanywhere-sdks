/**
 * GenerationOptionsResolver.ts
 *
 * Simple resolver that applies remote configuration constraints to runtime options
 *
 * Priority Order (highest to lowest):
 * 1. Runtime Options - User-provided values take precedence
 * 2. Remote Configuration - Organization defaults from console
 * 3. SDK Defaults - Fallback values when nothing else is specified
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Services/GenerationOptionsResolver.swift
 */

import type { GenerationOptions } from '../Models/GenerationOptions';

/**
 * Generation configuration from remote
 */
export interface GenerationConfiguration {
  readonly defaults: DefaultGenerationSettings;
  readonly tokenBudget: TokenBudgetConfiguration | null;
  readonly maxContextLength: number;
}

/**
 * Default settings for text generation
 */
export interface DefaultGenerationSettings {
  readonly temperature: number;
  readonly maxTokens: number;
  readonly topP: number;
  readonly topK: number | null;
  readonly repetitionPenalty: number | null;
  readonly stopSequences: string[];
}

/**
 * Token budget configuration for managing usage
 */
export interface TokenBudgetConfiguration {
  readonly maxTokensPerRequest: number | null;
  readonly maxTokensPerDay: number | null;
  readonly maxTokensPerMonth: number | null;
  readonly enforceStrictly: boolean;
}

/**
 * Simple resolver that applies remote configuration constraints to runtime options
 */
export class GenerationOptionsResolver {
  /**
   * Apply remote configuration constraints to runtime options
   *
   * Resolution Rules:
   * - If user provides a value, it's used (unless it exceeds hard limits)
   * - If user doesn't provide a value, remote default is used
   * - If neither exist, SDK defaults are used
   * - Hard limits (like token budgets) are always enforced
   */
  public resolve(
    options: GenerationOptions | null,
    remoteConfig: GenerationConfiguration | null
  ): GenerationOptions {
    // Import GenerationOptionsImpl
    const { GenerationOptionsImpl } = require('../Models/GenerationOptions');

    // Start with user options or create defaults
    const baseOptions = options ?? new GenerationOptionsImpl();

    // If no remote config, return as-is
    if (!remoteConfig) {
      return baseOptions;
    }

    // Apply remote constraints and defaults
    let maxTokens = baseOptions.maxTokens;
    let temperature = baseOptions.temperature;
    let topP = baseOptions.topP;

    // If user didn't specify, use remote defaults
    if (!options) {
      maxTokens = remoteConfig.defaults.maxTokens;
      temperature = remoteConfig.defaults.temperature;
      topP = remoteConfig.defaults.topP;
    }

    // Apply token budget constraints (these are hard limits)
    if (remoteConfig.tokenBudget) {
      if (remoteConfig.tokenBudget.maxTokensPerRequest != null) {
        maxTokens = Math.min(
          maxTokens,
          remoteConfig.tokenBudget.maxTokensPerRequest
        );
      }
    }

    // Apply context length constraint
    if (maxTokens > remoteConfig.maxContextLength) {
      maxTokens = remoteConfig.maxContextLength;
    }

    // Merge stop sequences
    const stopSequences = this.mergeStopSequences(
      baseOptions.stopSequences,
      remoteConfig.defaults.stopSequences
    );

    // Create updated options with constraints applied
    return new GenerationOptionsImpl({
      maxTokens,
      temperature,
      topP,
      enableRealTimeTracking: baseOptions.enableRealTimeTracking,
      stopSequences,
      streamingEnabled: baseOptions.streamingEnabled,
      preferredExecutionTarget: baseOptions.preferredExecutionTarget,
      preferredFramework: baseOptions.preferredFramework,
      structuredOutput: baseOptions.structuredOutput,
      systemPrompt: baseOptions.systemPrompt,
    });
  }

  /**
   * Prepare prompt with system prompt and structured output formatting
   */
  public preparePrompt(prompt: string, options: GenerationOptions): string {
    let effectivePrompt = prompt;

    // Apply structured output formatting first if needed
    if (options.structuredOutput) {
      // Import StructuredOutputHandler dynamically to avoid circular dependency
      const StructuredOutputHandler =
        require('../../StructuredOutput/Services/StructuredOutputHandler').StructuredOutputHandler;
      const handler = new StructuredOutputHandler();
      effectivePrompt = handler.preparePrompt(
        effectivePrompt,
        options.structuredOutput
      );
    }

    // Then apply system prompt if provided
    if (options.systemPrompt) {
      effectivePrompt = `${options.systemPrompt}\n\n${effectivePrompt}`;
    }

    return effectivePrompt;
  }

  /**
   * Merge stop sequences from runtime and remote
   */
  private mergeStopSequences(
    runtime: string[],
    remote: string[] | null
  ): string[] {
    const sequences = [...runtime];
    if (remote) {
      sequences.push(...remote);
    }
    // Remove duplicates while preserving order
    return sequences.filter((seq, index) => sequences.indexOf(seq) === index);
  }
}
