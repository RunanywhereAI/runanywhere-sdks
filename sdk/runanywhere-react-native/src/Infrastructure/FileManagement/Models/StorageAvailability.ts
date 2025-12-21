/**
 * Storage availability check result
 *
 * Represents the result of checking storage availability for model downloads
 * and other file operations. Provides detailed information about available space,
 * required space, and recommendations for the user.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Models/Domain/StorageAvailability.swift
 */

/**
 * Storage availability information
 */
export interface StorageAvailability {
  /**
   * Whether sufficient storage space is available
   */
  readonly isAvailable: boolean;

  /**
   * Required storage space in bytes
   */
  readonly requiredSpace: number;

  /**
   * Available storage space in bytes
   */
  readonly availableSpace: number;

  /**
   * Whether there is a warning about storage (e.g., low space but still available)
   */
  readonly hasWarning: boolean;

  /**
   * Optional recommendation message for the user
   */
  readonly recommendation: string | null;
}

/**
 * Creates a StorageAvailability instance
 *
 * @param params - Storage availability parameters
 * @returns StorageAvailability instance
 */
export function createStorageAvailability(params: {
  isAvailable: boolean;
  requiredSpace: number;
  availableSpace: number;
  hasWarning: boolean;
  recommendation?: string | null;
}): StorageAvailability {
  return {
    isAvailable: params.isAvailable,
    requiredSpace: params.requiredSpace,
    availableSpace: params.availableSpace,
    hasWarning: params.hasWarning,
    recommendation: params.recommendation ?? null,
  };
}

/**
 * Creates a StorageAvailability instance indicating available storage
 *
 * @param requiredSpace - Required storage space in bytes
 * @param availableSpace - Available storage space in bytes
 * @param hasWarning - Whether to include a warning
 * @param recommendation - Optional recommendation message
 * @returns StorageAvailability instance with isAvailable=true
 */
export function createAvailableStorage(
  requiredSpace: number,
  availableSpace: number,
  hasWarning: boolean = false,
  recommendation?: string | null
): StorageAvailability {
  return createStorageAvailability({
    isAvailable: true,
    requiredSpace,
    availableSpace,
    hasWarning,
    recommendation,
  });
}

/**
 * Creates a StorageAvailability instance indicating unavailable storage
 *
 * @param requiredSpace - Required storage space in bytes
 * @param availableSpace - Available storage space in bytes
 * @param recommendation - Optional recommendation message
 * @returns StorageAvailability instance with isAvailable=false
 */
export function createUnavailableStorage(
  requiredSpace: number,
  availableSpace: number,
  recommendation?: string | null
): StorageAvailability {
  return createStorageAvailability({
    isAvailable: false,
    requiredSpace,
    availableSpace,
    hasWarning: true,
    recommendation,
  });
}

/**
 * Formats storage size in human-readable format
 *
 * @param bytes - Size in bytes
 * @returns Formatted string (e.g., "1.5 GB")
 */
export function formatStorageSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(2)} ${units[unitIndex]}`;
}

/**
 * Gets a human-readable description of storage availability
 *
 * @param availability - StorageAvailability instance
 * @returns Human-readable description
 */
export function getStorageDescription(availability: StorageAvailability): string {
  const required = formatStorageSize(availability.requiredSpace);
  const available = formatStorageSize(availability.availableSpace);

  if (availability.isAvailable) {
    if (availability.hasWarning) {
      return `Storage available but limited: ${available} available, ${required} required. ${availability.recommendation || ''}`;
    }
    return `Storage available: ${available} available, ${required} required.`;
  }

  return `Insufficient storage: ${available} available, ${required} required. ${availability.recommendation || ''}`;
}
