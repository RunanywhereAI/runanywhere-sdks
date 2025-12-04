/**
 * Model Registry for RunAnywhere React Native SDK
 *
 * Manages model discovery, registration, and filtering.
 * The actual registry logic lives in the native SDK.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Registry/Services/RegistryService.swift
 */

import { requireNativeModule } from '../native';
import type { LLMFramework, ModelCategory, ModelFormat, ModelInfo } from '../types';

/**
 * Criteria for filtering models
 */
export interface ModelCriteria {
  /** Filter by compatible framework */
  framework?: LLMFramework;
  /** Filter by model format */
  format?: ModelFormat;
  /** Filter by model category */
  category?: ModelCategory;
  /** Maximum download size in bytes */
  maxSize?: number;
  /** Minimum context length */
  minContextLength?: number;
  /** Maximum context length */
  maxContextLength?: number;
  /** Filter by tags */
  tags?: string[];
  /** Search term for name/description */
  search?: string;
  /** Only show downloaded models */
  downloadedOnly?: boolean;
  /** Only show available models */
  availableOnly?: boolean;
}

/**
 * Options for adding a model from URL
 */
export interface AddModelFromURLOptions {
  /** Display name for the model */
  name: string;
  /** Download URL for the model */
  url: string;
  /** Target framework for the model */
  framework: LLMFramework;
  /** Estimated memory usage in bytes (optional) */
  estimatedSize?: number;
  /** Whether the model supports thinking mode */
  supportsThinking?: boolean;
}

/**
 * Model Registry Service
 *
 * Manages model discovery and registration.
 */
class ModelRegistryImpl {
  private modelsCache: Map<string, ModelInfo> = new Map();
  private initialized: boolean = false;

  /**
   * Initialize the registry
   */
  async initialize(): Promise<void> {
    const native = requireNativeModule();
    await native.initializeRegistry();
    this.initialized = true;

    // Load initial models into cache
    await this.refreshCache();
  }

  /**
   * Discover available models
   *
   * @returns Array of discovered models
   */
  async discoverModels(): Promise<ModelInfo[]> {
    const native = requireNativeModule();
    const modelsJson = await native.discoverModels();
    const models: ModelInfo[] = JSON.parse(modelsJson);

    // Update cache
    for (const model of models) {
      this.modelsCache.set(model.id, model);
    }

    return models;
  }

  /**
   * Register a model
   *
   * @param model - Model information to register
   */
  async registerModel(model: ModelInfo): Promise<void> {
    const native = requireNativeModule();
    await native.registerModel(JSON.stringify(model));
    this.modelsCache.set(model.id, model);
  }

  /**
   * Register and persist a model
   *
   * @param model - Model information to register and persist
   */
  async registerModelPersistently(model: ModelInfo): Promise<void> {
    const native = requireNativeModule();
    await native.registerModelPersistently(JSON.stringify(model));
    this.modelsCache.set(model.id, model);
  }

  /**
   * Get a model by ID
   *
   * @param id - Model identifier
   * @returns Model information or null if not found
   */
  async getModel(id: string): Promise<ModelInfo | null> {
    // Check cache first
    const cached = this.modelsCache.get(id);
    if (cached) {
      return cached;
    }

    // Fetch from native
    const native = requireNativeModule();
    const modelJson = await native.getModel(id);

    if (modelJson) {
      const model: ModelInfo = JSON.parse(modelJson);
      this.modelsCache.set(id, model);
      return model;
    }

    return null;
  }

  /**
   * Filter models by criteria
   *
   * @param criteria - Filter criteria
   * @returns Filtered models
   */
  async filterModels(criteria: ModelCriteria): Promise<ModelInfo[]> {
    const native = requireNativeModule();
    const modelsJson = await native.filterModels(JSON.stringify(criteria));
    return JSON.parse(modelsJson) as ModelInfo[];
  }

  /**
   * Update model information
   *
   * @param model - Updated model information
   */
  async updateModel(model: ModelInfo): Promise<void> {
    const native = requireNativeModule();
    await native.updateModel(model.id, JSON.stringify(model));
    this.modelsCache.set(model.id, model);
  }

  /**
   * Remove a model from the registry
   *
   * @param id - Model identifier
   */
  async removeModel(id: string): Promise<void> {
    const native = requireNativeModule();
    await native.removeModel(id);
    this.modelsCache.delete(id);
  }

  /**
   * Add a model from URL
   *
   * Creates and registers a model from a download URL.
   *
   * @param options - Options for adding the model
   * @returns Created model info
   */
  async addModelFromURL(options: AddModelFromURLOptions): Promise<ModelInfo> {
    const native = requireNativeModule();
    const modelJson = await native.addModelFromURL(options.url, JSON.stringify(options));
    const model: ModelInfo = JSON.parse(modelJson);
    this.modelsCache.set(model.id, model);
    return model;
  }

  /**
   * Get all registered models
   *
   * @returns Array of all registered models
   */
  async getAllModels(): Promise<ModelInfo[]> {
    await this.refreshCache();
    return Array.from(this.modelsCache.values());
  }

  /**
   * Get downloaded models only
   *
   * @returns Array of downloaded models
   */
  async getDownloadedModels(): Promise<ModelInfo[]> {
    return this.filterModels({ downloadedOnly: true });
  }

  /**
   * Get available models (ready to use)
   *
   * @returns Array of available models
   */
  async getAvailableModels(): Promise<ModelInfo[]> {
    return this.filterModels({ availableOnly: true });
  }

  /**
   * Get models by framework
   *
   * @param framework - Target framework
   * @returns Array of compatible models
   */
  async getModelsByFramework(framework: LLMFramework): Promise<ModelInfo[]> {
    return this.filterModels({ framework });
  }

  /**
   * Get models by category
   *
   * @param category - Model category
   * @returns Array of models in category
   */
  async getModelsByCategory(category: ModelCategory): Promise<ModelInfo[]> {
    return this.filterModels({ category });
  }

  /**
   * Search models by name or description
   *
   * @param query - Search query
   * @returns Array of matching models
   */
  async searchModels(query: string): Promise<ModelInfo[]> {
    return this.filterModels({ search: query });
  }

  /**
   * Check if a model is downloaded
   *
   * @param modelId - Model identifier
   * @returns Whether the model is downloaded
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    const model = await this.getModel(modelId);
    return model?.isDownloaded ?? false;
  }

  /**
   * Check if a model is available
   *
   * @param modelId - Model identifier
   * @returns Whether the model is available for use
   */
  async isModelAvailable(modelId: string): Promise<boolean> {
    const model = await this.getModel(modelId);
    return model?.isAvailable ?? false;
  }

  /**
   * Refresh the local cache from native
   */
  private async refreshCache(): Promise<void> {
    try {
      const native = requireNativeModule();
      const modelsJson = await native.availableModels();
      const models: ModelInfo[] = JSON.parse(modelsJson);

      this.modelsCache.clear();
      for (const model of models) {
        this.modelsCache.set(model.id, model);
      }
    } catch {
      // Cache refresh failed, but that's okay
    }
  }

  /**
   * Clear the cache
   */
  clearCache(): void {
    this.modelsCache.clear();
  }

  /**
   * Check if registry is initialized
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Reset the registry
   */
  reset(): void {
    this.modelsCache.clear();
    this.initialized = false;
  }
}

/**
 * Singleton instance of the Model Registry
 */
export const ModelRegistry = new ModelRegistryImpl();

export default ModelRegistry;
