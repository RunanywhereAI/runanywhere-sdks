/**
 * StorageInfo.ts
 * RunAnywhere SDK
 *
 * Storage information aggregating app, device, and model storage data
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Models/Domain/StorageInfo.swift
 */

import type { AppStorageInfo } from './AppStorageInfo';
import { createAppStorageInfo } from './AppStorageInfo';
import type { DeviceStorageInfo } from './DeviceStorageInfo';
import { createDeviceStorageInfo } from './DeviceStorageInfo';
import type { ModelStorageInfo } from '../../ModelManagement/Models/ModelStorageInfo';
import { createEmptyModelStorageInfo } from '../../ModelManagement/Models/ModelStorageInfo';
import type { StoredModel } from '../../ModelManagement/Models/StoredModel';

/**
 * Storage information
 */
export interface StorageInfo {
  /** App storage breakdown */
  readonly appStorage: AppStorageInfo;
  /** Device storage information */
  readonly deviceStorage: DeviceStorageInfo;
  /** Model storage information */
  readonly modelStorage: ModelStorageInfo;
  /** Cache size in bytes */
  readonly cacheSize: number;
  /** List of stored models */
  readonly storedModels: StoredModel[];
  /** Last time storage info was updated */
  readonly lastUpdated: Date;
}

/**
 * Creates a StorageInfo instance
 *
 * @param params - Storage info parameters
 * @returns StorageInfo instance
 */
export function createStorageInfo(params: {
  appStorage: AppStorageInfo;
  deviceStorage: DeviceStorageInfo;
  modelStorage: ModelStorageInfo;
  cacheSize: number;
  storedModels: StoredModel[];
  lastUpdated: Date;
}): StorageInfo {
  return {
    appStorage: params.appStorage,
    deviceStorage: params.deviceStorage,
    modelStorage: params.modelStorage,
    cacheSize: params.cacheSize,
    storedModels: params.storedModels,
    lastUpdated: params.lastUpdated,
  };
}

/**
 * Creates an empty StorageInfo instance for initialization
 *
 * @returns Empty StorageInfo instance
 */
export function createEmptyStorageInfo(): StorageInfo {
  return createStorageInfo({
    appStorage: createAppStorageInfo({
      documentsSize: 0,
      cacheSize: 0,
      appSupportSize: 0,
      totalSize: 0,
    }),
    deviceStorage: createDeviceStorageInfo({
      totalSpace: 0,
      freeSpace: 0,
      usedSpace: 0,
    }),
    modelStorage: createEmptyModelStorageInfo(),
    cacheSize: 0,
    storedModels: [],
    lastUpdated: new Date(),
  });
}
