/**
 * LLMComponent.ts
 *
 * Language Model component for RunAnywhere React Native SDK.
 * Follows the exact architecture and patterns from Swift SDK's LLMComponent.swift.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift
 */

import { NativeModules } from 'react-native';
import { BaseComponent } from '../BaseComponent';
import type { ComponentConfiguration, ComponentInput, ComponentOutput } from '../BaseComponent';
import { SDKError, SDKErrorCode } from '../../errors';
import { LLMFramework, SDKComponent } from '../../types/enums';
import type { GenerationOptions } from '../../types';

// ============================================================================
// LLM Configuration
// ============================================================================

/**
 * Quantization level for model loading
 * Reference: QuantizationLevel enum in LLMComponent.swift
 */
export enum QuantizationLevel {
  Q4V0 = 'Q4_0',
  Q4KM = 'Q4_K_M',
  Q5KM = 'Q5_K_M',
  Q6K = 'Q6_K',
  Q8V0 = 'Q8_0',
  F16 = 'F16',
  F32 = 'F32',
}

/**
 * Configuration for LLM component
 * Reference: LLMConfiguration in LLMComponent.swift
 *
 * Conforms to ComponentConfiguration and ComponentInitParameters protocols
 */
export interface LLMConfiguration extends ComponentConfiguration {
  /** Component type */
  readonly componentType: SDKComponent;

  /** Model ID */
  modelId?: string;

  // Model loading parameters
  /** Context length (default: 2048) */
  contextLength: number;

  /** Use GPU if available (default: true) */
  useGPUIfAvailable: boolean;

  /** Quantization level */
  quantizationLevel?: QuantizationLevel;

  /** Token cache size in MB (default: 100) */
  cacheSize: number;

  /** Optional system prompt to preload */
  preloadContext?: string;

  // Default generation parameters
  /** Temperature (default: 0.7) */
  temperature: number;

  /** Max tokens to generate (default: 100) */
  maxTokens: number;

  /** System prompt */
  systemPrompt?: string;

  /** Enable streaming (default: true) */
  streamingEnabled: boolean;

  /** Preferred framework */
  preferredFramework?: LLMFramework;
}

/**
 * Default LLM configuration values
 */
const DEFAULT_LLM_VALUES = {
  contextLength: 2048,
  useGPUIfAvailable: true,
  cacheSize: 100,
  temperature: 0.7,
  maxTokens: 100,
  streamingEnabled: true,
};

/**
 * Default LLM configuration
 */
export const DEFAULT_LLM_CONFIGURATION = {
  ...DEFAULT_LLM_VALUES,
  validate() {},
};

/**
 * Create LLM configuration with defaults
 */
export function createLLMConfiguration(
  config: Partial<Omit<LLMConfiguration, 'componentType' | 'validate'>>
): LLMConfiguration {
  const merged = {
    componentType: SDKComponent.LLM as SDKComponent,
    ...DEFAULT_LLM_VALUES,
    ...config,
    systemPrompt: config.systemPrompt ?? config.preloadContext,
  };

  return {
    ...merged,
    validate(): void {
      if (merged.contextLength <= 0 || merged.contextLength > 32768) {
        throw new SDKError(
          SDKErrorCode.ValidationFailed,
          'Context length must be between 1 and 32768'
        );
      }
      if (merged.cacheSize < 0 || merged.cacheSize > 1000) {
        throw new SDKError(
          SDKErrorCode.ValidationFailed,
          'Cache size must be between 0 and 1000 MB'
        );
      }
      if (merged.temperature < 0 || merged.temperature > 2.0) {
        throw new SDKError(
          SDKErrorCode.ValidationFailed,
          'Temperature must be between 0 and 2.0'
        );
      }
      if (merged.maxTokens <= 0 || merged.maxTokens > merged.contextLength) {
        throw new SDKError(
          SDKErrorCode.ValidationFailed,
          'Max tokens must be between 1 and context length'
        );
      }
    },
  };
}

// ============================================================================
// LLM Input/Output Types
// ============================================================================

/**
 * Message role enum
 * Reference: MessageRole in Conversation.swift
 */
export enum MessageRole {
  System = 'system',
  User = 'user',
  Assistant = 'assistant',
}

