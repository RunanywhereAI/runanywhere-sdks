/**
 * RunAnywhere+Storage.ts
 *
 * Storage management extension.
 * Uses react-native-fs via FileSystem service.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift
 */

import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem } from '../../services/FileSystem';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.Storage');

/**
 * Device storage information
 * Matches Swift's DeviceStorageInfo
 */
export interface DeviceStorageInfo {
  totalSpace: number;
  freeSpace: number;
  usedSpace: number;
}

/**
 * App storage information
 * Matches Swift's AppStorageInfo
 */
export interface AppStorageInfo {
  documentsSize: number;
  cacheSize: number;
  appSupportSize: number;
  totalSize: number;
}

/**
 * Model storage information
 */
export interface ModelStorageInfo {
  totalSize: number;
  modelCount: number;
}

/**
 * Complete storage info structure
 * Matches Swift's StorageInfo
 */
export interface StorageInfo {
  deviceStorage: DeviceStorageInfo;
  appStorage: AppStorageInfo;
  modelStorage: ModelStorageInfo;
  cacheSize: number;
  totalModelsSize: number;
}

/**
 * Get storage information
 * Returns structure matching Swift's StorageInfo
 */
export async function getStorageInfo(): Promise<StorageInfo> {
  const emptyResult: StorageInfo = {
    deviceStorage: { totalSpace: 0, freeSpace: 0, usedSpace: 0 },
    appStorage: { documentsSize: 0, cacheSize: 0, appSupportSize: 0, totalSize: 0 },
    modelStorage: { totalSize: 0, modelCount: 0 },
    cacheSize: 0,
    totalModelsSize: 0,
  };

  if (!FileSystem.isAvailable()) {
    return emptyResult;
  }

  try {
    const freeSpace = await FileSystem.getAvailableDiskSpace();
    const totalSpace = await FileSystem.getTotalDiskSpace();
    const usedSpace = totalSpace - freeSpace;

    // Get models directory size
    let modelsSize = 0;
    let modelCount = 0;
    try {
      const modelsDir = FileSystem.getModelsDirectory();
      const exists = await FileSystem.directoryExists(modelsDir);
      if (exists) {
        modelsSize = await FileSystem.getDirectorySize(modelsDir);
        const files = await FileSystem.listDirectory(modelsDir);
        modelCount = files.length;
      }
    } catch {
      // Models directory may not exist yet
    }

    // Get cache size
    let cacheSize = 0;
    try {
      const cacheDir = FileSystem.getCacheDirectory();
      const exists = await FileSystem.directoryExists(cacheDir);
      if (exists) {
        cacheSize = await FileSystem.getDirectorySize(cacheDir);
      }
    } catch {
      // Cache directory may not exist
    }

    // Get app documents size (RunAnywhere directory)
    let documentsSize = 0;
    try {
      const docsDir = FileSystem.getRunAnywhereDirectory();
      const exists = await FileSystem.directoryExists(docsDir);
      if (exists) {
        documentsSize = await FileSystem.getDirectorySize(docsDir);
      }
    } catch {
      // Documents directory may not exist
    }

    const totalAppSize = documentsSize + cacheSize;

    return {
      deviceStorage: {
        totalSpace,
        freeSpace,
        usedSpace,
      },
      appStorage: {
        documentsSize,
        cacheSize,
        appSupportSize: 0,
        totalSize: totalAppSize,
      },
      modelStorage: {
        totalSize: modelsSize,
        modelCount,
      },
      cacheSize,
      totalModelsSize: modelsSize,
    };
  } catch (error) {
    logger.warning('Failed to get storage info:', { error });
    return emptyResult;
  }
}

/**
 * Clear cache
 */
export async function clearCache(): Promise<void> {
  ModelRegistry.reset();
  logger.info('Cache cleared');
}
