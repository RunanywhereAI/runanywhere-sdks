/**
 * LLMCapability.ts
 *
 * Actor-based LLM capability that owns model lifecycle and generation.
 * Uses ManagedLifecycle for unified lifecycle + analytics handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/LLMCapability.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { LLMFramework } from '../../Core/Models/Framework/LLMFramework';
import { ServiceRegistry } from '../../Foundation/DependencyInjection/ServiceRegistry';
import type { ExecutionTarget } from '../../types/enums';
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
  type RunAnywhereGenerationOptions,
} from './LLMModels';
import type { LLMService } from '../../Core/Protocols/LLM/LLMService';
import type { GenerationOptions } from '../../Capabilities/TextGeneration/Models/GenerationOptions';
import type { GenerationResult } from '../../Capabilities/TextGeneration/Models/GenerationResult';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';
import { PerformanceMetricsImpl } from '../../Capabilities/TextGeneration/Models/PerformanceMetrics';
import { ManagedLifecycle } from '../../Core/Capabilities/ManagedLifecycle';
import type { ComponentConfiguration } from '../../Core/Capabilities/CapabilityProtocols';

/**
 * Generation analytics metrics
 * Matches iOS: GenerationMetrics struct
 */
export interface GenerationMetrics {
  /** Total number of analytics events */
  totalEvents: number;
  /** Time when tracking started */
  startTime: Date | null;
  /** Time of last event */
  lastEventTime: Date | null;
  /** Total number of all generations (streaming + non-streaming) */
  totalGenerations: number;
  /** Number of streaming generations */
  streamingGenerations: number;
  /** Number of non-streaming generations */
  nonStreamingGenerations: number;
  /** Average time to first token in seconds (only for streaming generations) */
  averageTimeToFirstToken: number;
  /** Average tokens per second across all generations */
  averageTokensPerSecond: number;
  /** Total input tokens processed */
  totalInputTokens: number;
  /** Total output tokens generated */
  totalOutputTokens: number;
}

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
 * Language Model capability
 *
 * Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking,
 * eliminating duplicate lifecycle management code.
 */
