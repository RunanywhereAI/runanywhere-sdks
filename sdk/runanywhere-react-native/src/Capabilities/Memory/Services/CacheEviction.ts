/**
 * CacheEviction.ts
 *
 * Manages cache eviction strategies and model selection for memory cleanup
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Memory/Services/CacheEviction.swift
 */

import type {
  MemoryLoadedModelInfo,
  MemoryPriority,
  EvictionStatistics,
} from '../../../Core/Protocols/Memory/MemoryModels';
import type { AllocationManager } from './AllocationManager';

/**
 * Manages cache eviction strategies and model selection for memory cleanup
 */
export class CacheEviction {
  private allocationManager: AllocationManager | null = null;

  /**
   * Set allocation manager
   */
  public setAllocationManager(manager: AllocationManager): void {
    this.allocationManager = manager;
  }

  /**
   * Select models to evict
   */
  public selectModelsToEvict(targetMemory: number): string[] {
    const models = this.getCurrentModels();
    return this.selectModelsUsingStrategy(
      models,
      targetMemory,
      false
    );
  }

  /**
   * Select models for critical eviction
   */
  public selectModelsForCriticalEviction(targetMemory: number): string[] {
    const models = this.getCurrentModels();
    return this.selectModelsUsingStrategy(models, targetMemory, true);
  }

  /**
   * Select models to evict by count
   */
  public selectModelsToEvict(count: number): string[] {
    const models = this.getCurrentModels();
    const sortedModels = this.sortModelsByEvictionPriority(models, false);
    return sortedModels.slice(0, count).map((m) => m.model.id);
  }

  /**
   * Select least important models
   */
  public selectLeastImportantModels(maxCount: number): string[] {
    const models = this.getCurrentModels();
    const sortedModels = this.sortModelsByImportance(models);
    return sortedModels.slice(0, maxCount).map((m) => m.model.id);
  }

  /**
   * Select models using strategy
   */
  private selectModelsUsingStrategy(
    models: MemoryLoadedModelInfo[],
    targetMemory: number,
    aggressive: boolean
  ): string[] {
    // Default to least recently used strategy
    return this.selectByLeastRecentlyUsed(
      models,
      targetMemory,
      aggressive
    );
  }

  /**
   * Select by least recently used
   */
  private selectByLeastRecentlyUsed(
    models: MemoryLoadedModelInfo[],
    targetMemory: number,
    aggressive: boolean
  ): string[] {
    const sortedModels = models.sort(
      (a, b) => a.lastUsed.getTime() - b.lastUsed.getTime()
    );
    return this.selectModelsToTarget(sortedModels, targetMemory, aggressive);
  }

  /**
   * Select models to target
   */
  private selectModelsToTarget(
    sortedModels: MemoryLoadedModelInfo[],
    targetMemory: number,
    aggressive: boolean
  ): string[] {
    const modelsToEvict: string[] = [];
    let freedMemory = 0;

    for (const model of sortedModels) {
      // In non-aggressive mode, skip critical priority models unless absolutely necessary
      if (
        !aggressive &&
        model.priority === MemoryPriority.Critical &&
        freedMemory > 0
      ) {
        continue;
      }

      modelsToEvict.push(model.model.id);
      freedMemory += model.size;

      if (freedMemory >= targetMemory) {
        break;
      }
    }

    return modelsToEvict;
  }

  /**
   * Sort models by eviction priority
   */
  private sortModelsByEvictionPriority(
    models: MemoryLoadedModelInfo[],
    aggressive: boolean
  ): MemoryLoadedModelInfo[] {
    return models.sort((lhs, rhs) => {
      // In aggressive mode, ignore critical priority
      if (!aggressive) {
        if (lhs.priority !== rhs.priority) {
          return lhs.priority - rhs.priority;
        }
      }

      // Consider both recency and size
      const lhsScore = this.calculateEvictionScore(lhs);
      const rhsScore = this.calculateEvictionScore(rhs);

      return lhsScore - rhsScore; // Lower score = higher eviction priority
    });
  }

  /**
   * Sort models by importance
   */
  private sortModelsByImportance(
    models: MemoryLoadedModelInfo[]
  ): MemoryLoadedModelInfo[] {
    return models.sort((lhs, rhs) => {
      // Higher priority = more important (lower eviction priority)
      if (lhs.priority !== rhs.priority) {
        return lhs.priority - rhs.priority;
      }

      // More recently used = more important
      return lhs.lastUsed.getTime() - rhs.lastUsed.getTime();
    });
  }

  /**
   * Calculate eviction score
   */
  private calculateEvictionScore(model: MemoryLoadedModelInfo): number {
    const timeSinceUse =
      (Date.now() - model.lastUsed.getTime()) / 1000; // seconds
    const priorityWeight = model.priority * 1000; // Higher priority = higher score
    const recencyScore = timeSinceUse / 3600; // Hours since last use

    // Lower score = higher eviction priority
    return priorityWeight - recencyScore;
  }

  /**
   * Get eviction candidates
   */
  public getEvictionCandidates(minMemory: number): MemoryLoadedModelInfo[] {
    const models = this.getCurrentModels();
    return models.filter((m) => m.size >= minMemory);
  }

  /**
   * Get models by priority
   */
  public getModelsByPriority(
    priority: MemoryPriority
  ): MemoryLoadedModelInfo[] {
    const models = this.getCurrentModels();
    return models.filter((m) => m.priority === priority);
  }

  /**
   * Get models by usage age
   */
  public getModelsByUsageAge(olderThan: number): MemoryLoadedModelInfo[] {
    const models = this.getCurrentModels();
    const cutoffDate = new Date(Date.now() - olderThan * 1000);
    return models.filter((m) => m.lastUsed < cutoffDate);
  }

  /**
   * Get eviction statistics
   */
  public getEvictionStatistics(): EvictionStatistics {
    const models = this.getCurrentModels();

    const totalMemory = models.reduce((sum, m) => sum + m.size, 0);
    const modelsByPriority: { [key: number]: number } = {};
    for (const model of models) {
      modelsByPriority[model.priority] =
        (modelsByPriority[model.priority] || 0) + 1;
    }

    const avgLastUsed =
      models.length > 0
        ? new Date(
            models.reduce(
              (sum, m) => sum + m.lastUsed.getTime(),
              0
            ) / models.length
          )
        : new Date();

    const oldestModel =
      models.length > 0
        ? new Date(
            Math.min(...models.map((m) => m.lastUsed.getTime()))
          )
        : new Date();

    const largestModel =
      models.length > 0
        ? Math.max(...models.map((m) => m.size))
        : 0;

    return {
      totalModels: models.length,
      totalMemory,
      modelsByPriority,
      averageLastUsed: avgLastUsed,
      oldestModel,
      largestModel,
      totalMemoryString: this.formatBytes(totalMemory),
      largestModelString: this.formatBytes(largestModel),
    };
  }

  /**
   * Get current models
   */
  private getCurrentModels(): MemoryLoadedModelInfo[] {
    return this.allocationManager?.getLoadedModels() ?? [];
  }

  /**
   * Format bytes to human-readable string
   */
  private formatBytes(bytes: number): string {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(2)} ${units[unitIndex]}`;
  }
}

