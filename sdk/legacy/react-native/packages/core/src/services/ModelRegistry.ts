/**
 * Model Registry for RunAnywhere React Native SDK
 *
 * Thin wrapper over native model registry.
 * All logic (caching, filtering, discovery) is in native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift
 */

import { requireNativeModule, requireDeviceInfoModule, isNativeModuleAvailable } from '../native';
import type { LLMFramework, ModelCategory, ModelInfo, ModelCompatibilityResult } from '../types';
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
 * Model Registry - Wrapper over native model registry with local cache fallback.
 *
 * Primary source of truth is native commons. A JS-side cache ensures models
 * registered via registerModel() are always available even if the native
 * getAvailableModels() call fails (e.g. timing issues during init).
 */
class ModelRegistryImpl {
  private initialized = false;
  private localCache = new Map<string, ModelInfo>();

  /**
   * Initialize the registry (calls native)
   */
  async initialize(): Promise<void> {
    if (this.initialized) return;

    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available, using local cache only');
      this.initialized = true;
      return;
    }

    try {
      await this.getAllModels();
      this.initialized = true;
      logger.info('Model registry initialized via native');
    } catch (error) {
      logger.warning('Failed to initialize registry, using local cache:', { error });
      this.initialized = true;
    }
  }

  /**
   * Get all models — tries native first, falls back to local cache
   */
  async getAllModels(): Promise<ModelInfo[]> {
    if (!isNativeModuleAvailable()) {
      return Array.from(this.localCache.values());
    }

    try {
      const native = requireNativeModule();
      const json = await native.getAvailableModels();
      const nativeModels: ModelInfo[] = JSON.parse(json);

      if (nativeModels.length > 0) {
        return nativeModels;
      }

      // Native returned empty — merge with local cache (models may not have synced yet)
      if (this.localCache.size > 0) {
        logger.debug(`Native returned 0 models, using ${this.localCache.size} from local cache`);
        return Array.from(this.localCache.values());
      }

      return [];
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`Native getAvailableModels failed (${msg}), using local cache (${this.localCache.size} models)`);
      return Array.from(this.localCache.values());
    }
  }

  /**
   * Get a model by ID — tries native first, falls back to local cache
   */
  async getModel(id: string): Promise<ModelInfo | null> {
    if (!isNativeModuleAvailable()) {
      return this.localCache.get(id) ?? null;
    }

    try {
      const native = requireNativeModule();
      const json = await native.getModelInfo(id);
      if (!json || json === '{}') {
        return this.localCache.get(id) ?? null;
      }
      return JSON.parse(json);
    } catch (error) {
      logger.debug(`Failed to get model info from native for ${id}, checking cache`);
      return this.localCache.get(id) ?? null;
    }
  }

  /**
   * Filter models by criteria
   */
  async filterModels(criteria: ModelCriteria): Promise<ModelInfo[]> {
    const allModels = await this.getAllModels();

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
   * Register a model — saves to both native and local cache
   */
  async registerModel(model: ModelInfo): Promise<void> {
    this.localCache.set(model.id, model);

    if (!isNativeModuleAvailable()) return;

    try {
      const native = requireNativeModule();
      await native.registerModel(JSON.stringify(model));
    } catch (error) {
      logger.debug(`Native registerModel failed for ${model.id}, model is in local cache`);
    }
  }

  /**
   * Update model info (alias for registerModel)
   */
  async updateModel(model: ModelInfo): Promise<void> {
    return this.registerModel(model);
  }

  /**
   * Remove a model (native + cache)
   */
  async removeModel(id: string): Promise<void> {
    this.localCache.delete(id);

    if (!isNativeModuleAvailable()) return;

    try {
      const native = requireNativeModule();
      await native.deleteModel(id);
    } catch (error) {
      logger.debug(`Native deleteModel failed for ${id}`);
    }
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
   * Check if model is downloaded (native, falls back to cache)
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return this.localCache.get(modelId)?.isDownloaded ?? false;
    }

    try {
      const native = requireNativeModule();
      return native.isModelDownloaded(modelId);
    } catch {
      return this.localCache.get(modelId)?.isDownloaded ?? false;
    }
  }

  /**
   * Check if a model is compatible with the current device
   * Checks RAM and storage requirements against device capabilities
   * All logic runs in native C++ (runanywhere-commons)
   */
  async checkCompatibility(modelId: string): Promise<ModelCompatibilityResult> {
    const defaultResult: ModelCompatibilityResult = {
      isCompatible: false,
      canRun: false,
      canFit: false,
      requiredMemory: 0,
      availableMemory: 0,
      requiredStorage: 0,
      availableStorage: 0,
    };

    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available for compatibility check');
      return defaultResult;
    }

    try {
      const native = requireNativeModule();
      const json = await native.checkCompatibility(modelId);
      const result = JSON.parse(json);

      // Convert string booleans to actual booleans if needed
      return {
        isCompatible: result.isCompatible === true || result.isCompatible === 'true',
        canRun: result.canRun === true || result.canRun === 'true',
        canFit: result.canFit === true || result.canFit === 'true',
        requiredMemory: Number(result.requiredMemory),
        availableMemory: Number(result.availableMemory),
        requiredStorage: Number(result.requiredStorage),
        availableStorage: Number(result.availableStorage),
      };
    } catch (error) {
      logger.error('Failed to check model compatibility:', { error });
      return defaultResult;
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
   * Update a cached model's info (e.g. after download completes)
   */
  updateCachedModel(modelId: string, updates: Partial<ModelInfo>): void {
    const existing = this.localCache.get(modelId);
    if (existing) {
      this.localCache.set(modelId, { ...existing, ...updates });
    }
  }

  /**
   * Reset (for testing)
   */
  reset(): void {
    this.initialized = false;
    this.localCache.clear();
  }
}

/**
 * Singleton instance
 */
export const ModelRegistry = new ModelRegistryImpl();