/**
 * Message in a conversation
 * Reference: Message in Conversation.swift
 */
export interface Message {
  /** Role of the message sender */
  role: MessageRole;

  /** Content of the message */
  content: string;

  /** Optional metadata */
  metadata?: Record<string, string>;

  /** Timestamp */
  timestamp: Date;
}

/**
 * Context for a conversation
 * Reference: Context in Conversation.swift
 */
export interface Context {
  /** System prompt */
  systemPrompt?: string;

  /** Previous messages */
  messages: Message[];

  /** Maximum messages to keep */
  maxMessages: number;

  /** Additional metadata */
  metadata: Record<string, string>;
}

/**
 * Input for Language Model generation
 * Reference: LLMInput in LLMComponent.swift
 */
export interface LLMInput extends ComponentInput {
  /** Messages in the conversation */
  messages: Message[];

  /** Optional system prompt override */
  systemPrompt?: string;

  /** Optional context for conversation */
  context?: Context;

  /** Optional generation options override */
  options?: GenerationOptions;

  /** Validate input */
  validate(): void;
}

/**
 * Token usage information
 * Reference: TokenUsage in LLMComponent.swift
 */
export interface TokenUsage {
  /** Prompt tokens */
  promptTokens: number;

  /** Completion tokens */
  completionTokens: number;

  /** Total tokens */
  totalTokens: number;
}

/**
 * Generation metadata
 * Reference: GenerationMetadata in LLMComponent.swift
 */
export interface GenerationMetadata {
  /** Model ID used */
  modelId: string;

  /** Temperature used */
  temperature: number;

  /** Generation time in seconds */
  generationTime: number;

  /** Tokens per second */
  tokensPerSecond?: number;
}

/**
 * Finish reason enum
 * Reference: FinishReason in LLMComponent.swift
 */
export enum FinishReason {
  Completed = 'completed',
  MaxTokens = 'max_tokens',
  StopSequence = 'stop_sequence',
  ContentFilter = 'content_filter',
  Error = 'error',
}

/**
 * Output from Language Model generation
 * Reference: LLMOutput in LLMComponent.swift
 */
export interface LLMOutput extends ComponentOutput {
  /** Generated text */
  text: string;

  /** Token usage statistics */
  tokenUsage: TokenUsage;

  /** Generation metadata */
  metadata: GenerationMetadata;

  /** Finish reason */
  finishReason: FinishReason;

  /** Timestamp */
  timestamp: Date;
}

// ============================================================================
// LLM Service Protocol
// ============================================================================

/**
 * Protocol for language model services
 * Reference: LLMService protocol in LLMComponent.swift
 */
export interface LLMService {
  /** Initialize the LLM service with optional model path */
  initialize(modelPath?: string): Promise<void>;

  /** Generate text from prompt */
  generate(prompt: string, options: GenerationOptions): Promise<string>;

  /** Stream generation token by token */
  streamGenerate(
    prompt: string,
    options: GenerationOptions,
    onToken: (token: string) => void
  ): Promise<void>;

  /** Check if service is ready */
  isReady: boolean;

  /** Get current model identifier */
  currentModel: string | null;

  /** Cleanup resources */
  cleanup(): Promise<void>;
}

/**
 * Service wrapper for LLM service
 * Reference: LLMServiceWrapper in LLMComponent.swift
 */
class LLMServiceWrapperImpl {
  public wrappedService: LLMService | null = null;

  constructor(service?: LLMService) {
    this.wrappedService = service || null;
  }
}

// Export as LLMServiceWrapper
export { LLMServiceWrapperImpl as LLMServiceWrapper };

// ============================================================================
// Native LLM Service Implementation
// ============================================================================

/**
 * Native implementation of LLMService using NativeRunAnywhere
 * This bridges to the native platform implementations
 */
class NativeLLMService implements LLMService {
  private nativeModule: any;
  private _isReady = false;
  private _currentModel: string | null = null;

  constructor() {
    this.nativeModule = NativeModules.RunAnywhere;
  }

