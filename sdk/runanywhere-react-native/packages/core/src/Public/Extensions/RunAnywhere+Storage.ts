/**
 * RunAnywhere+Storage.ts
 *
 * Storage management extension.
 * Delegates to C++ via native module for storage info (C++ handles recursive traversal).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift
 */

import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem } from '../../services/FileSystem';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { requireNativeModule, isNativeModuleAvailable } from '../../native';

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
 * Get models directory path on device
 * Returns: Documents/RunAnywhere/Models/
 */
export async function getModelsDirectory(): Promise<string> {
  if (!FileSystem.isAvailable()) {
    return '';
  }
  return FileSystem.getModelsDirectory();
}

/**
 * Get storage information
 * Delegates to C++ FileManagerBridge for recursive directory traversal.
 * Returns structure matching Swift's StorageInfo.
 */
export async function getStorageInfo(): Promise<StorageInfo> {
  const emptyResult: StorageInfo = {
    deviceStorage: { totalSpace: 0, freeSpace: 0, usedSpace: 0 },
    appStorage: { documentsSize: 0, cacheSize: 0, appSupportSize: 0, totalSize: 0 },
    modelStorage: { totalSize: 0, modelCount: 0 },
    cacheSize: 0,
    totalModelsSize: 0,
  };

  try {
    // Use native module (C++ FileManagerBridge handles recursive traversal)
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      const json = await native.getStorageInfo();
      const info = JSON.parse(json);

      const totalDeviceSpace = parseInt(info.totalDeviceSpace || '0', 10);
      const freeDeviceSpace = parseInt(info.freeDeviceSpace || '0', 10);
      const usedDeviceSpace = parseInt(info.usedDeviceSpace || '0', 10);
      const documentsSize = parseInt(info.documentsSize || '0', 10);
      const cacheSz = parseInt(info.cacheSize || '0', 10);
      const appSupportSize = parseInt(info.appSupportSize || '0', 10);
      const totalAppSize = parseInt(info.totalAppSize || '0', 10);
      const totalModelsSize = parseInt(info.totalModelsSize || '0', 10);
      const modelCount = parseInt(info.modelCount || '0', 10);

      return {
        deviceStorage: {
          totalSpace: totalDeviceSpace,
          freeSpace: freeDeviceSpace,
          usedSpace: usedDeviceSpace,
        },
        appStorage: {
          documentsSize,
          cacheSize: cacheSz,
          appSupportSize,
          totalSize: totalAppSize,
        },
        modelStorage: {
          totalSize: totalModelsSize,
          modelCount,
        },
        cacheSize: cacheSz,
        totalModelsSize,
      };
    }

    // Native module is required for storage info (C++ handles recursive traversal)
    return emptyResult;
  } catch (error) {
    logger.warning('Failed to get storage info:', { error });
    return emptyResult;
  }
}

/**
 * Clear cache
 * Delegates to C++ FileManagerBridge for file cache/temp clearing.
 */
export async function clearCache(): Promise<void> {
  // Clear in-memory model registry cache
  ModelRegistry.reset();

  // Clear file caches via native module (C++ handles directory clearing)
  if (isNativeModuleAvailable()) {
    try {
      const native = requireNativeModule();
      await native.clearCache();
    } catch (error) {
      logger.warning('Failed to clear native cache:', { error });
    }
  }

  logger.info('Cache cleared');
}
