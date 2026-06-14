/**
 * StorageProto+Helpers.ts
 *
 * Ergonomic helpers for canonical Storage proto types.
 *
 * Mirrors Swift `StorageProto+Helpers.swift`. Pure-rename field aliases were
 * already removed on the Swift side (SWIFT-DUP-STORAGE-ALIASES) and are not
 * ported; only the helpers with actual logic are mirrored.
 */

import {
  DeviceStorageInfo as DeviceStorageInfoMessage,
  AppStorageInfo as AppStorageInfoMessage,
  StorageInfo as StorageInfoMessage,
  ModelStorageMetrics as ModelStorageMetricsMessage,
  StoredModel as StoredModelMessage,
  StorageAvailability as StorageAvailabilityMessage,
} from '@runanywhere/proto-ts/storage_types';
import type {
  DeviceStorageInfo,
  AppStorageInfo,
  StorageInfo,
  ModelStorageMetrics,
  StoredModel,
  StorageAvailability,
} from '@runanywhere/proto-ts/storage_types';

/**
 * Build a `DeviceStorageInfo` with `usedPercent` derived from the byte
 * counts. Mirrors Swift `RADeviceStorageInfo.init(totalBytes:freeBytes:usedBytes:)`.
 */
export function makeDeviceStorageInfo(
  totalBytes: number,
  freeBytes: number,
  usedBytes: number
): DeviceStorageInfo {
  return DeviceStorageInfoMessage.fromPartial({
    totalBytes,
    freeBytes,
    usedBytes,
    usedPercent: totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0.0,
  });
}

/**
 * Build an `AppStorageInfo`. Mirrors Swift
 * `RAAppStorageInfo.init(documentsBytes:cacheBytes:appSupportBytes:totalBytes:)`.
 */
export function makeAppStorageInfo(
  documentsBytes: number,
  cacheBytes: number,
  appSupportBytes: number,
  totalBytes: number
): AppStorageInfo {
  return AppStorageInfoMessage.fromPartial({
    documentsBytes,
    cacheBytes,
    appSupportBytes,
    totalBytes,
  });
}

/** Empty storage snapshot. Mirrors Swift `RAStorageInfo.empty`. */
export function emptyStorageInfo(): StorageInfo {
  return StorageInfoMessage.fromPartial({
    app: AppStorageInfoMessage.fromPartial({}),
    device: DeviceStorageInfoMessage.fromPartial({}),
    models: [],
    totalModels: 0,
    totalModelsBytes: 0,
  });
}

/**
 * Sum of per-model on-disk sizes. Mirrors Swift
 * `RAStorageInfo.totalModelsSizeBytes`.
 */
export function totalModelsSizeBytes(info: StorageInfo): number {
  return info.models.reduce(
    (total, metrics) => total + metrics.sizeOnDiskBytes,
    0
  );
}

/**
 * Total models size with the per-model sum as fallback. Mirrors Swift
 * `RAStorageInfo.totalModelsSize`.
 */
export function totalModelsSize(info: StorageInfo): number {
  return info.totalModelsBytes > 0
    ? info.totalModelsBytes
    : totalModelsSizeBytes(info);
}

/**
 * Per-model metrics projected into `StoredModel` rows. Mirrors Swift
 * `RAStorageInfo.storedModels`.
 */
export function storedModels(info: StorageInfo): StoredModel[] {
  return info.models.map((metrics: ModelStorageMetrics) =>
    StoredModelMessage.fromPartial({
      modelId: metrics.modelId,
      name: metrics.modelId,
      sizeBytes: metrics.sizeOnDiskBytes,
    })
  );
}

/**
 * Usage percentage of a device storage snapshot. Mirrors Swift
 * `RADeviceStorageInfo.usagePercentage`.
 */
export function usagePercentage(device: DeviceStorageInfo): number {
  if (device.totalBytes <= 0) return 0;
  return (device.usedBytes / device.totalBytes) * 100.0;
}

/**
 * Build a `ModelStorageMetrics`. Mirrors Swift
 * `RAModelStorageMetrics.init(modelID:sizeOnDiskBytes:lastUsedMs:)`.
 */
export function makeModelStorageMetrics(
  modelId: string,
  sizeOnDiskBytes: number,
  lastUsedMs?: number
): ModelStorageMetrics {
  return ModelStorageMetricsMessage.fromPartial({
    modelId,
    sizeOnDiskBytes,
    ...(lastUsedMs !== undefined ? { lastUsedMs } : {}),
  });
}

/**
 * Build a `StorageAvailability`. Mirrors Swift
 * `RAStorageAvailability.make(isAvailable:requiredBytes:availableBytes:recommendation:)`.
 */
export function makeStorageAvailability(
  isAvailable: boolean,
  requiredBytes: number,
  availableBytes: number,
  recommendation?: string
): StorageAvailability {
  return StorageAvailabilityMessage.fromPartial({
    isAvailable,
    requiredBytes,
    availableBytes,
    ...(recommendation !== undefined ? { recommendation } : {}),
  });
}
