/**
 * Model Registry for RunAnywhere React Native SDK
 *
 * Thin wrapper over native model registry.
 * All logic (caching, filtering, discovery) is in native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import type { LLMFramework, ModelCategory, ModelInfo } from '../types';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('ModelRegistry');

/**
 * Criteria for filtering models (passed to native)
 */
export interface ModelCriteria {
  framework?: LLMFramework;
  category?: ModelCategory;
  downloadedOnly?: boolean;
  availableOnly?: boolean;
}

/**
 * Options for adding a model from URL
 */
export interface AddModelFromURLOptions {
  name: string;
  url: string;
  framework: LLMFramework;
  estimatedSize?: number;
  supportsThinking?: boolean;
}

/**
 * Model Registry - Thin wrapper over native
 *
 * All model management logic lives in native commons.
 */
class ModelRegistryImpl {
  private initialized = false;

  /**
   * Initialize the registry (calls native)
   */
  async initialize(): Promise<void> {
    if (this.initialized) return;

    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available');
      this.initialized = true;
      return;
    }

    try {
      const native = requireNativeModule();
      await native.discoverModels();
      this.initialized = true;
      logger.info('Model registry initialized via native');
    } catch (error) {
      logger.warning('Failed to initialize registry:', { error });
      this.initialized = true;
    }
  }

  /**
   * Discover available models (native)
   */
  async discoverModels(): Promise<ModelInfo[]> {
    if (!isNativeModuleAvailable()) return [];

    const native = requireNativeModule();
    const json = await native.discoverModels();
    return JSON.parse(json);
  }

  /**
   * Get a model by ID (native)
   */
  async getModel(id: string): Promise<ModelInfo | null> {
    if (!isNativeModuleAvailable()) return null;

    const native = requireNativeModule();
    const json = await native.getModel(id);
    if (!json) return null;
    return JSON.parse(json);
  }

  /**
   * Get all models (native)
   */
  async getAllModels(): Promise<ModelInfo[]> {
    if (!isNativeModuleAvailable()) return [];

    const native = requireNativeModule();
    const json = await native.availableModels();
    return JSON.parse(json);
  }

  /**
   * Filter models by criteria (native handles filtering)
   */
  async filterModels(criteria: ModelCriteria): Promise<ModelInfo[]> {
    const allModels = await this.getAllModels();

    // Simple filtering on JS side since native returns all
    let models = allModels;

    if (criteria.framework) {
      models = models.filter(m => m.compatibleFrameworks?.includes(criteria.framework!));
    }
    if (criteria.category) {
      models = models.filter(m => m.category === criteria.category);
    }
    if (criteria.downloadedOnly) {
      models = models.filter(m => m.isDownloaded);
    }
    if (criteria.availableOnly) {
      models = models.filter(m => m.isAvailable);
    }

    return models;
  }

  /**
   * Register a model (native)
   */
  async registerModel(model: ModelInfo): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule();
    await native.updateModel(model.id, JSON.stringify(model));
  }

  /**
   * Update model info (native)
   */
  async updateModel(model: ModelInfo): Promise<void> {
    return this.registerModel(model);
  }

  /**
   * Remove a model (native)
   */
  async removeModel(id: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule();
    await native.removeModel(id);
  }

  /**
   * Add model from URL (native)
   */
  async addModelFromURL(options: AddModelFromURLOptions): Promise<ModelInfo> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const json = await native.addModelFromURL(options.url, JSON.stringify(options));
    return JSON.parse(json);
  }

  /**
   * Get downloaded models
   */
  async getDownloadedModels(): Promise<ModelInfo[]> {
    return this.filterModels({ downloadedOnly: true });
  }

  /**
   * Get available models
   */
  async getAvailableModels(): Promise<ModelInfo[]> {
    return this.filterModels({ availableOnly: true });
  }

  /**
   * Get models by framework
   */
  async getModelsByFramework(framework: LLMFramework): Promise<ModelInfo[]> {
    return this.filterModels({ framework });
  }

  /**
   * Get models by category
   */
  async getModelsByCategory(category: ModelCategory): Promise<ModelInfo[]> {
    return this.filterModels({ category });
  }

  /**
   * Check if model is downloaded
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    const model = await this.getModel(modelId);
    return model?.isDownloaded ?? false;
  }

  /**
   * Check if model is available
   */
  async isModelAvailable(modelId: string): Promise<boolean> {
    const model = await this.getModel(modelId);
    return model?.isAvailable ?? false;
  }

  /**
   * Check if initialized
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Reset (for testing)
   */
  reset(): void {
    this.initialized = false;
  }
}

/**
 * Singleton instance
 */
export const ModelRegistry = new ModelRegistryImpl();
