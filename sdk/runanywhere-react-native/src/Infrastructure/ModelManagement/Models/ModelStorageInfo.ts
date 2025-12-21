/**
 * ModelStorageInfo.ts
 * RunAnywhere SDK
 *
 * Aggregate information about all stored models.
 * Located in ModelManagement as it aggregates model-specific data.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/ModelStorageInfo.swift
 */

import type { InferenceFramework } from './InferenceFramework';
import type { StoredModel } from './StoredModel';

/**
 * Aggregate information about all stored models
 */
export interface ModelStorageInfo {
  /** Total size of all stored models in bytes */
  totalSize: number;

  /** Number of stored models */
  modelCount: number;

  /** Models grouped by inference framework */
  modelsByFramework: Map<InferenceFramework, StoredModel[]>;

  /** The largest model by size */
  largestModel: StoredModel | null;
}

/**
 * Create a ModelStorageInfo instance
 */
export function createModelStorageInfo(params: {
  totalSize: number;
  modelCount: number;
  modelsByFramework: Map<InferenceFramework, StoredModel[]>;
  largestModel: StoredModel | null;
}): ModelStorageInfo {
  return {
    totalSize: params.totalSize,
    modelCount: params.modelCount,
    modelsByFramework: params.modelsByFramework,
    largestModel: params.largestModel,
  };
}

/**
 * Create an empty ModelStorageInfo instance
 */
export function createEmptyModelStorageInfo(): ModelStorageInfo {
  return {
    totalSize: 0,
    modelCount: 0,
    modelsByFramework: new Map(),
    largestModel: null,
  };
}

/**
 * Get models for a specific framework
 */
export function getModelsForFramework(
  info: ModelStorageInfo,
  framework: InferenceFramework
): StoredModel[] {
  return info.modelsByFramework.get(framework) ?? [];
}

/**
 * Get total count of frameworks in use
 */
export function getFrameworkCount(info: ModelStorageInfo): number {
  return info.modelsByFramework.size;
}

/**
 * Get all frameworks that have models
 */
export function getActiveFrameworks(
  info: ModelStorageInfo
): InferenceFramework[] {
  return Array.from(info.modelsByFramework.keys());
}

/**
 * Format total size as human-readable string
 */
export function formatTotalSize(info: ModelStorageInfo): string {
  const bytes = info.totalSize;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(2)} ${units[unitIndex]}`;
}
