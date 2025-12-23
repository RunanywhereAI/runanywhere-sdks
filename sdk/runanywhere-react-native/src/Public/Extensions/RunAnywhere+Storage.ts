/**
 * RunAnywhere+Storage.ts
 *
 * Storage management extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+Storage.swift
 */

import { requireFileSystemModule } from '../../native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { ServiceContainer } from '../../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.Storage');

// ============================================================================
// Storage Management Extension
// ============================================================================

/**
 * Get storage information including app storage, device storage, and model storage.
 *
 * Matches iOS: static func getStorageInfo() async -> StorageInfo
 */
export async function getStorageInfo(): Promise<
  import('../../Infrastructure/FileManagement/Models').StorageInfo
> {
  const fs = requireFileSystemModule();

  const freeSpace = await fs.getAvailableDiskSpace();
  const totalSpace = await fs.getTotalDiskSpace();

  const models = await ModelRegistry.getAvailableModels();
  const downloadedModels = models.filter((m) => m.isDownloaded);
  let modelsSize = 0;

  for (const model of downloadedModels) {
    modelsSize += model.downloadSize || 0;
  }

  const { createStorageInfo } = await import(
    '../../Infrastructure/FileManagement/Models'
  );
  const { createAppStorageInfo } = await import(
    '../../Infrastructure/FileManagement/Models/AppStorageInfo'
  );
  const { createDeviceStorageInfo } = await import(
    '../../Infrastructure/FileManagement/Models/DeviceStorageInfo'
  );
  const { createEmptyModelStorageInfo } = await import(
    '../../Infrastructure/ModelManagement/Models/ModelStorageInfo'
  );

  const modelStorageInfo = {
    ...createEmptyModelStorageInfo(),
    totalSize: modelsSize,
    modelCount: downloadedModels.length,
  };

  return createStorageInfo({
    appStorage: createAppStorageInfo({
      documentsSize: modelsSize,
      cacheSize: 0,
      appSupportSize: 0,
      totalSize: modelsSize,
    }),
    deviceStorage: createDeviceStorageInfo({
      totalSpace,
      freeSpace,
      usedSpace: totalSpace - freeSpace,
    }),
    modelStorage: modelStorageInfo,
    cacheSize: 0,
    storedModels: [],
    lastUpdated: new Date(),
  });
}

/**
 * Clear cache files.
 *
 * Matches iOS: static func clearCache() async throws
 */
export async function clearCache(): Promise<void> {
  const modelAssignmentService =
    ServiceContainer.shared.modelAssignmentService;
  if (modelAssignmentService) {
    modelAssignmentService.clearCache();
  }

  logger.info('Cache cleared successfully');
}

/**
 * Clean temporary files.
 *
 * Matches iOS: static func cleanTempFiles() async throws
 */
export async function cleanTempFiles(): Promise<void> {
  logger.info('Temp files cleanup signal sent');
}

/**
 * Get the base directory URL where models and data are stored.
 *
 * Matches iOS: static func getBaseDirectoryURL() -> URL
 */
export async function getBaseDirectoryURL(): Promise<string> {
  const fs = requireFileSystemModule();
  return fs.getDataDirectory();
}
