/**
 * PressureHandler.ts
 *
 * Handles memory pressure situations and coordinates response actions
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Memory/Services/PressureHandler.swift
 */

import { MemoryPressureLevel } from '../../../Core/Protocols/Memory/MemoryModels';
import type { CacheEviction } from './CacheEviction';

/**
 * Handles memory pressure situations and coordinates response actions
 */
export class PressureHandler {
  private evictionHandler: CacheEviction | null = null;
  private memoryThreshold: number = 500_000_000; // 500MB

  /**
   * Configure memory threshold
   */
  public configure(memoryThreshold: number): void {
    this.memoryThreshold = memoryThreshold;
  }

  /**
   * Set eviction handler
   */
  public setEvictionHandler(handler: CacheEviction): void {
    this.evictionHandler = handler;
  }

  /**
   * Handle pressure
   */
  public async handlePressure(
    level: MemoryPressureLevel,
    modelsToEvict: string[] = []
  ): Promise<number> {
    const startTime = Date.now();
    let totalFreed = 0;

    switch (level) {
      case MemoryPressureLevel.Low:
      case MemoryPressureLevel.Medium:
        // No action needed for low/medium pressure
        totalFreed = 0;
        break;
      case MemoryPressureLevel.High:
      case MemoryPressureLevel.Warning:
        totalFreed = await this.handleWarningPressure(modelsToEvict);
        break;
      case MemoryPressureLevel.Critical:
        totalFreed = await this.handleCriticalPressure(modelsToEvict);
        break;
    }

    const _duration = (Date.now() - startTime) / 1000;

    return totalFreed;
  }

  /**
   * Handle system memory warning
   */
  public async handleSystemMemoryWarning(): Promise<void> {
    await this.handlePressure(MemoryPressureLevel.Critical);
  }

  /**
   * Handle warning pressure
   */
  private async handleWarningPressure(
    modelsToEvict: string[]
  ): Promise<number> {
    let totalFreed = 0;

    // First, try evicting suggested models
    if (modelsToEvict.length > 0) {
      totalFreed += await this.evictModels(modelsToEvict);
    }

    // If that's not enough, use eviction handler to find more candidates
    if (
      totalFreed < this.calculateTargetFreedMemory(MemoryPressureLevel.Warning)
    ) {
      if (!this.evictionHandler) {
        return totalFreed;
      }

      const additionalTarget =
        this.calculateTargetFreedMemory(MemoryPressureLevel.Warning) -
        totalFreed;
      const additionalModels =
        this.evictionHandler.selectModelsToEvict(additionalTarget);
      totalFreed += await this.evictModels(additionalModels);
    }

    return totalFreed;
  }

  /**
   * Handle critical pressure
   */
  private async handleCriticalPressure(
    modelsToEvict: string[]
  ): Promise<number> {
    let totalFreed = 0;

    // In critical situations, be more aggressive
    if (modelsToEvict.length > 0) {
      totalFreed += await this.evictModels(modelsToEvict);
    }

    // Force additional cleanup if needed
    if (
      totalFreed < this.calculateTargetFreedMemory(MemoryPressureLevel.Critical)
    ) {
      if (!this.evictionHandler) {
        return totalFreed;
      }

      // Use more aggressive eviction strategy
      const additionalTarget =
        this.calculateTargetFreedMemory(MemoryPressureLevel.Critical) -
        totalFreed;
      const additionalModels =
        this.evictionHandler.selectModelsForCriticalEviction(additionalTarget);
      totalFreed += await this.evictModels(additionalModels);
    }

    // Force garbage collection
    this.performSystemCleanup();

    return totalFreed;
  }

  /**
   * Evict models
   */
  private async evictModels(modelIds: string[]): Promise<number> {
    if (modelIds.length === 0) {
      return 0;
    }

    // This would normally delegate to the allocation manager
    // For now, return a placeholder value
    return 0;
  }

  /**
   * Perform system cleanup
   */
  private performSystemCleanup(): void {
    // Force garbage collection if available
    if (global.gc) {
      global.gc();
    }
  }

  /**
   * Calculate target freed memory
   */
  private calculateTargetFreedMemory(level: MemoryPressureLevel): number {
    switch (level) {
      case MemoryPressureLevel.Low:
      case MemoryPressureLevel.Medium:
        return 0;
      case MemoryPressureLevel.High:
        return this.memoryThreshold / 2;
      case MemoryPressureLevel.Warning:
        return this.memoryThreshold;
      case MemoryPressureLevel.Critical:
        return this.memoryThreshold * 2;
    }
  }
}
