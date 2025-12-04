/**
 * AllocationManager.ts
 *
 * Manages memory allocation and model registration
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Memory/Services/AllocationManager.swift
 */

import type {
  MemoryLoadedModel,
  MemoryLoadedModelInfo,
} from '../../../Core/Protocols/Memory/MemoryModels';
import { MemoryPriority } from '../../../Core/Protocols/Memory/MemoryModels';
import type { LLMService } from '../../../Core/Protocols/LLM/LLMService';

/**
 * Manages memory allocation and model registration
 */
export class AllocationManager {
  private loadedModels: Map<string, MemoryLoadedModelInfo> = new Map();
  private pressureCallback: (() => void) | null = null;

  /**
   * Set pressure callback
   */
  public setPressureCallback(callback: () => void): void {
    this.pressureCallback = callback;
  }

  /**
   * Register a model
   */
  public registerModel(
    model: MemoryLoadedModel,
    size: number,
    service: LLMService,
    priority: MemoryPriority = MemoryPriority.Normal
  ): void {
    const modelInfo: MemoryLoadedModelInfo = {
      model,
      size,
      lastUsed: new Date(),
      service,
      priority,
    };

    this.loadedModels.set(model.id, modelInfo);

    // Call pressure callback if set
    if (this.pressureCallback) {
      this.pressureCallback();
    }
  }

  /**
   * Unregister a model
   */
  public unregisterModel(modelId: string): void {
    this.loadedModels.delete(modelId);
  }

  /**
   * Touch a model (update last used time)
   */
  public touchModel(modelId: string): void {
    const modelInfo = this.loadedModels.get(modelId);
    if (modelInfo) {
      this.loadedModels.set(modelId, {
        ...modelInfo,
        lastUsed: new Date(),
      });
    }
  }

  /**
   * Request memory
   */
  public async requestMemory(
    size: number,
    priority: MemoryPriority = MemoryPriority.Normal
  ): Promise<boolean> {
    const availableMemory = this.getCurrentAvailableMemory();

    if (availableMemory >= size) {
      return true;
    }

    // Try to free memory based on priority
    const needed = size - availableMemory;
    const freed = await this.freeMemory(needed, priority);

    const newAvailable = this.getCurrentAvailableMemory();
    return newAvailable >= size;
  }

  /**
   * Release memory
   */
  public async releaseMemory(size: number): Promise<void> {
    // Memory is automatically released when models are unloaded
    // This tracks explicit memory releases for accounting
  }

  /**
   * Get total model memory
   */
  public getTotalModelMemory(): number {
    let total = 0;
    for (const modelInfo of this.loadedModels.values()) {
      total += modelInfo.size;
    }
    return total;
  }

  /**
   * Get loaded model count
   */
  public getLoadedModelCount(): number {
    return this.loadedModels.size;
  }

  /**
   * Get loaded models
   */
  public getLoadedModels(): MemoryLoadedModelInfo[] {
    return Array.from(this.loadedModels.values());
  }

  /**
   * Check if model is loaded
   */
  public isModelLoaded(modelId: string): boolean {
    return this.loadedModels.has(modelId);
  }

  /**
   * Get model memory usage
   */
  public getModelMemoryUsage(modelId: string): number | null {
    const modelInfo = this.loadedModels.get(modelId);
    return modelInfo ? modelInfo.size : null;
  }

  /**
   * Get models for eviction
   */
  public getModelsForEviction(): MemoryLoadedModelInfo[] {
    return Array.from(this.loadedModels.values());
  }

  /**
   * Unload a model
   */
  public async unloadModel(modelId: string): Promise<number> {
    const modelInfo = this.loadedModels.get(modelId);
    if (!modelInfo) {
      return 0;
    }

    const size = modelInfo.size;
    this.loadedModels.delete(modelId);

    // Notify service to cleanup
    if (modelInfo.service && typeof modelInfo.service.cleanup === 'function') {
      await modelInfo.service.cleanup();
    }

    return size;
  }

  /**
   * Unload multiple models
   */
  public async unloadModels(modelIds: string[]): Promise<number> {
    let totalFreed = 0;
    for (const modelId of modelIds) {
      totalFreed += await this.unloadModel(modelId);
    }
    return totalFreed;
  }

  /**
   * Get current available memory
   */
  private getCurrentAvailableMemory(): number {
    // In React Native, this would need native module support
    // For now, return a placeholder
    return 2_000_000_000; // 2GB default
  }

  /**
   * Free memory
   */
  private async freeMemory(
    needed: number,
    requesterPriority: MemoryPriority
  ): Promise<number> {
    const models = Array.from(this.loadedModels.values());

    // Sort models by eviction priority
    const sortedModels = models.sort((lhs, rhs) => {
      // Higher priority models are less likely to be evicted
      if (lhs.priority !== rhs.priority) {
        return lhs.priority - rhs.priority;
      }
      // If same priority, evict least recently used first
      return lhs.lastUsed.getTime() - rhs.lastUsed.getTime();
    });

    let freedMemory = 0;
    const modelsToUnload: string[] = [];

    for (const model of sortedModels) {
      // Don't evict models with higher or equal priority unless absolutely necessary
      if (
        model.priority >= requesterPriority &&
        freedMemory > 0
      ) {
        continue;
      }

      modelsToUnload.push(model.model.id);
      freedMemory += model.size;

      if (freedMemory >= needed) {
        break;
      }
    }

    // Unload selected models
    const actualFreed = await this.unloadModels(modelsToUnload);
    return actualFreed;
  }
}

