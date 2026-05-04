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
import {
  StorageAvailabilityRequest,
  StorageAvailabilityResult as StorageAvailabilityResultCodec,
  StorageDeletePlan as StorageDeletePlanCodec,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult as StorageDeleteResultCodec,
  StorageInfoRequest,
  StorageInfoResult as StorageInfoResultCodec,
} from '@runanywhere/proto-ts/storage_types';
import type {
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeleteResult,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.Storage');

export type {
  StorageAvailability,
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeleteCandidate,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfo as ProtoStorageInfo,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';

function encode<T>(
  message: T,
  codec: { encode(value: T): { finish(): Uint8Array } }
): ArrayBuffer {
  return bytesToArrayBuffer(codec.encode(message).finish());
}

function decode<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T },
  fallback: T
): T {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? fallback : codec.decode(bytes);
}

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
 * Get canonical generated storage info from native commons.
 */
export async function getStorageInfoProto(
  request: StorageInfoRequest = {
    includeDevice: true,
    includeApp: true,
    includeModels: true,
  }
): Promise<StorageInfoResult> {
  if (!isNativeModuleAvailable()) {
    return StorageInfoResultCodec.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.storageInfoProto(
    encode(request, StorageInfoRequest)
  );
  return decode(
    buffer,
    StorageInfoResultCodec,
    StorageInfoResultCodec.fromPartial({
      success: false,
      errorMessage: 'storageInfoProto returned an empty result',
    })
  );
}

/**
 * Check storage availability using the canonical generated request/result.
 */
export async function checkStorageAvailability(
  request: StorageAvailabilityRequest
): Promise<StorageAvailabilityResult> {
  if (!isNativeModuleAvailable()) {
    return StorageAvailabilityResultCodec.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.storageAvailabilityProto(
    encode(request, StorageAvailabilityRequest)
  );
  return decode(
    buffer,
    StorageAvailabilityResultCodec,
    StorageAvailabilityResultCodec.fromPartial({
      success: false,
      errorMessage: 'storageAvailabilityProto returned an empty result',
    })
  );
}

/**
 * Build a native storage delete plan.
 */
export async function planStorageDelete(
  request: StorageDeletePlanRequest
): Promise<StorageDeletePlan> {
  if (!isNativeModuleAvailable()) {
    return StorageDeletePlanCodec.fromPartial({
      canReclaimRequiredBytes: false,
      requiredBytes: request.requiredBytes,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.storageDeletePlanProto(
    encode(request, StorageDeletePlanRequest)
  );
  return decode(
    buffer,
    StorageDeletePlanCodec,
    StorageDeletePlanCodec.fromPartial({
      canReclaimRequiredBytes: false,
      requiredBytes: request.requiredBytes,
      errorMessage: 'storageDeletePlanProto returned an empty result',
    })
  );
}

/**
 * Execute or dry-run native storage deletion.
 */
export async function deleteStorage(
  request: StorageDeleteRequest
): Promise<StorageDeleteResult> {
  if (!isNativeModuleAvailable()) {
    return StorageDeleteResultCodec.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.storageDeleteProto(
    encode(request, StorageDeleteRequest)
  );
  return decode(
    buffer,
    StorageDeleteResultCodec,
    StorageDeleteResultCodec.fromPartial({
      success: false,
      errorMessage: 'storageDeleteProto returned an empty result',
    })
  );
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
    const result = await getStorageInfoProto();
    if (result.success && result.info) {
      const info = result.info;
      return {
        deviceStorage: {
          totalSpace: info.device?.totalBytes ?? 0,
          freeSpace: info.device?.freeBytes ?? 0,
          usedSpace: info.device?.usedBytes ?? 0,
        },
        appStorage: {
          documentsSize: info.app?.documentsBytes ?? 0,
          cacheSize: info.app?.cacheBytes ?? 0,
          appSupportSize: info.app?.appSupportBytes ?? 0,
          totalSize: info.app?.totalBytes ?? 0,
        },
        modelStorage: {
          totalSize: info.totalModelsBytes,
          modelCount: info.totalModels,
        },
        cacheSize: info.app?.cacheBytes ?? 0,
        totalModelsSize: info.totalModelsBytes,
      };
    }

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
