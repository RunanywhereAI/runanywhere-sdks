/**
 * RunAnywhere+Storage.ts
 *
 * Storage management extension.
 * Delegates to native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift
 */

import { requireFileSystemModule, isNativeModuleAvailable } from '../../native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.Storage');

/**
 * Storage info type
 */
export interface StorageInfo {
  totalSpace: number;
  freeSpace: number;
  usedSpace: number;
  modelsSize: number;
}

/**
 * Get storage information
 */
export async function getStorageInfo(): Promise<StorageInfo> {
  if (!isNativeModuleAvailable()) {
    return { totalSpace: 0, freeSpace: 0, usedSpace: 0, modelsSize: 0 };
  }

  try {
    const fs = requireFileSystemModule();
    const freeSpace = await fs.getAvailableDiskSpace();
    const totalSpace = await fs.getTotalDiskSpace();

    return {
      totalSpace,
      freeSpace,
      usedSpace: totalSpace - freeSpace,
      modelsSize: 0, // Would need to scan models directory
    };
  } catch (error) {
    logger.warning('Failed to get storage info:', { error });
    return { totalSpace: 0, freeSpace: 0, usedSpace: 0, modelsSize: 0 };
  }
}

/**
 * Clear cache
 */
export async function clearCache(): Promise<void> {
  ModelRegistry.reset();
  logger.info('Cache cleared');
}
