/**
 * LLMComponent.ts
 *
 * Language Model component following the clean architecture
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ModuleRegistry } from '../../Core/ModuleRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { LLMConfiguration } from './LLMConfiguration';
import {
  type LLMInput,
  type LLMOutput,
  type Message,
  MessageRole,
  FinishReason,
  type LLMStreamToken,
  type LLMStreamResult,
} from './LLMModels';
import type { LLMService } from '../../Core/Protocols/LLM/LLMService';
import type { LLMServiceProvider } from '../../Core/Protocols/LLM/LLMServiceProvider';
import type { GenerationOptions } from '../../Capabilities/TextGeneration/Models/GenerationOptions';
import type { GenerationResult } from '../../Capabilities/TextGeneration/Models/GenerationResult';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';
import { PerformanceMetricsImpl } from '../../Capabilities/TextGeneration/Models/PerformanceMetrics';

/**
 * LLM Service Wrapper
 * Wrapper class to allow protocol-based LLM service to work with BaseComponent
 */
export class LLMServiceWrapper extends AnyServiceWrapper<LLMService> {
  constructor(service: LLMService | null = null) {
    super(service);
  }
}

/**
 * Language Model component
 */
export class LLMComponent extends BaseComponent<LLMServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.LLM;

  private readonly llmConfiguration: LLMConfiguration;
  private conversationContext: { systemPrompt?: string | null; messages?: Message[] } | null = null;
  private isModelLoaded = false;
  private modelPath: string | null = null;

  // MARK: - Initialization

  constructor(configuration: LLMConfiguration) {
    super(configuration);
    this.llmConfiguration = configuration;

    // Preload context if provided
    if (configuration.preloadContext) {
      this.conversationContext = { systemPrompt: configuration.preloadContext };
    }
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<LLMServiceWrapper> {
    // Check if model needs downloading
    if (this.llmConfiguration.modelId) {
      this.modelPath = this.llmConfiguration.modelId;
      // In real implementation, check if model exists
    }

    // Try to get a registered LLM provider from central registry
    const provider = ModuleRegistry.shared.llmProvider(this.llmConfiguration.modelId);

    if (!provider) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ModuleRegistry.shared.registerLLM(provider).'
      );
    }

    try {
      // Create service through provider
      const llmService = await provider.createLLMService(this.llmConfiguration);

    // Initialize the service
      await llmService.initialize(this.modelPath ?? undefined);
      this.isModelLoaded = true;

    // Wrap and return the service
      return new LLMServiceWrapper(llmService);
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        `Failed to create LLM service: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  protected override async performCleanup(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.cleanup();
    }
    this.isModelLoaded = false;
    this.modelPath = null;
    this.conversationContext = null;
  }

  // MARK: - Public API

  /**
   * Generate text from a simple prompt
   */
  public async generate(prompt: string, systemPrompt?: string | null): Promise<LLMOutput> {
    this.ensureReady();

    const input: LLMInput = {
      messages: [{ role: MessageRole.User, content: prompt }],
      systemPrompt: systemPrompt ?? null,
      context: null,
      options: null,
      validate: () => {
        if (!prompt || prompt.trim().length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'LLMInput must contain at least one message');
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Generate with conversation history
   */
  public async generateWithHistory(
    messages: Message[],
    systemPrompt?: string | null
  ): Promise<LLMOutput> {
    this.ensureReady();

    const input: LLMInput = {
      messages,
      systemPrompt: systemPrompt ?? null,
      context: null,
      options: null,
      validate: () => {
        if (!messages || messages.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'LLMInput must contain at least one message');
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Process LLM input
   */
  public async process(input: LLMInput): Promise<LLMOutput> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'LLM service not available');
    }

    // Validate input
    input.validate();

    // Use provided options or create from configuration
    const options: GenerationOptions = input.options
      ? {
          maxTokens: input.options.maxTokens,
          temperature: input.options.temperature,
          systemPrompt: input.options.systemPrompt,
        }
      : {
      maxTokens: this.llmConfiguration.maxTokens,
      temperature: this.llmConfiguration.temperature,
          systemPrompt: this.llmConfiguration.systemPrompt,
    };

    // Build prompt
    const prompt = this.buildPrompt(
      input.messages,
      input.systemPrompt ?? this.llmConfiguration.systemPrompt
    );

    // Track generation time
    const startTime = Date.now();

    // Generate response
    const result: GenerationResult = await this.service.wrappedService.generate(prompt, options);

    const generationTime = (Date.now() - startTime) / 1000; // seconds

    // Extract token usage from result
    const promptTokens = Math.floor(prompt.length / 4); // Rough estimate
    const completionTokens = result.tokensUsed ?? Math.floor(result.text.length / 4);
    const tokensPerSecond = completionTokens / generationTime;

    // Create output
    return {
      text: result.text,
      tokenUsage: {
        promptTokens,
        completionTokens,
        totalTokens: promptTokens + completionTokens,
      },
      metadata: {
        modelId: this.service.wrappedService.currentModel ?? 'unknown',
        temperature: options.temperature ?? this.llmConfiguration.temperature,
        generationTime,
        tokensPerSecond,
      },
      finishReason: FinishReason.Completed,
      timestamp: new Date(),
    };
  }

  /**
   * Stream generation
   */
  public async *streamGenerate(
    prompt: string,
    systemPrompt?: string | null
  ): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'LLM service not available');
    }

    const options: GenerationOptions = {
      maxTokens: this.llmConfiguration.maxTokens,
      temperature: this.llmConfiguration.temperature,
      systemPrompt: systemPrompt ?? this.llmConfiguration.systemPrompt,
    };

    const fullPrompt = this.buildPrompt(
      [{ role: MessageRole.User, content: prompt }],
      systemPrompt ?? this.llmConfiguration.systemPrompt
    );

    // Stream generation (if supported)
    if (this.service.wrappedService.generateStream) {
      let accumulatedText = '';
      const result = await this.service.wrappedService.generateStream(
      fullPrompt,
      options,
        (token: string) => {
          // Yield tokens as they come
          accumulatedText += token;
        }
      );
      // Yield final result if no tokens were yielded during streaming
      if (accumulatedText) {
        yield accumulatedText;
      } else {
        yield result.text;
      }
    } else {
      // Fallback to non-streaming
      const result = await this.service.wrappedService.generate(fullPrompt, options);
      yield result.text;
    }
  }

  /**
   * Generate with streaming and metrics tracking
   * Returns both the token stream and final result with performance metrics
   *
   * This is the recommended method for streaming with full analytics support.
   * The stream yields tokens as they're generated, while the result promise
   * resolves to the complete output with performance metrics.
   *
   * @param prompt - User prompt
   * @param options - Generation options (optional, uses configuration defaults if not provided)
   * @returns LLMStreamResult with stream and result promise
   *
   * @example
   * ```typescript
   * const streamResult = component.generateStreamWithMetrics("Tell me a story", {
   *   maxTokens: 100,
   *   temperature: 0.7
   * });
   *
   * // Consume tokens as they arrive
   * for await (const token of streamResult.stream) {
   *   console.log(token.token);
   * }
   *
   * // Get final result with metrics
   * const output = await streamResult.result;
   * console.log(`Tokens/sec: ${output.metadata.tokensPerSecond}`);
   * ```
   */
  public generateStreamWithMetrics(
    prompt: string,
    options?: Partial<RunAnywhereGenerationOptions>
  ): LLMStreamResult {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'LLM service not available');
    }

    // Shared state between stream and result
    const collector = {
      fullText: '',
      startTime: Date.now(),
      firstTokenTime: null as number | null,
      tokenCount: 0,
      error: null as Error | null,
      isComplete: false,
      resolveResult: null as ((value: LLMOutput) => void) | null,
      rejectResult: null as ((error: Error) => void) | null,
    };

    // Token queue for async iteration
    const tokenQueue: LLMStreamToken[] = [];
    let streamResolve: ((value: IteratorResult<LLMStreamToken>) => void) | null = null;
    let streamEnded = false;

    // Merge options with configuration defaults
    const generationOptions: GenerationOptions = {
      maxTokens: options?.maxTokens ?? this.llmConfiguration.maxTokens,
      temperature: options?.temperature ?? this.llmConfiguration.temperature,
      systemPrompt: options?.systemPrompt ?? this.llmConfiguration.systemPrompt,
      topP: options?.topP,
      stopSequences: options?.stopSequences,
      streamingEnabled: true,
      preferredExecutionTarget: options?.executionTarget ?
        (options.executionTarget as any) : undefined,
      preferredFramework: options?.preferredFramework as any,
    };

    const fullPrompt = this.buildPrompt(
      [{ role: MessageRole.User, content: prompt }],
      generationOptions.systemPrompt ?? null
    );

    // Helper to enqueue tokens
    const enqueueToken = (token: LLMStreamToken) => {
      if (streamResolve) {
        streamResolve({ value: token, done: false });
        streamResolve = null;
      } else {
        tokenQueue.push(token);
      }
    };

    // Helper to end the stream
    const endStream = () => {
      streamEnded = true;
      if (streamResolve) {
        streamResolve({ value: undefined, done: true });
        streamResolve = null;
      }
    };

    // Start the streaming generation in the background
    const service = this.service.wrappedService;
    const componentThis = this;

    (async () => {
      try {
        if (!service?.generateStream) {
          throw new SDKError(
            SDKErrorCode.FeatureNotAvailable,
            'Streaming not supported by current LLM service'
          );
        }

        let tokenIndex = 0;

        // Reset start time right before inference
        collector.startTime = Date.now();

        await service.generateStream(
          fullPrompt,
          generationOptions,
          (token: string) => {
            // Record first token time
            if (collector.firstTokenTime === null && token.length > 0) {
              collector.firstTokenTime = Date.now();
            }

            // Accumulate text and count tokens
            collector.fullText += token;
            collector.tokenCount += 1;

            // Create and enqueue the token
            const streamToken: LLMStreamToken = {
              token,
              isLast: false,
              tokenIndex: tokenIndex++,
              timestamp: new Date(),
            };

            enqueueToken(streamToken);
          }
        );

        // Mark as complete
        collector.isComplete = true;

        // Enqueue final token
        enqueueToken({
          token: '',
          isLast: true,
          tokenIndex: collector.tokenCount,
          timestamp: new Date(),
        });

        // End the stream
        endStream();

        // Signal result completion
        if (collector.resolveResult) {
          const output = componentThis.buildOutputFromCollector(collector, generationOptions);
          collector.resolveResult(output);
        }
      } catch (error) {
        collector.error = error as Error;
        if (collector.rejectResult) {
          collector.rejectResult(error as Error);
        }
        endStream();
      }
    })();

    // Create the async generator
    const stream = (async function* (): AsyncGenerator<LLMStreamToken, void, unknown> {
      while (!streamEnded || tokenQueue.length > 0) {
        if (tokenQueue.length > 0) {
          const token = tokenQueue.shift()!;
          yield token;
          if (token.isLast) {
            break;
          }
        } else {
          // Wait for next token
          await new Promise<IteratorResult<LLMStreamToken>>((resolve) => {
            streamResolve = resolve;
          }).then((result) => {
            if (!result.done) {
              tokenQueue.push(result.value);
            }
          });
        }
      }
    })();

    // Create result promise
    const result = new Promise<LLMOutput>((resolve, reject) => {
      collector.resolveResult = resolve;
      collector.rejectResult = reject;
    });

    return {
      stream,
      result,
    };
  }

  // MARK: - Helper Methods

  /**
   * Build LLMOutput from metrics collector
   */
  private buildOutputFromCollector(
    collector: {
      fullText: string;
      startTime: number;
      firstTokenTime: number | null;
      tokenCount: number
    },
    options: GenerationOptions
  ): LLMOutput {
    const endTime = Date.now();
    const totalTimeMs = endTime - collector.startTime;
    const totalTimeSec = totalTimeMs / 1000;

    const timeToFirstTokenMs = collector.firstTokenTime
      ? collector.firstTokenTime - collector.startTime
      : null;

    // Calculate tokens per second
    const tokensPerSecond = totalTimeSec > 0 ? collector.tokenCount / totalTimeSec : 0;

    // Estimate prompt tokens (rough estimate: 1 token ≈ 4 characters)
    const promptTokens = Math.floor(collector.fullText.length / 4);
    const completionTokens = collector.tokenCount;

    const performanceMetrics = new PerformanceMetricsImpl({
      tokenizationTimeMs: 0,
      inferenceTimeMs: totalTimeMs,
      postProcessingTimeMs: 0,
      tokensPerSecond,
      peakMemoryUsage: 0,
      queueWaitTimeMs: 0,
      timeToFirstTokenMs,
      thinkingTimeMs: null,
      responseTimeMs: totalTimeMs,
    });

    return {
      text: collector.fullText,
      tokenUsage: {
        promptTokens,
        completionTokens,
        totalTokens: promptTokens + completionTokens,
      },
      metadata: {
        modelId: this.service?.wrappedService?.currentModel ?? 'unknown',
        temperature: options.temperature ?? this.llmConfiguration.temperature,
        generationTime: totalTimeSec,
        tokensPerSecond,
      },
      finishReason: FinishReason.Completed,
      timestamp: new Date(),
    };
  }

  /**
   * Build prompt from messages and system prompt
   */
  private buildPrompt(messages: Message[], systemPrompt?: string | null): string {
    let prompt = '';

    if (systemPrompt) {
      prompt += `System: ${systemPrompt}\n\n`;
    }

    for (const message of messages) {
      const roleLabel = message.role === MessageRole.User ? 'User' : 'Assistant';
      prompt += `${roleLabel}: ${message.content}\n\n`;
    }

    prompt += 'Assistant:';
    return prompt;
  }
}
