/**
 * RegistryService.ts
 *
 * Implementation of model registry
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Registry/Services/RegistryService.swift
 */

import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';
import type { ModelRegistry } from '../../../Core/Protocols/Registry/ModelRegistry';
import type { ModelCriteria } from '../../../Core/Protocols/Registry/ModelRegistry';

/**
 * Implementation of model registry
 */
export class RegistryService implements ModelRegistry {
  private models: Map<string, ModelInfo> = new Map();
  private modelsByProvider: Map<string, ModelInfo[]> = new Map();
  private modelDiscovery: any; // ModelDiscovery

  constructor() {
    // Initialize model discovery
    // this.modelDiscovery = new ModelDiscovery();
  }

  /**
   * Initialize registry with configuration
   */
  public async initialize(_apiKey: string): Promise<void> {
    // Load pre-configured models
    await this.loadPreconfiguredModels();

    // Discover local models that are already downloaded
    const localModels =
      (await this.modelDiscovery?.discoverLocalModels()) ?? [];

    // Update existing registered models with discovered local paths
    for (const discoveredModel of localModels) {
      const existingModel = this.getModel(discoveredModel.id);
      if (existingModel) {
        // Model already registered - just update its localPath if needed
        if (!existingModel.localPath && discoveredModel.localPath) {
          const updatedModel = {
            ...existingModel,
            localPath: discoveredModel.localPath,
          };
          this.updateModel(updatedModel);
        }
      } else {
        // New model found on disk - register it
        this.registerModel(discoveredModel);
      }
    }
  }

  /**
   * Discover available models
   */
  public async discoverModels(): Promise<ModelInfo[]> {
    // Simply return all registered models
    return Array.from(this.models.values());
  }

  /**
   * Register a model
   */
  public registerModel(model: ModelInfo): void {
    // Validate model before registering
    if (!model.id || model.id.length === 0) {
      return;
    }

    this.models.set(model.id, model);
  }

  /**
   * Register model and save to database for persistence
   */
  public async registerModelPersistently(model: ModelInfo): Promise<void> {
    // Validate model before registering
    if (!model.id || model.id.length === 0) {
      return;
    }

    // Register the model in memory
    this.registerModel(model);

    // Save to database (would use ModelInfoService)
    // const modelInfoService = await ServiceContainer.shared.modelInfoService;
    // try {
    //   await modelInfoService.saveModel(model);
    // } catch (error) {
    //   // Model is still registered in memory even if database save fails
    // }
  }

  /**
   * Get model by ID
   */
  public getModel(id: string): ModelInfo | null {
    return this.models.get(id) ?? null;
  }

  /**
   * Filter models by criteria
   */
  public filterModels(criteria: ModelCriteria): ModelInfo[] {
    return Array.from(this.models.values()).filter((model) => {
      // Framework filter
      if (criteria.framework) {
        if (!model.compatibleFrameworks.includes(criteria.framework)) {
          return false;
        }
      }

      // Format filter
      if (criteria.format) {
        if (model.format !== criteria.format) {
          return false;
        }
      }

      // Category filter
      if (criteria.category) {
        if (model.category !== criteria.category) {
          return false;
        }
      }

      // Available filter
      if (criteria.available !== undefined) {
        if (model.isAvailable !== criteria.available) {
          return false;
        }
      }

      return true;
    });
  }

  /**
   * Update model information
   */
  public updateModel(model: ModelInfo): void {
    this.models.set(model.id, model);
  }

  /**
   * Remove a model
   */
  public removeModel(id: string): void {
    this.models.delete(id);
  }

  /**
   * Load preconfigured models
   */
  private async loadPreconfiguredModels(): Promise<void> {
    // Load models from configuration (remote or cached)
    // This would integrate with ConfigurationService
    // For now, placeholder
  }
}
