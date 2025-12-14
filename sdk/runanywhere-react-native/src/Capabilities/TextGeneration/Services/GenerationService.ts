/**
 * GenerationService.ts
 *
 * Main service for text generation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Services/GenerationService.swift
 */

import type { GenerationOptions } from '../Models/GenerationOptions';
import type { GenerationResult } from '../Models/GenerationResult';
import type { RoutingDecision } from '../../Routing/Models/RoutingDecision';
import type { LoadedModel } from '../../ModelLoading/Models/LoadedModel';
import { RoutingService } from '../../Routing/Services/RoutingService';
import { GenerationOptionsResolver } from './GenerationOptionsResolver';
import { StructuredOutputHandler } from '../../StructuredOutput/Services/StructuredOutputHandler';
import { ThinkingParser } from './ThinkingParser';
import { TokenCounter } from './TokenCounter';
import { ExecutionTarget } from '../Models/GenerationOptions';
import { HardwareAcceleration } from '../Models/GenerationOptions';
import type { PerformanceMetrics } from '../Models/PerformanceMetrics';
import { PerformanceMetricsImpl } from '../Models/PerformanceMetrics';
import { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';

/**
 * Main service for text generation
 */
export class GenerationService {
  private routingService: RoutingService;
  private modelLoadingService: any; // ModelLoadingService
  private optionsResolver: GenerationOptionsResolver;
  private currentLoadedModel: LoadedModel | null = null;

  constructor(
    routingService: RoutingService,
    modelLoadingService?: any
  ) {
    this.routingService = routingService;
    this.modelLoadingService = modelLoadingService;
    this.optionsResolver = new GenerationOptionsResolver();
  }

  /**
   * Set the current loaded model for generation
   */
  public setCurrentModel(model: LoadedModel | null): void {
    this.currentLoadedModel = model;
  }

  /**
   * Get the current loaded model
   */
  public getCurrentModel(): LoadedModel | null {
    return this.currentLoadedModel;
  }

  /**
   * Generate text using the loaded model
   */
  public async generate(
    prompt: string,
    options: GenerationOptions
  ): Promise<GenerationResult> {
    const startTime = Date.now();

    // Get remote configuration (placeholder - would come from ServiceContainer)
    const remoteConfig = null;

    // Apply remote constraints to options
    const resolvedOptions = this.optionsResolver.resolve(options, remoteConfig);

    // Prepare prompt with system prompt and structured output formatting
    const effectivePrompt = this.optionsResolver.preparePrompt(
      prompt,
      resolvedOptions
    );

    // Get routing decision
    const routingDecision = await this.routingService.determineRouting(
      effectivePrompt,
      null,
      resolvedOptions
    );

    // Generate based on routing decision
    let result: GenerationResult;

    if (routingDecision.type === 'onDevice') {
      result = await this.generateOnDevice(
        effectivePrompt,
        resolvedOptions,
        routingDecision.framework
      );
    } else if (routingDecision.type === 'cloud') {
      result = await this.generateInCloud(
        effectivePrompt,
        resolvedOptions,
        routingDecision.provider
      );
    } else {
      // hybrid
      result = await this.generateHybrid(
        effectivePrompt,
        resolvedOptions,
        routingDecision.devicePortion,
        routingDecision.framework
      );
    }

    // Validate structured output if configured
    if (resolvedOptions.structuredOutput) {
      const handler = new StructuredOutputHandler();
      const validation = handler.validateStructuredOutput(
        result.text,
        resolvedOptions.structuredOutput
      );

      return {
        ...result,
        structuredOutputValidation: validation,
      };
    }

    return result;
  }

  /**
   * Generate on device
   */
  private async generateOnDevice(
    prompt: string,
    options: GenerationOptions,
    framework: LLMFramework | null
  ): Promise<GenerationResult> {
    const startTime = Date.now();

    // Use the current loaded model
    if (!this.currentLoadedModel) {
      throw new Error('No model is currently loaded');
    }

    const loadedModel = this.currentLoadedModel;

    // Generate text using the actual loaded model's service
    let generatedText: string;
    try {
      const result = await loadedModel.service.generate(prompt, options);
      generatedText = result.text;
    } catch (error) {
      throw error;
    }

    // Calculate metrics
    const latency = Date.now() - startTime;

    // Parse thinking content if model supports it
    const modelInfo = loadedModel.model;
    let finalText: string;
    let thinkingContent: string | null = null;
    let thinkingTimeMs: number | null = null;

    if (modelInfo.supportsThinking && modelInfo.thinkingPattern) {
      const parseResult = ThinkingParser.parse(
        generatedText,
        modelInfo.thinkingPattern
      );
      finalText = parseResult.content;
      thinkingContent = parseResult.thinkingContent;

      // Estimate thinking time if present
      if (thinkingContent && thinkingContent.length > 0) {
        thinkingTimeMs = latency * 0.6;
      }
    } else {
      finalText = generatedText;
    }

    // Calculate token counts
    const tokenCounts = TokenCounter.splitTokenCounts(
      generatedText,
      thinkingContent,
      finalText
    );

    const tokensPerSecond = TokenCounter.calculateTokensPerSecond(
      tokenCounts.totalTokens,
      latency / 1000.0
    );

    const responseTimeMs: number | null =
      thinkingTimeMs != null ? latency - thinkingTimeMs : null;

    // For non-streaming generation, time-to-first-token equals total latency
    const timeToFirstTokenMs = latency;

    const performanceMetrics: PerformanceMetrics = new PerformanceMetricsImpl({
      inferenceTimeMs: latency,
      tokensPerSecond,
      timeToFirstTokenMs,
      thinkingTimeMs,
      responseTimeMs,
    });

    return {
      text: finalText,
      thinkingContent,
      tokensUsed: tokenCounts.totalTokens,
      modelUsed: loadedModel.model.id,
      latencyMs: latency,
      executionTarget: ExecutionTarget.OnDevice,
      savedAmount: 0.001, // Placeholder
      framework: framework ?? loadedModel.model.preferredFramework,
      hardwareUsed: HardwareAcceleration.CPU, // Placeholder
      memoryUsed: 0, // Placeholder
      performanceMetrics,
      structuredOutputValidation: null,
      thinkingTokens: tokenCounts.thinkingTokens,
      responseTokens: tokenCounts.responseTokens,
    };
  }

  /**
   * Generate in cloud
   */
  private async generateInCloud(
    prompt: string,
    options: GenerationOptions,
    provider: string | null
  ): Promise<GenerationResult> {
    // Placeholder implementation
    const latency = 50;
    const tokensUsed = 10;

    const performanceMetrics: PerformanceMetrics = new PerformanceMetricsImpl({
      inferenceTimeMs: latency,
      tokensPerSecond: 20.0,
    });

    return {
      text: 'Generated text in cloud',
      thinkingContent: null,
      tokensUsed,
      modelUsed: 'cloud-model',
      latencyMs: latency,
      executionTarget: ExecutionTarget.Cloud,
      savedAmount: 0.001,
      framework: null,
      hardwareUsed: HardwareAcceleration.CPU,
      memoryUsed: 0,
      performanceMetrics,
      structuredOutputValidation: null,
      thinkingTokens: null,
      responseTokens: tokensUsed,
    };
  }

  /**
   * Generate hybrid
   */
  private async generateHybrid(
    prompt: string,
    options: GenerationOptions,
    devicePortion: number,
    framework: LLMFramework | null
  ): Promise<GenerationResult> {
    // For hybrid approach, use on-device generation with partial processing
    // In a real implementation, this would split processing between device and cloud
    const startTime = Date.now();

    // Use the current loaded model
    if (!this.currentLoadedModel) {
      throw new Error('No model is currently loaded');
    }

    const loadedModel = this.currentLoadedModel;

    // For now, use on-device generation entirely
    const generationResult = await loadedModel.service.generate(prompt, options);
    const generatedText = generationResult.text;

    // Calculate metrics
    const latency = Date.now() - startTime;

    // Parse thinking content if model supports it
    const modelInfo = loadedModel.model;
    let finalText: string;
    let thinkingContent: string | null = null;
    let thinkingTimeMs: number | null = null;

    if (modelInfo.supportsThinking && modelInfo.thinkingPattern) {
      const parseResult = ThinkingParser.parse(
        generatedText,
        modelInfo.thinkingPattern
      );
      finalText = parseResult.content;
      thinkingContent = parseResult.thinkingContent;

      if (thinkingContent && thinkingContent.length > 0) {
        thinkingTimeMs = latency * 0.6;
      }
    } else {
      finalText = generatedText;
    }

    // Calculate token counts
    const tokenCounts = TokenCounter.splitTokenCounts(
      generatedText,
      thinkingContent,
      finalText
    );

    const tokensPerSecond = TokenCounter.calculateTokensPerSecond(
      tokenCounts.totalTokens,
      latency / 1000.0
    );

    const responseTimeMs: number | null =
      thinkingTimeMs != null ? latency - thinkingTimeMs : null;

    const timeToFirstTokenMs = latency;

    const performanceMetrics: PerformanceMetrics = new PerformanceMetricsImpl({
      inferenceTimeMs: latency,
      tokensPerSecond,
      timeToFirstTokenMs,
      thinkingTimeMs,
      responseTimeMs,
    });

    return {
      text: finalText,
      thinkingContent,
      tokensUsed: tokenCounts.totalTokens,
      modelUsed: loadedModel.model.id,
      latencyMs: latency,
      executionTarget: ExecutionTarget.Hybrid,
      savedAmount: 0.0005, // Hybrid saves less than full on-device
      framework: framework ?? loadedModel.model.preferredFramework,
      hardwareUsed: HardwareAcceleration.CPU,
      memoryUsed: 0,
      performanceMetrics,
      structuredOutputValidation: null,
      thinkingTokens: tokenCounts.thinkingTokens,
      responseTokens: tokenCounts.responseTokens,
    };
  }
}