export class LLMCapability extends BaseComponent<LLMServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.LLM;

  private readonly llmConfiguration: LLMConfiguration;
  private conversationContext: {
    systemPrompt?: string | null;
    messages?: Message[];
  } | null = null;

  /**
   * Managed lifecycle with integrated event tracking
   * Matches iOS: private let managedLifecycle: ManagedLifecycle<LLMService>
   */
  private readonly managedLifecycle: ManagedLifecycle<LLMService>;

  // MARK: - Initialization

  constructor(configuration: LLMConfiguration) {
    super(configuration);
    this.llmConfiguration = configuration;

    // Preload context if provided
    if (configuration.preloadContext) {
      this.conversationContext = { systemPrompt: configuration.preloadContext };
    }

    // Create managed lifecycle for LLM with load/unload functions
    this.managedLifecycle = ManagedLifecycle.forLLM<LLMService>(
      // Load resource function
      async (resourceId: string, _config: ComponentConfiguration | null) => {
        return await this.loadLLMService(resourceId);
      },
      // Unload resource function
      async (service: LLMService) => {
        await service.cleanup();
      }
    );

    // Configure lifecycle with our configuration
    this.managedLifecycle.configure(configuration as ComponentConfiguration);
  }

  // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)
  // All lifecycle operations are delegated to ManagedLifecycle which handles analytics automatically

  /**
   * Whether a model is currently loaded
   * Matches iOS: public var isModelLoaded: Bool { get async { await managedLifecycle.isLoaded } }
   */
  get isModelLoaded(): boolean {
    return this.managedLifecycle.isLoaded;
  }

  /**
   * The currently loaded model ID
   * Matches iOS: public var currentModelId: String? { get async { await managedLifecycle.currentResourceId } }
   */
  get currentModelId(): string | null {
    return this.managedLifecycle.currentResourceId;
  }

  /**
   * Whether the currently loaded service supports true streaming generation
   * Matches iOS: public var supportsStreaming: Bool { get async { ... } }
   * @returns `true` if streaming is supported, `false` otherwise
   * @note Returns `false` if no model is loaded
   */
  get supportsStreaming(): boolean {
    const service = this.managedLifecycle.currentService;
    if (!service) {
      return false;
    }
    // Check if the service has a generateStream method
    return typeof service.generateStream === 'function';
  }

  // MARK: - Analytics

  /**
   * Get current generation analytics metrics
   * Matches iOS: public func getAnalyticsMetrics() async -> GenerationMetrics
   */
  getAnalyticsMetrics(): GenerationMetrics {
    return this._analyticsMetrics;
  }

  /**
   * Internal analytics state
   */
  private _analyticsMetrics: GenerationMetrics = {
    totalEvents: 0,
    startTime: null,
    lastEventTime: null,
    totalGenerations: 0,
    streamingGenerations: 0,
    nonStreamingGenerations: 0,
    averageTimeToFirstToken: 0,
    averageTokensPerSecond: 0,
    totalInputTokens: 0,
    totalOutputTokens: 0,
  };

  /**
   * Update analytics after a generation
   */
  private updateAnalytics(metrics: {
    isStreaming: boolean;
    timeToFirstToken?: number;
    tokensPerSecond: number;
    inputTokens: number;
    outputTokens: number;
  }): void {
    const now = new Date();

    if (!this._analyticsMetrics.startTime) {
      this._analyticsMetrics.startTime = now;
    }
    this._analyticsMetrics.lastEventTime = now;
    this._analyticsMetrics.totalEvents++;
    this._analyticsMetrics.totalGenerations++;

    if (metrics.isStreaming) {
      this._analyticsMetrics.streamingGenerations++;
      if (metrics.timeToFirstToken !== undefined) {
        // Update running average of TTFT
        const ttftCount = this._analyticsMetrics.streamingGenerations;
        this._analyticsMetrics.averageTimeToFirstToken =
          (this._analyticsMetrics.averageTimeToFirstToken * (ttftCount - 1) +
            metrics.timeToFirstToken) /
          ttftCount;
      }
    } else {
      this._analyticsMetrics.nonStreamingGenerations++;
    }

    // Update running average of tokens per second
    const genCount = this._analyticsMetrics.totalGenerations;
    this._analyticsMetrics.averageTokensPerSecond =
      (this._analyticsMetrics.averageTokensPerSecond * (genCount - 1) +
        metrics.tokensPerSecond) /
      genCount;

    this._analyticsMetrics.totalInputTokens += metrics.inputTokens;
    this._analyticsMetrics.totalOutputTokens += metrics.outputTokens;
  }

  /**
   * Load a model by ID
   * Matches iOS: public func loadModel(_ modelId: String) async throws
   */
  async loadModel(modelId: string): Promise<void> {
    const llmService = await this.managedLifecycle.load(modelId);
    // Update BaseComponent's service reference for compatibility
    this.service = new LLMServiceWrapper(llmService);
  }

  /**
   * Unload the currently loaded model
   * Matches iOS: public func unload() async throws
   */
  async unloadModel(): Promise<void> {
    await this.managedLifecycle.unload();
    this.service = null;
  }

  // MARK: - Private Service Loading

  /**
   * Load LLM service for a given model ID
   * Called by ManagedLifecycle during load()
   */
  private async loadLLMService(modelId: string): Promise<LLMService> {
    // Try to get a registered LLM provider from central registry
    const provider = ServiceRegistry.shared.llmProvider(modelId);

    if (!provider) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ServiceRegistry.shared.registerLLMProvider(provider).'
      );
    }

    // Create service through provider
    const llmService = await provider.createLLMService(this.llmConfiguration);

    // Initialize the service
    await llmService.initialize(modelId);

    return llmService;
  }

  // MARK: - Service Creation (BaseComponent compatibility)

  protected override async createService(): Promise<LLMServiceWrapper> {
    // If modelId is provided in config, load through managed lifecycle
    if (this.llmConfiguration.modelId) {
      await this.loadModel(this.llmConfiguration.modelId);
      if (!this.service) {
        throw new SDKError(
          SDKErrorCode.InvalidState,
          'Service was not created after loading model'
        );
      }
      return this.service;
    }

    // Fallback: create service without loading model (caller will load model separately)
    return new LLMServiceWrapper(null);
  }

  protected override async performCleanup(): Promise<void> {
    await this.managedLifecycle.reset();
    this.conversationContext = null;
  }

  // MARK: - Public API

  /**
   * Generate text from a simple prompt
   */
  public async generate(
    prompt: string,
    systemPrompt?: string | null
  ): Promise<LLMOutput> {
    this.ensureReady();

    const input: LLMInput = {
      messages: [{ role: MessageRole.User, content: prompt }],
      systemPrompt: systemPrompt ?? null,
      context: null,
      options: null,
      validate: () => {
        if (!prompt || prompt.trim().length === 0) {
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'LLMInput must contain at least one message'
          );
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
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'LLMInput must contain at least one message'
          );
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

    // Use managedLifecycle.requireService() for iOS parity
    const llmService = this.managedLifecycle.requireService();
    const modelId = this.managedLifecycle.resourceIdOrUnknown();

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

    // Generate response using service from managed lifecycle
    const result: GenerationResult = await llmService.generate(prompt, options);

    const generationTime = (Date.now() - startTime) / 1000; // seconds

    // Extract token usage from result
    const promptTokens = Math.floor(prompt.length / 4); // Rough estimate
    const completionTokens =
      result.tokensUsed ?? Math.floor(result.text.length / 4);
    const tokensPerSecond = completionTokens / generationTime;

    // Update analytics
    this.updateAnalytics({
      isStreaming: false,
      tokensPerSecond,
      inputTokens: promptTokens,
      outputTokens: completionTokens,
    });

    // Create output
    return {
      text: result.text,
      tokenUsage: {
        promptTokens,
        completionTokens,
        totalTokens: promptTokens + completionTokens,
      },
      metadata: {
        modelId,
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

    // Use managedLifecycle.requireService() for iOS parity
    const llmService = this.managedLifecycle.requireService();

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
    if (llmService.generateStream) {
      let accumulatedText = '';
      const result = await llmService.generateStream(
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
      const result = await llmService.generate(fullPrompt, options);
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

    // Use managedLifecycle.requireService() for iOS parity
    const llmService = this.managedLifecycle.requireService();
    const _modelId = this.managedLifecycle.resourceIdOrUnknown();

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
    let streamResolve:
      | ((value: IteratorResult<LLMStreamToken>) => void)
      | null = null;
    let streamEnded = false;

    // Merge options with configuration defaults

    const generationOptions: GenerationOptions = {
      maxTokens: options?.maxTokens ?? this.llmConfiguration.maxTokens,
      temperature: options?.temperature ?? this.llmConfiguration.temperature,
      systemPrompt: options?.systemPrompt ?? this.llmConfiguration.systemPrompt,
      topP: options?.topP,
      stopSequences: options?.stopSequences,
      streamingEnabled: true,
      preferredExecutionTarget: options?.executionTarget
        ? (options.executionTarget as ExecutionTarget)
        : undefined,
      preferredFramework: options?.preferredFramework as
        | LLMFramework
        | undefined,
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
    (async () => {
      try {
        if (!llmService?.generateStream) {
          throw new SDKError(
            SDKErrorCode.FeatureNotAvailable,
            'Streaming not supported by current LLM service'
          );
        }

        let tokenIndex = 0;

        // Reset start time right before inference
        collector.startTime = Date.now();

        await llmService.generateStream(
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

        // Update analytics for streaming generation
        const totalTimeMs = Date.now() - collector.startTime;
        const timeToFirstTokenMs = collector.firstTokenTime
          ? collector.firstTokenTime - collector.startTime
          : null;
        const tokensPerSecond =
          totalTimeMs > 0 ? (collector.tokenCount / totalTimeMs) * 1000 : 0;

        this.updateAnalytics({
          isStreaming: true,
          timeToFirstToken:
            timeToFirstTokenMs !== null ? timeToFirstTokenMs / 1000 : undefined,
          tokensPerSecond,
          inputTokens: Math.floor(fullPrompt.length / 4), // Rough estimate
          outputTokens: collector.tokenCount,
        });

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
          const output = this.buildOutputFromCollector(
            collector,
            generationOptions
          );
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
    const stream = (async function* (): AsyncGenerator<
      LLMStreamToken,
      void,
      unknown
    > {
      while (!streamEnded || tokenQueue.length > 0) {
        if (tokenQueue.length > 0) {
          const token = tokenQueue.shift();
          if (!token) continue;
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
      tokenCount: number;
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
    const tokensPerSecond =
      totalTimeSec > 0 ? collector.tokenCount / totalTimeSec : 0;

    // Estimate prompt tokens (rough estimate: 1 token ≈ 4 characters)
    const promptTokens = Math.floor(collector.fullText.length / 4);
    const completionTokens = collector.tokenCount;

    const _performanceMetrics = new PerformanceMetricsImpl({
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
        modelId: this.managedLifecycle.resourceIdOrUnknown(),
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
  private buildPrompt(
    messages: Message[],
    systemPrompt?: string | null
  ): string {
    let prompt = '';

    if (systemPrompt) {
      prompt += `System: ${systemPrompt}\n\n`;
    }

    for (const message of messages) {
      const roleLabel =
        message.role === MessageRole.User ? 'User' : 'Assistant';
      prompt += `${roleLabel}: ${message.content}\n\n`;
    }

    prompt += 'Assistant:';
    return prompt;
  }
}