  async initialize(modelPath?: string): Promise<void> {
    if (!this.nativeModule) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native module not available'
      );
    }

    // For now, just mark as ready
    // In real implementation, this would initialize the native LLM service
    this._isReady = true;
    if (modelPath) {
      this._currentModel = modelPath;
    }
  }

  async generate(prompt: string, options: GenerationOptions): Promise<string> {
    if (!this._isReady) {
      throw new SDKError(SDKErrorCode.NotInitialized, 'LLM service not initialized');
    }

    // Call native module for generation
    const optionsJson = JSON.stringify({
      maxTokens: options.maxTokens || 100,
      temperature: options.temperature || 0.7,
      topP: options.topP || 1.0,
      stopSequences: options.stopSequences || [],
    });

    const result = await this.nativeModule.generate?.(prompt, optionsJson);

    if (!result) {
      throw new SDKError(SDKErrorCode.GenerationFailed, 'Generation failed');
    }

    return result;
  }

  async streamGenerate(
    prompt: string,
    options: GenerationOptions,
    onToken: (token: string) => void
  ): Promise<void> {
    if (!this._isReady) {
      throw new SDKError(SDKErrorCode.NotInitialized, 'LLM service not initialized');
    }

    // Call native streaming method
    const optionsJson = JSON.stringify({
      maxTokens: options.maxTokens || 100,
      temperature: options.temperature || 0.7,
      topP: options.topP || 1.0,
      stopSequences: options.stopSequences || [],
      streamingEnabled: true,
    });

    // Create stream
    const streamId = await this.nativeModule.createGenerationStream?.(prompt, optionsJson);

    if (streamId < 0) {
      throw new SDKError(SDKErrorCode.StreamCreationFailed, 'Failed to create generation stream');
    }

    try {
      // Poll for tokens
      let isComplete = false;
      while (!isComplete) {
        const tokenJson = await this.nativeModule.getNextToken?.(streamId);
        if (tokenJson) {
          const tokenData = JSON.parse(tokenJson);
          if (tokenData.token) {
            onToken(tokenData.token);
          }
          if (tokenData.isComplete) {
            isComplete = true;
          }
        } else {
          // No more tokens
          isComplete = true;
        }
      }
    } finally {
      // Cleanup stream
      await this.nativeModule.destroyGenerationStream?.(streamId);
    }
  }

  get isReady(): boolean {
    return this._isReady;
  }

  get currentModel(): string | null {
    return this._currentModel;
  }

  async cleanup(): Promise<void> {
    this._isReady = false;
    this._currentModel = null;
  }

  async loadModel(modelPath: string): Promise<void> {
    const result = await this.nativeModule.loadLLMModel?.(modelPath);
    if (!result) {
      const error = await this.nativeModule.getLastError?.() || 'Unknown error';
      throw new SDKError(SDKErrorCode.ModelLoadFailed, `Failed to load LLM model: ${error}`);
    }
    this._currentModel = modelPath;
  }
}

// ============================================================================
// LLM Component
// ============================================================================

/**
 * Language Model component following the clean architecture
 *
 * Extends BaseComponent to provide LLM capabilities with lifecycle management.
 * Matches the Swift SDK LLMComponent implementation exactly.
 *
 * Reference: LLMComponent in LLMComponent.swift
 *
 * @example
 * ```typescript
 * // Create and initialize component
 * const config = createLLMConfiguration({
 *   modelId: 'qwen-2.5-3b',
 *   temperature: 0.8,
 *   maxTokens: 500,
 * });
 *
 * const llm = new LLMComponent(config);
 * await llm.initialize();
 *
 * // Generate text
 * const result = await llm.generate('What is the capital of France?');
 * console.log('Response:', result.text);
 *
 * // Stream generation
 * for await (const token of llm.generateStream('Tell me a story')) {
 *   process.stdout.write(token);
 * }
 * ```
 */
export class LLMComponent extends BaseComponent<LLMServiceWrapperImpl> {
  // ============================================================================
  // Static Properties
  // ============================================================================

  /**
   * Component type identifier
   * Reference: componentType in LLMComponent.swift
   */
  static override componentType = SDKComponent.LLM;

  // ============================================================================
  // Instance Properties
  // ============================================================================

  private readonly llmConfiguration: LLMConfiguration;
  private conversationContext?: Context;
  private modelPath?: string;

  // ============================================================================
  // Constructor
  // ============================================================================

