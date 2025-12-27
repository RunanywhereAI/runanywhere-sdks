/**
 * Storage Recommendation Types
 *
 * Provides storage recommendations for file management operations.
 * Matches iOS SDK: Infrastructure/FileManagement/Models/Domain/StorageRecommendation.swift
 *
 * @module Infrastructure/FileManagement/Models
 */

/**
 * Recommendation type indicating severity level
 */
export enum RecommendationType {
  /** Critical storage issue requiring immediate action */
  Critical = 'critical',
  /** Warning about storage that should be addressed soon */
  Warning = 'warning',
  /** Suggestion for optimizing storage */
  Suggestion = 'suggestion',
}

/**
 * Storage recommendation
 *
 * Represents a recommendation for storage management,
 * including severity, description, and suggested action.
 */
export interface StorageRecommendation {
  /** Type of recommendation */
  readonly type: RecommendationType;
  /** Human-readable message describing the issue */
  readonly message: string;
  /** Suggested action to address the issue */
  readonly action: string;
}

/**
 * Creates a storage recommendation
 *
 * @param type - Type of recommendation
 * @param message - Human-readable message describing the issue
 * @param action - Suggested action to address the issue
 * @returns Storage recommendation object
 *
 * @example
 * ```typescript
 * const recommendation = createStorageRecommendation(
 *   RecommendationType.WARNING,
 *   'Storage space is running low',
 *   'Consider removing unused models'
 * );
 * ```
 */
export function createStorageRecommendation(
  type: RecommendationType,
  message: string,
  action: string
): StorageRecommendation {
  return {
    type,
    message,
    action,
  };
}

/**
 * Type guard to check if an object is a valid StorageRecommendation
 *
 * @param obj - Object to check
 * @returns True if object is a valid StorageRecommendation
 */
export function isStorageRecommendation(
  obj: unknown
): obj is StorageRecommendation {
  if (typeof obj !== 'object' || obj === null) {
    return false;
  }

  const recommendation = obj as Record<string, unknown>;

  return (
    typeof recommendation.type === 'string' &&
    Object.values(RecommendationType).includes(
      recommendation.type as RecommendationType
    ) &&
    typeof recommendation.message === 'string' &&
    typeof recommendation.action === 'string'
  );
}
