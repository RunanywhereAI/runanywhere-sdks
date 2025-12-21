/**
 * DeviceStorageInfo.ts
 * RunAnywhere SDK
 *
 * Device storage information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Models/Domain/DeviceStorageInfo.swift
 */

/**
 * Device storage information
 */
export interface DeviceStorageInfo {
  /** Total device storage space in bytes */
  readonly totalSpace: number;
  /** Free device storage space in bytes */
  readonly freeSpace: number;
  /** Used device storage space in bytes */
  readonly usedSpace: number;
}

/**
 * Creates a DeviceStorageInfo instance
 *
 * @param params - Device storage parameters
 * @returns DeviceStorageInfo instance
 */
export function createDeviceStorageInfo(params: {
  totalSpace: number;
  freeSpace: number;
  usedSpace: number;
}): DeviceStorageInfo {
  return {
    totalSpace: params.totalSpace,
    freeSpace: params.freeSpace,
    usedSpace: params.usedSpace,
  };
}

/**
 * Calculate device storage usage percentage
 *
 * @param info - DeviceStorageInfo instance
 * @returns Usage percentage (0-100)
 */
export function getDeviceStorageUsagePercentage(
  info: DeviceStorageInfo
): number {
  if (info.totalSpace <= 0) {
    return 0;
  }
  return (info.usedSpace / info.totalSpace) * 100;
}
