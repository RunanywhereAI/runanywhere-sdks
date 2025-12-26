/**
 * @runanywhere/llamacpp - LlamaCPP Provider
 *
 * LlamaCPP service provider for React Native SDK.
 * Mirrors Swift SDK's LlamaCPPServiceProvider pattern.
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPPServiceProvider.swift
 */

import {
  type ModelInfo,
  LLMFramework,
  SDKError,
  SDKErrorCode,
  ServiceRegistry,
  ModelRegistry,
  type LLMServiceProvider,
  type LLMService,
  type GenerationOptions,
  type GenerationResult,
  type LLMConfiguration,
  ExecutionTarget,
  HardwareAcceleration,
  PerformanceMetricsImpl,
} from '@runanywhere/core';
import {
  requireNativeModule,
  type NativeRunAnywhereModule,
} from '@runanywhere/native';

// Simple logger for this package
const DEBUG = typeof __DEV__ !== 'undefined' ? __DEV__ : false;
const log = {
  info: (msg: string) => DEBUG && console.log(`[LlamaCppProvider] ${msg}`),
  debug: (msg: string) => DEBUG && console.log(`[LlamaCppProvider] ${msg}`),
  warning: (msg: string) => console.warn(`[LlamaCppProvider] ${msg}`),
};

/**
 * LlamaCpp service configuration
 */
export interface LlamaCppConfiguration {
  modelId?: string;
  configJson?: string;
}

/**
 * LlamaCPP Service Provider
 *
 * This provider handles GGUF/GGML models through the llama.cpp backend.
 * It follows the same pattern as Swift SDK's LlamaCPPServiceProvider.
 */
export class LlamaCppProvider implements LLMServiceProvider {
  readonly name = 'LlamaCpp';

  private static _instance: LlamaCppProvider | null = null;

  /**
   * Singleton instance (mirroring Swift SDK pattern)
   */
  static get shared(): LlamaCppProvider {
    if (!LlamaCppProvider._instance) {
      LlamaCppProvider._instance = new LlamaCppProvider();
    }
    return LlamaCppProvider._instance;
  }

  /**
   * Register the LlamaCPP provider with ServiceRegistry
   */
  static register(): void {
    log.info('Registering LlamaCPP service provider');

    // Register with priority 100 (default priority)
    ServiceRegistry.shared.registerLLMProvider(LlamaCppProvider.shared, 100);

    log.info('LlamaCPP service provider registered successfully');
  }

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean {
    if (!modelId) {
      return false;
    }

    const lowercased = modelId.toLowerCase();

    // Primary: GGUF format (llama.cpp native)
    if (lowercased.includes('gguf') || lowercased.endsWith('.gguf')) {
      return true;
    }

    // Secondary: GGML format (older)
    if (lowercased.includes('ggml') || lowercased.endsWith('.ggml')) {
      return true;
    }

    // Tertiary: Explicit framework references
    if (lowercased.includes('llamacpp') || lowercased.includes('llama-cpp')) {
      return true;
    }

    // Quaternary: Common model names with quantization patterns
    const hasModelFamily =
      lowercased.includes('smollm') ||
      lowercased.includes('mistral') ||
      lowercased.includes('llama') ||
      lowercased.includes('phi') ||
      lowercased.includes('qwen') ||
      lowercased.includes('gemma') ||
      lowercased.includes('lfm');

    const hasQuantization =
      lowercased.includes('q4') ||
      lowercased.includes('q5') ||
      lowercased.includes('q6') ||
      lowercased.includes('q8') ||
      lowercased.includes('q2') ||
      lowercased.includes('q3');

    if (hasModelFamily && hasQuantization) {
      return true;
    }

    return false;
  }

  /**
   * Get models provided by this provider
   */
  getProvidedModels(): ModelInfo[] {
    // For now, return empty array - models are registered via LlamaCPP.addModel()
    // In the future, this could fetch from a catalog
    log.debug('Providing registered GGUF models');
    return [];
  }