  constructor(configuration: LLMConfiguration) {
    super(configuration);
    this.llmConfiguration = configuration;

    // Preload context if provided
    if (configuration.preloadContext) {
      this.conversationContext = {
        systemPrompt: configuration.preloadContext,
        messages: [],
        maxMessages: 100,
        metadata: {},
      };
    }
  }

  // ============================================================================
  // Service Creation
  // ============================================================================

  /**
   * Create the LLM service
   *
   * Reference: createService() in LLMComponent.swift
   */
  protected async createService(): Promise<LLMServiceWrapperImpl> {
    // Check if model needs downloading
    if (this.llmConfiguration.modelId) {
      this.modelPath = this.llmConfiguration.modelId;

      // In real implementation, check if model exists
      const needsDownload = false;

      if (needsDownload) {
        // Emit download required event
        this.eventBus.emitComponentInitialization({
          type: 'componentDownloadRequired',
          component: this.componentType,
          modelId: this.llmConfiguration.modelId,
          sizeBytes: 0, // Size will be determined during download
        });

        // Download model
        await this.downloadModel(this.llmConfiguration.modelId);
      }
    }

    // Create native LLM service
    const llmService = new NativeLLMService();

    // Initialize the service
    await llmService.initialize(this.modelPath);

    // Wrap and return the service
    return new LLMServiceWrapperImpl(llmService);
  }

  /**
   * Cleanup resources
   *
   * Reference: performCleanup() in LLMComponent.swift
   */
  protected async performCleanup(): Promise<void> {
    await this.service?.wrappedService?.cleanup();
    this.modelPath = undefined;
    this.conversationContext = undefined;
  }

  // ============================================================================
  // Model Management
  // ============================================================================

  /**
   * Download model with progress tracking
   */
  private async downloadModel(modelId: string): Promise<void> {
    // Emit download started event
    this.eventBus.emitComponentInitialization({
      type: 'componentDownloadStarted',
      component: this.componentType,
      modelId: modelId,
    });

    // Simulate download with progress
    for (let progress = 0.0; progress <= 1.0; progress += 0.1) {
      this.eventBus.emitComponentInitialization({
        type: 'componentDownloadProgress',
        component: this.componentType,
        modelId: modelId,
        progress: progress,
      });
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    // Emit download completed event
    this.eventBus.emitComponentInitialization({
      type: 'componentDownloadCompleted',
      component: this.componentType,
      modelId: modelId,
    });
  }

  // ============================================================================
  // Helper Properties
  // ============================================================================

  /**
   * Get wrapped LLM service
   */
  private get llmService(): LLMService | null {
    return this.service?.wrappedService || null;
  }

  // ============================================================================
  // Public API
  // ============================================================================

  /**
   * Generate text from a simple prompt
   *
   * Reference: generate(_:systemPrompt:) in LLMComponent.swift
   *
   * @param prompt - The prompt text
   * @param systemPrompt - Optional system prompt override
   * @returns LLM output with generated text and metadata
   */
  async generate(prompt: string, systemPrompt?: string): Promise<LLMOutput> {
    this.ensureReady();

    const messages = [{ role: MessageRole.User, content: prompt, timestamp: new Date() }];
    const input: LLMInput = {
      messages: messages,
      systemPrompt: systemPrompt,
      validate: () => {
        if (messages.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'LLMInput must contain at least one message');
        }
      },
    };

    return this.process(input);
  }

  /**
   * Generate with conversation history
   *
   * Reference: generateWithHistory(_:systemPrompt:) in LLMComponent.swift
   *
   * @param messages - Conversation messages
   * @param systemPrompt - Optional system prompt override
   * @returns LLM output with generated text and metadata
   */
  async generateWithHistory(messages: Message[], systemPrompt?: string): Promise<LLMOutput> {
    this.ensureReady();

    const input: LLMInput = {
      messages: messages,
      systemPrompt: systemPrompt,
      validate: () => {
        if (messages.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'LLMInput must contain at least one message');
        }
      },
    };

