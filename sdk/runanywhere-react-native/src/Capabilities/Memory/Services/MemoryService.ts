/**
 * MemoryService.ts
 *
 * Central memory management service
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Memory/Services/MemoryService.swift
 */

import type {
  MemoryLoadedModel,
  MemoryPriority,
  MemoryPressureLevel,
  MemoryStatistics,
  MemoryLoadedModelInfo,
} from '../../../Core/Protocols/Memory/MemoryModels';
import type { MemoryManager } from '../../../Core/Protocols/Memory/MemoryManager';
import type { LoadedModel } from '../../ModelLoading/Models/LoadedModel';
import type { LLMService } from '../../../Core/Protocols/LLM/LLMService';
import { AllocationManager } from './AllocationManager';
import { PressureHandler } from './PressureHandler';
import { CacheEviction } from './CacheEviction';
import { MemoryMonitor } from './MemoryMonitor';
import { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';

/**
 * Central memory management service
 */
export class MemoryService implements MemoryManager {
  private allocationManager: AllocationManager;
  private pressureHandler: PressureHandler;
  private cacheEviction: CacheEviction;
  private memoryMonitor: MemoryMonitor;
  private memoryThreshold: number = 500_000_000; // 500MB
  private criticalThreshold: number = 200_000_000; // 200MB

  constructor(
    allocationManager?: AllocationManager,
    pressureHandler?: PressureHandler,
    cacheEviction?: CacheEviction,
    memoryMonitor?: MemoryMonitor
  ) {
    this.allocationManager =
      allocationManager ?? new AllocationManager();
    this.pressureHandler = pressureHandler ?? new PressureHandler();
    this.cacheEviction = cacheEviction ?? new CacheEviction();
    this.memoryMonitor = memoryMonitor ?? new MemoryMonitor();

    this.setupIntegration();
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
    this.allocationManager.registerModel(model, size, service, priority);

    // Check for memory pressure after registration
    this.checkMemoryConditions();
  }

  /**
   * Unregister a model
   */
  public unregisterModel(modelId: string): void {
    this.allocationManager.unregisterModel(modelId);
  }

  /**
   * Touch a model
   */
  public touchModel(modelId: string): void {
    this.allocationManager.touchModel(modelId);
  }

  /**
   * Handle memory pressure
   */
  public async handleMemoryPressure(
    level: MemoryPressureLevel = MemoryPressureLevel.Warning
  ): Promise<void> {
    const targetMemory = this.calculateTargetMemory(level);
    const modelsToEvict =
      this.cacheEviction.selectModelsToEvict(targetMemory);

    await this.pressureHandler.handlePressure(level, modelsToEvict);
  }

  /**
   * Request memory
   */
  public async requestMemory(
    size: number,
    priority: MemoryPriority = MemoryPriority.Normal
  ): Promise<boolean> {
    return await this.allocationManager.requestMemory(size, priority);
  }

  /**
   * Release memory
   */
  public async releaseMemory(size: number): Promise<void> {
    await this.allocationManager.releaseMemory(size);
  }

  /**
   * Register loaded model (MemoryManager protocol)
   */
  public registerLoadedModel(
    model: LoadedModel,
    size: number,
    service: LLMService
  ): void {
    const framework =
      model.model.preferredFramework ?? LLMFramework.CoreML;
    const memoryModel: MemoryLoadedModel = {
      id: model.model.id,
      name: model.model.name,
      size,
      framework,
      loadedAt: new Date(),
      lastUsed: new Date(),
      priority: MemoryPriority.Normal,
    };
    this.registerModel(memoryModel, size, service);
  }

  /**
   * Get current memory usage
   */
  public getCurrentMemoryUsage(): number {
    return this.allocationManager.getTotalModelMemory();
  }

  /**
   * Get available memory
   */
  public getAvailableMemory(): number {
    return this.memoryMonitor.getAvailableMemory();
  }

  /**
   * Check if enough memory is available
   */
  public hasAvailableMemory(for size: number): boolean {
    return this.getAvailableMemory() >= size;
  }

  /**
   * Check if memory can be allocated
   */
  public async canAllocate(size: number): Promise<boolean> {
    return await this.requestMemory(size);
  }

  /**
   * Handle memory pressure (MemoryManager protocol)
   */
  public async handleMemoryPressure(): Promise<void> {
    await this.handleMemoryPressure(MemoryPressureLevel.Warning);
  }

  /**
   * Set memory threshold
   */
  public setMemoryThreshold(threshold: number): void {
    this.memoryThreshold = threshold;
  }

  /**
   * Get loaded models (MemoryManager protocol)
   */
  public getLoadedModels(): LoadedModel[] {
    const memoryModels = this.allocationManager.getLoadedModels();
    return memoryModels
      .map((memModelInfo) => {
        const service = memModelInfo.service;
        if (!service) {
          return null;
        }

        // Create a ModelInfo from the MemoryLoadedModel
        // This is a simplified version - in production, we'd need to reconstruct ModelInfo
        // For now, return null as we don't have full ModelInfo reconstruction
        return null;
      })
      .filter((model): model is LoadedModel => model !== null);
  }

  /**
   * Check if service is healthy
   */
  public isHealthy(): boolean {
    return this.memoryMonitor.getAvailableMemory() > 0;
  }

  /**
   * Get memory statistics
   */
  public getMemoryStatistics(): MemoryStatistics {
    const totalMemory = this.memoryMonitor.getTotalMemory();
    const availableMemory = this.memoryMonitor.getAvailableMemory();
    const modelMemory = this.allocationManager.getTotalModelMemory();
    const loadedModelCount = this.allocationManager.getLoadedModelCount();
    const memoryPressure = availableMemory < this.memoryThreshold;

    return {
      totalMemory,
      availableMemory,
      modelMemory,
      loadedModelCount,
      memoryPressure,
      usedMemoryPercentage:
        ((totalMemory - availableMemory) / totalMemory) * 100,
      modelMemoryPercentage: (modelMemory / totalMemory) * 100,
    };
  }

  /**
   * Check if model is loaded
   */
  public isModelLoaded(modelId: string): boolean {
    return this.allocationManager.isModelLoaded(modelId);
  }

  /**
   * Get model memory usage
   */
  public getModelMemoryUsage(modelId: string): number | null {
    return this.allocationManager.getModelMemoryUsage(modelId);
  }

  /**
   * Get loaded models (internal)
   */
  public getLoadedModelsInternal(): MemoryLoadedModelInfo[] {
    return this.allocationManager.getLoadedModels();
  }

  /**
   * Setup integration
   */
  private setupIntegration(): void {
    // Connect cache eviction with allocation manager
    this.cacheEviction.setAllocationManager(this.allocationManager);

    // Connect pressure handler with cache eviction
    this.pressureHandler.setEvictionHandler(this.cacheEviction);

    // Connect allocation manager with pressure monitoring
    this.allocationManager.setPressureCallback(() => {
      this.checkMemoryConditions();
    });
  }

  /**
   * Check memory conditions
   */
  private async checkMemoryConditions(): Promise<void> {
    const availableMemory = this.memoryMonitor.getAvailableMemory();

    if (availableMemory < this.criticalThreshold) {
      await this.handleMemoryPressure(MemoryPressureLevel.Critical);
    } else if (availableMemory < this.memoryThreshold) {
      await this.handleMemoryPressure(MemoryPressureLevel.Warning);
    }
  }

  /**
   * Calculate target memory
   */
  private calculateTargetMemory(level: MemoryPressureLevel): number {
    switch (level) {
      case MemoryPressureLevel.Low:
      case MemoryPressureLevel.Medium:
        return this.memoryThreshold;
      case MemoryPressureLevel.High:
        return Math.floor(this.memoryThreshold * 1.5);
      case MemoryPressureLevel.Warning:
        return this.memoryThreshold;
      case MemoryPressureLevel.Critical:
        return this.memoryThreshold * 2;
    }
  }
}

