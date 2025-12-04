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
import { type LLMInput, type LLMOutput, type Message, MessageRole, FinishReason } from './LLMModels';
import type { LLMService } from '../../Core/Protocols/LLM/LLMService';
import type { LLMServiceProvider } from '../../Core/Protocols/LLM/LLMServiceProvider';
import type { GenerationOptions } from '../../Capabilities/TextGeneration/Models/GenerationOptions';
import type { GenerationResult } from '../../Capabilities/TextGeneration/Models/GenerationResult';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';

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

  // MARK: - Helper Methods

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
