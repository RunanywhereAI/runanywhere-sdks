/**
 * StorageConstants.ts
 * RunAnywhere SDK
 *
 * Storage and file management configuration constants.
 * Matches iOS: Infrastructure/FileManagement/Constants/StorageConstants.swift
 */

/**
 * Storage and file management configuration constants
 */
export const StorageConstants = {
  // MARK: - Directory Names

  /** Model directory name */
  modelDirectoryName: 'RunAnywhereModels',

  /** Cache directory name */
  cacheDirectoryName: 'RunAnywhereCache',

  /** Temporary directory name */
  tempDirectoryName: 'RunAnywhereTmp',

  // MARK: - Cache Configuration

  /** Cache size limit in bytes (100 MB) */
  cacheSizeLimit: 100 * 1024 * 1024,

  /** Default max cache size in MB */
  defaultMaxCacheSizeMB: 2048,

  /** Default cleanup threshold percentage */
  defaultCleanupThresholdPercentage: 90,

  /** Default model retention days */
  defaultModelRetentionDays: 30,
} as const;

/**
 * Type for StorageConstants
 */
export type StorageConstantsType = typeof StorageConstants;
