/**
 * MemoryModels.ts
 *
 * Memory-related models
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Memory/MemoryManager.swift
 */

import { LLMFramework } from '../../Models/Framework/LLMFramework';

/**
 * Memory-tracked model information
 */
export interface MemoryLoadedModel {
  readonly id: string;
  readonly name: string;
  readonly size: number; // Int64
  readonly framework: LLMFramework;
  readonly loadedAt: Date;
  lastUsed: Date;
  readonly priority: MemoryPriority;
}

/**
 * Memory priority levels
 */
export enum MemoryPriority {
  Low = 0,
  Normal = 1,
  High = 2,
  Critical = 3,
}

/**
 * Memory-specific information about a loaded model
 */
export interface MemoryLoadedModelInfo {
  readonly model: MemoryLoadedModel;
  readonly size: number; // Int64
  lastUsed: Date;
  readonly service: any | null; // LLMService (weak reference in Swift)
  readonly priority: MemoryPriority;
}

/**
 * Memory statistics
 */
export interface MemoryStatistics {
  readonly totalMemory: number; // Int64
  readonly availableMemory: number; // Int64
  readonly modelMemory: number; // Int64
  readonly loadedModelCount: number;
  readonly memoryPressure: boolean;

  readonly usedMemoryPercentage: number;
  readonly modelMemoryPercentage: number;
}

/**
 * Memory monitoring statistics
 */
export interface MemoryMonitoringStats {
  readonly totalMemory: number; // Int64
  readonly availableMemory: number; // Int64
  readonly usedMemory: number; // Int64
  readonly pressureLevel: MemoryPressureLevel | null;
  readonly timestamp: Date;

  readonly usedMemoryPercentage: number;
  readonly availableMemoryPercentage: number;
}

/**
 * Memory pressure levels
 */
export enum MemoryPressureLevel {
  Low = 'low',
  Medium = 'medium',
  High = 'high',
  Warning = 'warning',
  Critical = 'critical',
}

/**
 * Memory usage trend information
 */
export interface MemoryUsageTrend {
  readonly direction: TrendDirection;
  readonly rate: number; // bytes per second
  readonly confidence: number; // 0.0 to 1.0
  readonly rateString: string;
}

/**
 * Trend direction
 */
export enum TrendDirection {
  Increasing = 'increasing',
  Decreasing = 'decreasing',
  Stable = 'stable',
}

/**
 * Eviction statistics
 */
export interface EvictionStatistics {
  readonly totalModels: number;
  readonly totalMemory: number; // Int64
  readonly modelsByPriority: { [key: number]: number }; // MemoryPriority -> count
  readonly averageLastUsed: Date;
  readonly oldestModel: Date;
  readonly largestModel: number; // Int64
  readonly totalMemoryString: string;
  readonly largestModelString: string;
}
