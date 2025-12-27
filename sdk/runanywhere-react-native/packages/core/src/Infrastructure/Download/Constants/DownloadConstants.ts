/**
 * DownloadConstants.ts
 * RunAnywhere SDK
 *
 * Download and network configuration constants.
 * Matches iOS: Infrastructure/Download/Constants/DownloadConstants.swift
 */

/**
 * Download and network configuration constants
 */
export const DownloadConstants = {
  // MARK: - Timeout Configuration

  /** Default API timeout in seconds */
  defaultAPITimeout: 60,

  /** Default download timeout in seconds */
  defaultDownloadTimeout: 300,

  // MARK: - Retry Configuration

  /** Maximum retry attempts */
  maxRetryAttempts: 3,

  /** Retry delay in seconds */
  retryDelay: 1.0,

  /** Default batch size for operations */
  defaultBatchSize: 32,

  // MARK: - Download Configuration

  /** Default chunk size for downloads in bytes (1MB) */
  defaultChunkSize: 1024 * 1024,

  /** Maximum concurrent downloads */
  maxConcurrentDownloads: 3,

  /** Progress update interval in milliseconds */
  progressUpdateInterval: 100,
} as const;

/**
 * Type for DownloadConstants
 */
export type DownloadConstantsType = typeof DownloadConstants;
