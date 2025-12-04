/**
 * ModelLoadingService.ts
 *
 * Service for loading and unloading models
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/ModelLoading/Services/ModelLoadingService.swift
 */

import type { LoadedModel } from '../Models/LoadedModel';
import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';
import type { MemoryManager } from '../../../Core/Protocols/Memory/MemoryManager';
import type { ModelRegistry } from '../../../Core/Protocols/Registry/ModelRegistry';
import { FrameworkModality } from '../../../Core/Models/Framework/FrameworkModality';
import { LLMFramework } from '../../../types';

/**
 * Service for loading and unloading models
 */
export class ModelLoadingService {
  private loadedModels: Map<string, LoadedModel> = new Map();
  private inflightLoads: Map<string, Promise<LoadedModel>> = new Map();
  private registry: ModelRegistry;
  private memoryService: MemoryManager;
  private adapterRegistry: any; // AdapterRegistry

  constructor(
    registry: ModelRegistry,
    memoryService: MemoryManager,
    adapterRegistry?: any
  ) {
    this.registry = registry;
    this.memoryService = memoryService;
    this.adapterRegistry = adapterRegistry;
  }

  /**
   * Load a model by identifier
   * Concurrent calls for the same model will be deduplicated
   */
  public async loadModel(modelId: string): Promise<LoadedModel> {
    // Check if already loaded
    if (this.loadedModels.has(modelId)) {
      return this.loadedModels.get(modelId)!;
    }

    // Check if a load is already in progress
    if (this.inflightLoads.has(modelId)) {
      return await this.inflightLoads.get(modelId)!;
    }

    // Create a new loading task
    const loadTask = this.performLoad(modelId);

    // Store the task to prevent duplicate loads
    this.inflightLoads.set(modelId, loadTask);

    try {
      const result = await loadTask;
      return result;
    } finally {
      // Remove from inflight loads
      this.inflightLoads.delete(modelId);
    }
  }

  /**
   * Perform the actual model loading
   */
  private async performLoad(modelId: string): Promise<LoadedModel> {
    // Double-check if already loaded
    if (this.loadedModels.has(modelId)) {
      return this.loadedModels.get(modelId)!;
    }

    // Get model info from registry
    const modelInfo = this.registry.getModel(modelId);
    if (!modelInfo) {
      throw new Error(`Model not found in registry: ${modelId}`);
    }

    // Check if this is a built-in model
    const isBuiltIn = modelInfo.localPath?.startsWith('builtin://') ?? false;

    if (!isBuiltIn) {
      // Check model file exists for non-built-in models
      if (!modelInfo.localPath) {
        throw new Error(`Model '${modelId}' not downloaded`);
      }
    }

    // ModelLoadingService handles LLM models only
    if (
      modelInfo.category === 'speech-recognition' ||
      modelInfo.preferredFramework === LLMFramework.WhisperKit
    ) {
      throw new Error(
        `Model '${modelId}' is a speech recognition model. STT models are loaded automatically through STTComponent.`
      );
    }

    // Check memory availability
    const memoryRequired = modelInfo.memoryRequired ?? 1024 * 1024 * 1024; // Default 1GB
    const canAllocate = await this.memoryService.canAllocate(memoryRequired);
    if (!canAllocate) {
      throw new Error('Insufficient memory');
    }

    // ModelLoadingService handles LLMs only; constrain to text-to-text modality
    const modality = FrameworkModality.TextToText;

    // Get adapters for this modality
    const adapters = this.adapterRegistry?.getAdapters(modality) ?? [];

    if (adapters.length === 0) {
      throw new Error('No adapters available for text-to-text modality');
    }

    // Try each adapter until one succeeds
    let lastError: Error | null = null;
    for (let index = 0; index < adapters.length; index++) {
      const adapter = adapters[index];
      const isPrimary = index === 0;

      try {
        const service = await adapter.loadModel(modelInfo, modality);

        // Cast to LLMService (by construction: text-to-text modality)
        if (!service || typeof service.generate !== 'function') {
          throw new Error(
            `Adapter '${adapter.framework}' did not return an LLMService for text-to-text modality`
          );
        }

        // Create loaded model
        const loaded: LoadedModel = {
          model: modelInfo,
          service: service,
        };

        // Register loaded model
        this.memoryService.registerLoadedModel(
          loaded,
          modelInfo.memoryRequired ?? memoryRequired,
          service
        );

        this.loadedModels.set(modelId, loaded);

        return loaded;
      } catch (err) {
        lastError = err instanceof Error ? err : new Error(String(err));
        // Continue to next adapter
      }
    }

    // All adapters failed
    throw lastError ?? new Error('Failed to load model with any available adapter');
  }

  /**
   * Unload a model
   */
  public async unloadModel(modelId: string): Promise<void> {
    const loaded = this.loadedModels.get(modelId);
    if (!loaded) {
      return;
    }

    // Unload through service
    if (loaded.service && typeof loaded.service.cleanup === 'function') {
      await loaded.service.cleanup();
    }

    // Unregister from memory service
    this.memoryService.unregisterModel(modelId);

    // Remove from loaded models
    this.loadedModels.delete(modelId);
  }

  /**
   * Get currently loaded model
   */
  public getLoadedModel(modelId: string): LoadedModel | null {
    return this.loadedModels.get(modelId) ?? null;
  }
}
