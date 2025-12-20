/**
 * StreamingService.ts
 *
 * Service for streaming text generation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Services/StreamingService.swift
 */

import type { GenerationOptions } from '../Models/GenerationOptions';
import type { GenerationResult } from '../Models/GenerationResult';
import type { GenerationService } from './GenerationService';
import { GenerationOptionsResolver } from './GenerationOptionsResolver';
import { ThinkingParser } from './ThinkingParser';
import { TokenCounter } from './TokenCounter';
import { ExecutionTarget } from '../Models/GenerationOptions';
import { HardwareAcceleration } from '../Models/GenerationOptions';
import type { PerformanceMetrics } from '../Models/PerformanceMetrics';
import { PerformanceMetricsImpl } from '../Models/PerformanceMetrics';
import type { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';
import type { ModelLoadingService } from '../../ModelLoading/Services/ModelLoadingService';

/**
 * Streaming result with stream and final result task
 */
export interface StreamingResult {
  /** Stream of tokens as they are generated */
  stream: AsyncGenerator<string, void, unknown>;

  /** Promise that resolves to final generation result including metrics */
  result: Promise<GenerationResult>;
}

/**
 * Service for streaming text generation
 */
export class StreamingService {
  private generationService: GenerationService;
  private modelLoadingService?: ModelLoadingService;
  private optionsResolver: GenerationOptionsResolver;

  constructor(
    generationService: GenerationService,
    modelLoadingService?: ModelLoadingService
  ) {
    this.generationService = generationService;
    this.modelLoadingService = modelLoadingService;
    this.optionsResolver = new GenerationOptionsResolver();
  }

  /**
   * Generate streaming text with metrics tracking
   */
  public generateStreamWithMetrics(
    prompt: string,
    options: GenerationOptions
  ): StreamingResult {
    // Shared state between stream and result promise
    let fullText = '';
    let thinkingContent: string | null = null;
    const startTime = Date.now();
    let firstTokenTime: number | null = null;
    let thinkingStartTime: number | null = null;
    let thinkingEndTime: number | null = null;
    let tokenCount = 0;
    let error: Error | null = null;
    let isComplete = false;
    let modelName: string | null = null;
    let framework: LLMFramework | undefined;

    // Create stream
    const stream = this.createStream(prompt, options, {
      onToken: (token: string, isThinking: boolean) => {
        fullText += token;
        tokenCount += 1;

        // Only set firstTokenTime for non-empty tokens
        if (firstTokenTime === null && token.length > 0) {
          firstTokenTime = Date.now();
        }

        if (isThinking && thinkingStartTime === null) {
          thinkingStartTime = Date.now();
        }
      },
      onThinkingEnd: (thinking: string) => {
        thinkingContent = thinking;
        thinkingEndTime = Date.now();
      },
      onComplete: (model: string, fw: LLMFramework | undefined) => {
        modelName = model;
        framework = fw;
        isComplete = true;
      },
      onError: (err: Error) => {
        error = err;
      },
    });

    // Create result promise
    const resultPromise = (async (): Promise<GenerationResult> => {
      // Wait for stream to complete
      for await (const _ of stream) {
        // Consume stream
      }

      if (error) {
        throw error;
      }

      if (!isComplete || !modelName) {
        throw new Error('Stream did not complete successfully');
      }

      // Build result
      return this.buildResult(
        modelName,
        framework,
        fullText,
        thinkingContent,
        startTime,
        firstTokenTime,
        thinkingStartTime,
        thinkingEndTime,
        tokenCount
      );
    })();

    return {
      stream,
      result: resultPromise,
    };
  }

  /**
   * Create streaming generator
   */
  private async *createStream(
    prompt: string,
    options: GenerationOptions,
    callbacks: {
      onToken: (token: string, isThinking: boolean) => void;
      onThinkingEnd: (thinking: string) => void;
      onComplete: (model: string, framework: LLMFramework | undefined) => void;
      onError: (error: Error) => void;
    }
  ): AsyncGenerator<string, void, unknown> {
    try {
      // Get remote configuration
      const remoteConfig = null;

      // Apply remote constraints to options
      const resolvedOptions = this.optionsResolver.resolve(
        options,
        remoteConfig
      );

      // Prepare prompt
      const effectivePrompt = this.optionsResolver.preparePrompt(
        prompt,
        resolvedOptions
      );

      // Get current model
      const currentModel = this.generationService.getCurrentModel();
      if (!currentModel) {
        throw new Error('No model is currently loaded');
      }

      // Get streaming service from model
      const service = currentModel.service;
      if (!service.generateStream) {
        throw new Error('Service does not support streaming');
      }

      // Stream tokens using callback-based API
      let isThinking = false;
      let thinkingBuffer = '';
      const tokens: string[] = [];

      // generateStream uses callback for tokens, returns final result
      const onToken = (token: string): void => {
        tokens.push(token);

        // Check if this is a thinking token
        if (
          currentModel.model.supportsThinking &&
          currentModel.model.thinkingPattern
        ) {
          const state = {
            buffer: thinkingBuffer,
            inThinkingSection: isThinking,
          };
          const parseResult = ThinkingParser.parseStreamingToken(
            token,
            currentModel.model.thinkingPattern,
            state
          );

          thinkingBuffer = state.buffer;
          isThinking = state.inThinkingSection;

          if (parseResult.tokenType === 'thinking') {
            callbacks.onToken(token, true);
            return;
          } else if (!isThinking && thinkingBuffer.length > 0) {
            // Thinking ended
            callbacks.onThinkingEnd(thinkingBuffer);
            thinkingBuffer = '';
          }
        }

        callbacks.onToken(token, false);
      };

      // Call generateStream with callback
      await service.generateStream(effectivePrompt, resolvedOptions, onToken);

      // Yield all collected tokens
      for (const token of tokens) {
        yield token;
      }

      callbacks.onComplete(
        currentModel.model.id,
        currentModel.model.preferredFramework
      );
    } catch (err) {
      callbacks.onError(err instanceof Error ? err : new Error(String(err)));
      throw err;
    }
  }

  /**
   * Build result from streaming data
   */
  private buildResult(
    modelUsed: string,
    framework: LLMFramework | undefined,
    fullText: string,
    thinkingContent: string | null,
    startTime: number,
    firstTokenTime: number | null,
    thinkingStartTime: number | null,
    thinkingEndTime: number | null,
    _tokenCount: number
  ): GenerationResult {
    const latency = Date.now() - startTime;

    // Parse thinking content if present
    let finalText = fullText;
    if (thinkingContent) {
      // If thinkingContent is already extracted, just remove it from fullText
      finalText = fullText.replace(thinkingContent, '').trim();
    }

    // Calculate token counts
    const tokenCounts = TokenCounter.splitTokenCounts(
      fullText,
      thinkingContent,
      finalText
    );

    const tokensPerSecond = TokenCounter.calculateTokensPerSecond(
      tokenCounts.totalTokens,
      latency / 1000.0
    );

    const thinkingTimeMs =
      thinkingStartTime && thinkingEndTime
        ? thinkingEndTime - thinkingStartTime
        : null;

    const responseTimeMs =
      thinkingTimeMs != null ? latency - thinkingTimeMs : null;

    const performanceMetrics: PerformanceMetrics = new PerformanceMetricsImpl({
      inferenceTimeMs: latency,
      tokensPerSecond,
      timeToFirstTokenMs: firstTokenTime ? firstTokenTime - startTime : null,
      thinkingTimeMs,
      responseTimeMs,
      thinkingStartTimeMs: thinkingStartTime
        ? thinkingStartTime - startTime
        : null,
      thinkingEndTimeMs: thinkingEndTime ? thinkingEndTime - startTime : null,
      firstResponseTokenTimeMs: thinkingEndTime
        ? thinkingEndTime - startTime
        : firstTokenTime
          ? firstTokenTime - startTime
          : null,
    });

    return {
      text: finalText,
      thinkingContent,
      tokensUsed: tokenCounts.totalTokens,
      modelUsed,
      latencyMs: latency,
      executionTarget: ExecutionTarget.OnDevice,
      savedAmount: 0.001,
      framework,
      hardwareUsed: HardwareAcceleration.CPU,
      memoryUsed: 0,
      performanceMetrics,
      structuredOutputValidation: null,
      thinkingTokens: tokenCounts.thinkingTokens,
      responseTokens: tokenCounts.responseTokens,
    };
  }
}
