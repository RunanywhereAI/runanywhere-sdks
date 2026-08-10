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
  StorageAvailability as StorageAvailabilityMessage,
} from '@runanywhere/proto-ts/storage_types';
import type {
  DeviceStorageInfo,
  AppStorageInfo,
  StorageInfo,
  ModelStorageMetrics,
  StorageAvailability,
} from '@runanywhere/proto-ts/storage_types';

/**
 * Build a `DeviceStorageInfo`. Mirrors Swift
 * `RADeviceStorageInfo.init(totalBytes:freeBytes:usedBytes:)`.
 *
 * `usedPercent` is deleted outright — it is a pure derivation of
 * `usedBytes`/`totalBytes` with no independent writer; callers needing it
 * should use {@link usagePercentage} below instead of a stored field.
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

/**
 * Empty storage snapshot. Mirrors Swift `RAStorageInfo.empty`.
 *
 * `totalModels` is deleted outright — `models.length` is the sole count
 * signal now (unlike `totalModelsBytes`, which stays a live field per its
 * idl comment).
 */
export function emptyStorageInfo(): StorageInfo {
  return StorageInfoMessage.fromPartial({
    app: AppStorageInfoMessage.fromPartial({}),
    device: DeviceStorageInfoMessage.fromPartial({}),
    models: [],
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
 *
 * `lastUsedMs` is deleted outright — the message now carries only
 * `modelId`/`sizeOnDiskBytes`, so this helper drops its third parameter.
 */
export function makeModelStorageMetrics(
  modelId: string,
  sizeOnDiskBytes: number
): ModelStorageMetrics {
  return ModelStorageMetricsMessage.fromPartial({
    modelId,
    sizeOnDiskBytes,
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