  /**
   * Create an LLM service for the given configuration
   */
  async createLLMService(
    configuration: { modelId?: string | null }
  ): Promise<LLMService> {
    const llamaCppConfig: LlamaCppConfiguration = {
      modelId: configuration.modelId ?? undefined,
      configJson: undefined,
    };
    log.info(`Creating LLM service for model: ${llamaCppConfig.modelId}`);

    // Verify we can handle this model
    if (!this.canHandle(configuration?.modelId)) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        `LlamaCppProvider cannot handle model: ${configuration?.modelId}`
      );
    }

    // Get model info from registry
    let modelPath: string | null = null;

    if (configuration?.modelId) {
      const modelInfo = await ModelRegistry.getModel(configuration.modelId);

      if (!modelInfo) {
        throw new SDKError(
          SDKErrorCode.ModelNotFound,
          `Model '${configuration.modelId}' not found in registry`
        );
      }

      if (!modelInfo.localPath) {
        throw new SDKError(
          SDKErrorCode.ModelNotFound,
          `Model '${configuration.modelId}' is not downloaded. Call downloadModel() first.`
        );
      }

      modelPath = modelInfo.localPath;
    }

    // Create native LLM service wrapper
    const service = new LlamaCppService(llamaCppConfig, modelPath);

    log.info('LLM service created successfully');

    return service;
  }

  /**
   * Lifecycle hook called when provider is registered
   */
  onRegistration(): void {
    log.debug('onRegistration() called');
    const models = this.getProvidedModels();
    log.info(`Registered ${models.length} models through provider`);
  }
}

/**
 * LlamaCPP Service Implementation
 *
 * Wraps the native LlamaCPP backend for text generation.
 */
class LlamaCppService implements LLMService {
  private configuration: LlamaCppConfiguration;
  private modelPath: string | null;
  private native: NativeRunAnywhereModule;

  isReady: boolean = false;
  currentModel: string | null = null;

  constructor(configuration: LlamaCppConfiguration, modelPath: string | null) {
    this.configuration = configuration;
    this.modelPath = modelPath;
    this.native = requireNativeModule();
  }

  async initialize(modelPath?: string): Promise<void> {
    const pathToLoad = modelPath || this.modelPath;

    if (!pathToLoad) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Model path is required for LlamaCPP service initialization'
      );
    }

    log.info(`Initializing with model: ${pathToLoad}`);

    const config = this.configuration?.configJson ?? undefined;
    const success = await this.native.loadTextModel(pathToLoad, config);

    if (!success) {
      const error = await this.native.getLastError();
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        `Failed to load LlamaCPP model: ${error}`
      );
    }

    this.isReady = true;
    this.currentModel = pathToLoad;
    log.info('Model loaded successfully');
  }

  async generate(
    prompt: string,
    options?: GenerationOptions
  ): Promise<GenerationResult> {
    const startTime = Date.now();

    const optionsJson = JSON.stringify({
      systemPrompt: options?.systemPrompt || null,
      maxTokens: options?.maxTokens || 512,
      temperature: options?.temperature || 0.7,
    });

    const result = await this.native.generate(prompt, optionsJson);

    const latencyMs = Date.now() - startTime;

    return {
      text: result,
      thinkingContent: null,
      tokensUsed: 0,
      modelUsed: this.currentModel || 'unknown',
      latencyMs,
      executionTarget: ExecutionTarget.OnDevice,
      savedAmount: 0,
      framework: LLMFramework.LlamaCpp,
      hardwareUsed: HardwareAcceleration.CPU,
      memoryUsed: 0,
      performanceMetrics: new PerformanceMetricsImpl({ inferenceTimeMs: latencyMs }),
      structuredOutputValidation: null,
      thinkingTokens: null,
      responseTokens: 0,
    };
  }

  async cleanup(): Promise<void> {
    log.debug('Cleaning up service');
    await this.native.unloadTextModel();
    this.isReady = false;
    this.currentModel = null;
  }
}
