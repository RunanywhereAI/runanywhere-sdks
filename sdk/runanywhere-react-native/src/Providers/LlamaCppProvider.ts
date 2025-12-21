/**
 * LlamaCppProvider.ts
 *
 * LlamaCPP service provider for React Native SDK.
 * Mirrors Swift SDK's LlamaCPPServiceProvider pattern.
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPPServiceProvider.swift
 */

import type { LLMServiceProvider } from '../Core/Protocols/LLM/LLMServiceProvider';
import type { LLMService } from '../Core/Protocols/LLM/LLMService';
import type { ModelInfo } from '../types';
import type { GenerationOptions } from '../Capabilities/TextGeneration/Models/GenerationOptions';
import type { GenerationResult } from '../Capabilities/TextGeneration/Models/GenerationResult';
import { LLMFramework } from '../Core/Models/Framework/LLMFramework';
import { LLMFramework as CatalogFramework } from '../types'; // For catalog lookup
import { PerformanceMetricsImpl } from '../Capabilities/TextGeneration/Models/PerformanceMetrics';
import { getCatalogModelsByFramework } from '../Data/modelCatalog';
import { SDKError, SDKErrorCode } from '../Public/Errors/SDKError';
import { requireNativeModule, type NativeRunAnywhereModule } from '../native';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

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
 *
 * Pattern matching strategy (hierarchical):
 * 1. Format suffix matching (gguf, ggml)
 * 2. Framework name matching (llamacpp, llama-cpp)
 * 3. Model family + quantization pattern matching
 */
const logger = new SDKLogger('LlamaCppProvider');

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
   *
   * This is called during SDK initialization (like Swift SDK's onRegistration)
   */
  static register(): void {
    logger.info('Registering LlamaCPP service provider');

    // Import ServiceRegistry dynamically to avoid circular dependency
    const {
      ServiceRegistry,
    } = require('../Foundation/DependencyInjection/ServiceRegistry');

    // Register with priority 100 (default priority)
    ServiceRegistry.shared.registerLLMProvider(LlamaCppProvider.shared, 100);

    logger.info('LlamaCPP service provider registered successfully');
  }

  /**
   * Check if this provider can handle the given model
   *
   * Pattern matching strategy (from Swift SDK):
   * 1. GGUF format (llama.cpp native)
   * 2. GGML format (older)
   * 3. Explicit framework references
   * 4. Model names with quantization patterns
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
   *
   * This method exposes models that LlamaCPP can handle.
   * Called during provider registration to populate ModelRegistry.
   */
  getProvidedModels(): ModelInfo[] {
    // Get all GGUF models from catalog (use types/enums version for catalog lookup)
    const ggufModels = getCatalogModelsByFramework(CatalogFramework.LlamaCpp);

    logger.debug(`Providing ${ggufModels.length} GGUF models`);

    return ggufModels;
  }

  /**
   * Create an LLM service for the given configuration
   *
   * This mirrors Swift SDK's createLLMService implementation.
   */
  async createLLMService(
    configuration: import('../Features/LLM/LLMConfiguration').LLMConfiguration
  ): Promise<LLMService> {
    // Extract LlamaCpp-specific configuration
    const llamaCppConfig: LlamaCppConfiguration = {
      modelId: configuration.modelId ?? undefined,
      configJson: undefined, // LLMConfiguration doesn't have configJson
    };
    logger.info(`Creating LLM service for model: ${llamaCppConfig.modelId}`);

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
      // Query ModelRegistry for model info
      const { ModelRegistry } = require('../services/ModelRegistry');
      const modelInfo = await ModelRegistry.getModel(configuration.modelId);

      if (!modelInfo) {
        throw new SDKError(
          SDKErrorCode.ModelNotFound,
          `Model '${configuration.modelId}' not found in registry`
        );
      }

      // Check if model is downloaded
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

    logger.info('LLM service created successfully');

    return service;
  }

  /**
   * Lifecycle hook called when provider is registered
   *
   * This matches Swift SDK's onRegistration() pattern.
   * Called automatically by ServiceRegistry during registration.
   */
  onRegistration(): void {
    logger.debug('onRegistration() called');

    // Register models with ModelRegistry (in-memory cache)
    // This ensures models are discoverable immediately
    const models = this.getProvidedModels();

    logger.info(`Registered ${models.length} models through provider`);
  }
}

const serviceLogger = new SDKLogger('LlamaCppService');

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

    serviceLogger.info(`Initializing with model: ${pathToLoad}`);

    // Load model via native module
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
    serviceLogger.info('Model loaded successfully');
  }

  async generate(
    prompt: string,
    options?: GenerationOptions
  ): Promise<GenerationResult> {
    const startTime = Date.now();

    // Build options JSON for native module
    const optionsJson = JSON.stringify({
      systemPrompt: options?.systemPrompt || null,
      maxTokens: options?.maxTokens || 512,
      temperature: options?.temperature || 0.7,
    });

    const result = await this.native.generate(prompt, optionsJson);

    const latencyMs = Date.now() - startTime;

    // Import enums at runtime to avoid type issues
    const { ExecutionTarget, HardwareAcceleration } = require('../types/enums');

    // Return full GenerationResult matching the interface
    return {
      text: result,
      thinkingContent: null,
      tokensUsed: 0, // Native layer should provide this
      modelUsed: this.currentModel || 'unknown',
      latencyMs,
      executionTarget: ExecutionTarget.OnDevice,
      savedAmount: 0,
      framework: LLMFramework.LlamaCpp,
      hardwareUsed: HardwareAcceleration.CPU,
      memoryUsed: 0,
      performanceMetrics: new PerformanceMetricsImpl({
        inferenceTimeMs: latencyMs,
      }),
      structuredOutputValidation: null,
      thinkingTokens: null,
      responseTokens: 0,
    };
  }

  async cleanup(): Promise<void> {
    serviceLogger.debug('Cleaning up service');
    await this.native.unloadTextModel();
    this.isReady = false;
    this.currentModel = null;
  }
}
