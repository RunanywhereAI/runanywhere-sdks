/**
 * MemoryMonitor.ts
 *
 * Provides memory usage statistics on-demand
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Memory/Monitors/MemoryMonitor.swift
 */

import type {
  MemoryMonitoringStats,
  MemoryUsageTrend,
} from '../../../Core/Protocols/Memory/MemoryModels';
import {
  MemoryPressureLevel,
  TrendDirection,
} from '../../../Core/Protocols/Memory/MemoryModels';

/**
 * Provides memory usage statistics on-demand
 */
export class MemoryMonitor {
  private memoryThreshold: number = 500_000_000; // 500MB
  private criticalThreshold: number = 200_000_000; // 200MB
  private memoryHistory: MemoryMonitoringStats[] = [];
  private readonly maxHistoryEntries: number = 100;

  /**
   * Configure memory thresholds
   */
  public configure(memoryThreshold: number, criticalThreshold: number): void {
    this.memoryThreshold = memoryThreshold;
    this.criticalThreshold = criticalThreshold;
  }

  /**
   * Get total memory
   */
  public getTotalMemory(): number {
    // In React Native, we can't directly access physical memory
    // This would need to be implemented via native modules
    // For now, return a placeholder
    return 4_000_000_000; // 4GB default
  }

  /**
   * Get available memory
   */
  public getAvailableMemory(): number {
    // In React Native, we can't directly access available memory
    // This would need to be implemented via native modules
    // For now, return a placeholder
    return 2_000_000_000; // 2GB default
  }

  /**
   * Get used memory
   */
  public getUsedMemory(): number {
    const total = this.getTotalMemory();
    const available = this.getAvailableMemory();
    return total - available;
  }

  /**
   * Get memory pressure level
   */
  public getMemoryPressureLevel(): MemoryPressureLevel | null {
    const available = this.getAvailableMemory();

    if (available < this.criticalThreshold) {
      return MemoryPressureLevel.Critical;
    } else if (available < this.memoryThreshold) {
      return MemoryPressureLevel.Warning;
    }

    return null;
  }

  /**
   * Get current stats
   */
  public getCurrentStats(): MemoryMonitoringStats {
    const totalMemory = this.getTotalMemory();
    const availableMemory = this.getAvailableMemory();
    const usedMemory = this.getUsedMemory();
    const pressureLevel = this.getMemoryPressureLevel();

    const stats: MemoryMonitoringStats = {
      totalMemory,
      availableMemory,
      usedMemory,
      pressureLevel,
      timestamp: new Date(),
      usedMemoryPercentage: (usedMemory / totalMemory) * 100,
      availableMemoryPercentage: (availableMemory / totalMemory) * 100,
    };

    // Record stats for history/trends
    this.recordStats(stats);

    return stats;
  }

  /**
   * Get memory trend
   */
  public getMemoryTrend(duration: number): MemoryUsageTrend | null {
    const cutoffTime = new Date(Date.now() - duration * 1000);
    const recentHistory = this.memoryHistory.filter(
      (entry) => entry.timestamp >= cutoffTime
    );

    if (recentHistory.length < 2) {
      return null;
    }

    const firstEntry = recentHistory[0];
    const lastEntry = recentHistory[recentHistory.length - 1];

    if (!firstEntry || !lastEntry) {
      return null;
    }

    const memoryDelta = lastEntry.availableMemory - firstEntry.availableMemory;
    const timeDelta =
      (lastEntry.timestamp.getTime() - firstEntry.timestamp.getTime()) / 1000;

    if (timeDelta <= 0) {
      return null;
    }

    const rate = Math.abs(memoryDelta / timeDelta); // bytes per second

    return {
      direction:
        memoryDelta > 0
          ? TrendDirection.Increasing
          : memoryDelta < 0
          ? TrendDirection.Decreasing
          : TrendDirection.Stable,
      rate,
      confidence: this.calculateTrendConfidence(recentHistory),
      rateString: this.formatBytes(rate) + '/s',
    };
  }

  /**
   * Get average memory usage
   */
  public getAverageMemoryUsage(duration: number): number | null {
    const cutoffTime = new Date(Date.now() - duration * 1000);
    const recentHistory = this.memoryHistory.filter(
      (entry) => entry.timestamp >= cutoffTime
    );

    if (recentHistory.length === 0) {
      return null;
    }

    const totalUsage = recentHistory.reduce(
      (sum, entry) => sum + entry.usedMemory,
      0
    );
    return totalUsage / recentHistory.length;
  }

  /**
   * Record stats
   */
  private recordStats(stats: MemoryMonitoringStats): void {
    // Store in history for trend analysis
    this.memoryHistory.push(stats);
    if (this.memoryHistory.length > this.maxHistoryEntries) {
      this.memoryHistory.shift();
    }
  }

  /**
   * Calculate trend confidence
   */
  private calculateTrendConfidence(
    entries: MemoryMonitoringStats[]
  ): number {
    if (entries.length < 3) {
      return 0.5;
    }

    // Calculate consistency of trend direction
    let consistent = 0;
    let total = 0;

    for (let i = 1; i < entries.length; i++) {
      const currentEntry = entries[i];
      const prevEntry = entries[i - 1];
      const prevPrevEntry = i > 1 ? entries[i - 2] : null;

      if (!currentEntry || !prevEntry) {
        continue;
      }

      const delta = currentEntry.availableMemory - prevEntry.availableMemory;
      const previousDelta =
        prevPrevEntry
          ? prevEntry.availableMemory - prevPrevEntry.availableMemory
          : delta;

      if (
        (delta > 0 && previousDelta > 0) ||
        (delta < 0 && previousDelta < 0)
      ) {
        consistent++;
      }
      total++;
    }

    return total > 0 ? consistent / total : 0.5;
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