    return this.process(input);
  }

  /**
   * Process LLM input
   *
   * Reference: process(_:) in LLMComponent.swift
   *
   * @param input - LLM input with messages and options
   * @returns LLM output with generation result
   */
  async process(input: LLMInput): Promise<LLMOutput> {
    this.ensureReady();

    if (!this.llmService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'LLM service not available');
    }

    // Validate input
    input.validate();

    // Use provided options or create from configuration
    const options: GenerationOptions = input.options || {
      maxTokens: this.llmConfiguration.maxTokens,
      temperature: this.llmConfiguration.temperature,
      streamingEnabled: this.llmConfiguration.streamingEnabled,
      preferredFramework: this.llmConfiguration.preferredFramework,
    };

    // Build prompt
    const prompt = this.buildPrompt(
      input.messages,
      input.systemPrompt ?? this.llmConfiguration.systemPrompt
    );

    // Track generation time
    const startTime = Date.now();

    // Generate response
    const response = await this.llmService.generate(prompt, options);

    const generationTime = (Date.now() - startTime) / 1000; // Convert to seconds

    // Calculate tokens (rough estimate - real implementation would get from service)
    const promptTokens = Math.floor(prompt.length / 4);
    const completionTokens = Math.floor(response.length / 4);
    const tokensPerSecond = completionTokens / generationTime;

    // Create output
    return {
      text: response,
      tokenUsage: {
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens + completionTokens,
      },
      metadata: {
        modelId: this.llmService.currentModel || 'unknown',
        temperature: options.temperature || 0.7,
        generationTime: generationTime,
        tokensPerSecond: tokensPerSecond,
      },
      finishReason: FinishReason.Completed,
      timestamp: new Date(),
    };
  }

  /**
   * Stream generation
   *
   * Reference: streamGenerate(_:systemPrompt:) in LLMComponent.swift
   *
   * @param prompt - The prompt text
   * @param systemPrompt - Optional system prompt override
   * @returns Async generator yielding tokens
   */
  async *generateStream(prompt: string, systemPrompt?: string): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    if (!this.llmService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'LLM service not available');
    }

    const options: GenerationOptions = {
      maxTokens: this.llmConfiguration.maxTokens,
      temperature: this.llmConfiguration.temperature,
      streamingEnabled: true,
      preferredFramework: this.llmConfiguration.preferredFramework,
    };

    const fullPrompt = this.buildPrompt(
      [{ role: MessageRole.User, content: prompt, timestamp: new Date() }],
      systemPrompt ?? this.llmConfiguration.systemPrompt
    );

    // Create a queue for tokens
    const tokens: string[] = [];
    let isComplete = false;
    let error: Error | null = null;

    // Start streaming
    const streamPromise = this.llmService.streamGenerate(
      fullPrompt,
      options,
      (token) => {
        tokens.push(token);
      }
    ).then(() => {
      isComplete = true;
    }).catch((err) => {
      error = err;
      isComplete = true;
    });

    // Yield tokens as they arrive
    while (!isComplete || tokens.length > 0) {
      if (error) {
        throw error;
      }

      if (tokens.length > 0) {
        const token = tokens.shift()!;
        yield token;
      } else {
        // Wait a bit for more tokens
        await new Promise(resolve => setTimeout(resolve, 10));
      }
    }

    // Wait for streaming to complete
    await streamPromise;
  }

  /**
   * Get wrapped LLM service for advanced usage
   *
   * Reference: getService() in LLMComponent.swift
   */
  getLLMService(): LLMService | null {
    return this.llmService;
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /**
   * Build prompt from messages and system prompt
   *
   * Reference: buildPrompt(from:systemPrompt:) in LLMComponent.swift
   */
  private buildPrompt(messages: Message[], systemPrompt?: string): string {
    // For LLMSwiftService, we should NOT add role markers as it handles its own templating
    // Just concatenate the messages with newlines
    let prompt = '';

    // Add system prompt first if available
    if (systemPrompt) {
      prompt += `${systemPrompt}\n\n`;
    }

    // Add messages without role markers - let service handle formatting
    for (const message of messages) {
      prompt += `${message.content}\n`;
    }

    // Don't add trailing "Assistant: " - service handles this
    return prompt.trim();
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/**
 * Create an LLM component with configuration
 *
 * @param config - Partial configuration (merged with defaults)
 * @returns Configured LLM component
 */
export function createLLMComponent(
  config?: Partial<Omit<LLMConfiguration, 'componentType' | 'validate'>>
): LLMComponent {
  const configuration = createLLMConfiguration(config || {});
  return new LLMComponent(configuration);
}

