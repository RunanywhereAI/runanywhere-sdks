/**
 * StorageAnalyzer.ts
 * RunAnywhere SDK
 *
 * Protocol for storage analysis operations
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Protocol/StorageAnalyzer.swift
 */

import { StorageInfo } from '../Models/StorageInfo';
import { ModelStorageInfo } from '../../ModelManagement/Models/ModelStorageInfo';
import { StorageAvailability } from '../Models/StorageAvailability';
import { StorageRecommendation } from '../Models/StorageRecommendation';

/**
 * Protocol for storage analysis operations
 */
export interface StorageAnalyzer {
  /**
   * Analyze overall storage situation
   *
   * @returns Promise resolving to storage information
   */
  analyzeStorage(): Promise<StorageInfo>;

  /**
   * Get model storage usage information
   *
   * @returns Promise resolving to model storage information
   */
  getModelStorageUsage(): Promise<ModelStorageInfo>;

  /**
   * Check storage availability for a model
   *
   * @param modelSize - Size of the model in bytes
   * @param safetyMargin - Safety margin as a percentage (e.g., 0.1 for 10%)
   * @returns Storage availability information
   */
  checkStorageAvailable(modelSize: number, safetyMargin: number): StorageAvailability;

  /**
   * Get storage recommendations
   *
   * @param storageInfo - Current storage information
   * @returns Array of storage recommendations
   */
  getRecommendations(storageInfo: StorageInfo): StorageRecommendation[];

  /**
   * Calculate size at path
   *
   * @param path - File or directory path
   * @returns Promise resolving to size in bytes
   * @throws Error if path does not exist or cannot be accessed
   */
  calculateSize(path: string): Promise<number>;
}
