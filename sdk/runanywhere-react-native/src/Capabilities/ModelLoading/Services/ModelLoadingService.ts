/**
 * ModelLoadingService.ts
 *
 * Service for loading and unloading models
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/ModelLoading/Services/ModelLoadingService.swift
 */

import type { LoadedModel } from '../Models/LoadedModel';
import type { MemoryManager } from '../../../Core/Protocols/Memory/MemoryManager';
import type { ModelRegistry } from '../../../Core/Protocols/Registry/ModelRegistry';
import type { AdapterRegistry } from '../../../Foundation/DependencyInjection/AdapterRegistry';
import type { LLMService } from '../../../Core/Protocols/LLM/LLMService';
import { FrameworkModality } from '../../../Core/Models/Framework/FrameworkModality';
import { LLMFramework } from '../../../types';

/**
 * Type guard to check if a service is an LLMService
 */
function isLLMService(service: unknown): service is LLMService {
  return (
    service !== null &&
    typeof service === 'object' &&
    'generate' in service &&
    typeof (service as LLMService).generate === 'function'
  );
}

/**
 * Service for loading and unloading models
 */
export class ModelLoadingService {
  private loadedModels: Map<string, LoadedModel> = new Map();
  private inflightLoads: Map<string, Promise<LoadedModel>> = new Map();
  private registry: ModelRegistry;
  private memoryService: MemoryManager;
  private adapterRegistry: AdapterRegistry | undefined;

  constructor(
    registry: ModelRegistry,
    memoryService: MemoryManager,
    adapterRegistry?: AdapterRegistry
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
    const existingLoaded = this.loadedModels.get(modelId);
    if (existingLoaded) {
      return existingLoaded;
    }

    // Check if a load is already in progress
    const existingLoad = this.inflightLoads.get(modelId);
    if (existingLoad) {
      return await existingLoad;
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
    const existingLoaded = this.loadedModels.get(modelId);
    if (existingLoaded) {
      return existingLoaded;
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
      const _isPrimary = index === 0;

      try {
        const service = await adapter.loadModel(modelInfo, modality);

        // Validate it's an LLMService (by construction: text-to-text modality)
        if (!isLLMService(service)) {
          throw new Error(
            `Adapter '${adapter.framework}' did not return an LLMService for text-to-text modality`
          );
        }

        // Create loaded model
        const loaded: LoadedModel = {
          model: modelInfo,
          service,
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
    throw (
      lastError ?? new Error('Failed to load model with any available adapter')
    );
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
