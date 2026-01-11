/**
 * Model Registry for RunAnywhere React Native SDK
 *
 * Thin wrapper over native model registry.
 * All logic (caching, filtering, discovery) is in native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../native';
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
      // Just get available models to verify registry is working
      await this.getAllModels();
      this.initialized = true;
      logger.info('Model registry initialized via native');
    } catch (error) {
      logger.warning('Failed to initialize registry:', { error });
      this.initialized = true;
    }
  }

  /**
   * Get all models (native)
   */
  async getAllModels(): Promise<ModelInfo[]> {
    if (!isNativeModuleAvailable()) return [];

    try {
      const native = requireNativeModule();
      const json = await native.getAvailableModels();
      return JSON.parse(json);
    } catch (error) {
      logger.error('Failed to get available models:', { error });
      return [];
    }
  }

  /**
   * Get a model by ID (native)
   */
  async getModel(id: string): Promise<ModelInfo | null> {
    if (!isNativeModuleAvailable()) return null;

    try {
      const native = requireNativeModule();
      const json = await native.getModelInfo(id);
      if (!json || json === '{}') return null;
      return JSON.parse(json);
    } catch (error) {
      logger.error('Failed to get model info:', { error });
      return null;
    }
  }

  /**
   * Filter models by criteria
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
    await native.registerModel(JSON.stringify(model));
  }

  /**
   * Update model info (alias for registerModel)
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
    await native.deleteModel(id);
  }

  /**
   * Add model from URL - registers a model with a download URL
   */
  async addModelFromURL(options: AddModelFromURLOptions): Promise<ModelInfo> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    // Create a ModelInfo from the options and register it
    const model: Partial<ModelInfo> = {
      id: options.name.toLowerCase().replace(/\s+/g, '-'),
      name: options.name,
      downloadURL: options.url,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      compatibleFrameworks: [options.framework] as any,
      downloadSize: options.estimatedSize ?? 0,
      supportsThinking: options.supportsThinking ?? false,
      isDownloaded: false,
      isAvailable: true,
    };

    await this.registerModel(model as ModelInfo);
    return model as ModelInfo;
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
   * Check if model is downloaded (native)
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;

    try {
      const native = requireNativeModule();
      return native.isModelDownloaded(modelId);
    } catch {
      return false;
    }
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
