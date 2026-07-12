/**
 * StorageProto+Helpers.ts
 *
 * Ergonomic helpers for canonical Storage proto types — Swift parity:
 * `StorageProto+Helpers.swift` (Public/Extensions/Storage). Swift expresses
 * these as extensions on the generated proto structs; TS expresses them as
 * standalone functions over the generated `@runanywhere/proto-ts/storage_types`
 * shapes (idl/storage_types.proto).
 *
 * Aliases removed in Swift per SWIFT-DUP-STORAGE-ALIASES (`totalSpace`,
 * `documentsSize`, `modelId`/`sizeOnDisk`/`lastUsed`, `hasWarning`, ...) are
 * intentionally NOT ported — use the canonical proto field names.
 */

import {
  AppStorageInfo,
  DeviceStorageInfo,
  ModelStorageMetrics,
  StorageAvailability,
  StorageInfo,
} from '@runanywhere/proto-ts/storage_types';

// MARK: - DeviceStorageInfo

/**
 * Build a `DeviceStorageInfo` with `usedPercent` materialized.
 * Swift parity: `RADeviceStorageInfo.init(totalBytes:freeBytes:usedBytes:)`
 * (StorageProto+Helpers.swift:13-21).
 */
export function makeDeviceStorageInfo(
  totalBytes: number,
  freeBytes: number,
  usedBytes: number,
): DeviceStorageInfo {
  return DeviceStorageInfo.fromPartial({
    totalBytes,
    freeBytes,
    usedBytes,
    usedPercent: totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0.0,
  });
}

/**
 * Usage percentage (0.0 — 100.0), computed from the byte counters.
 * Swift parity: `RADeviceStorageInfo.usagePercentage`
 * (StorageProto+Helpers.swift:27-30).
 */
export function deviceStorageUsagePercentage(info: DeviceStorageInfo): number {
  if (info.totalBytes <= 0) return 0;
  return (info.usedBytes / info.totalBytes) * 100.0;
}

// MARK: - AppStorageInfo

/**
 * Build an `AppStorageInfo`.
 * Swift parity: `RAAppStorageInfo.init(documentsBytes:cacheBytes:appSupportBytes:totalBytes:)`
 * (StorageProto+Helpers.swift:36-42).
 */
export function makeAppStorageInfo(
  documentsBytes: number,
  cacheBytes: number,
  appSupportBytes: number,
  totalBytes: number,
): AppStorageInfo {
  return AppStorageInfo.fromPartial({
    documentsBytes,
    cacheBytes,
    appSupportBytes,
    totalBytes,
  });
}

// MARK: - StorageInfo

/**
 * Empty `StorageInfo` with default sub-messages populated.
 * Swift parity: `RAStorageInfo.empty` (StorageProto+Helpers.swift:53-61).
 * Returns a fresh value per call (Swift's `static let` is an immutable
 * shared instance; TS objects are mutable, so sharing would be unsafe).
 */
export function emptyStorageInfo(): StorageInfo {
  return StorageInfo.fromPartial({
    app: AppStorageInfo.fromPartial({}),
    device: DeviceStorageInfo.fromPartial({}),
    models: [],
    totalModels: 0,
    totalModelsBytes: 0,
  });
}

/**
 * Sum of `sizeOnDiskBytes` across all per-model rows.
 * Swift parity: `RAStorageInfo.totalModelsSizeBytes`
 * (StorageProto+Helpers.swift:63-65).
 */
export function storageInfoTotalModelsSizeBytes(info: StorageInfo): number {
  return info.models.reduce((total, metrics) => total + metrics.sizeOnDiskBytes, 0);
}

/**
 * App storage breakdown, defaulting when absent.
 * Swift parity: `RAStorageInfo.appStorage` getter
 * (StorageProto+Helpers.swift:67-70). SwiftProtobuf returns a default
 * instance for unset sub-messages; ts-proto models them as optional, so the
 * default instance is materialized here. (The Swift setter is not ported —
 * TS callers assign `info.app` directly.)
 */
export function storageInfoAppStorage(info: StorageInfo): AppStorageInfo {
  return info.app ?? AppStorageInfo.fromPartial({});
}

/**
 * Device storage view, defaulting when absent.
 * Swift parity: `RAStorageInfo.deviceStorage` getter
 * (StorageProto+Helpers.swift:72-75). (Setter not ported — TS callers
 * assign `info.device` directly.)
 */
export function storageInfoDeviceStorage(info: StorageInfo): DeviceStorageInfo {
  return info.device ?? DeviceStorageInfo.fromPartial({});
}

/**
 * Denormalized total model bytes, falling back to summing the rows.
 * Swift parity: `RAStorageInfo.totalModelsSize`
 * (StorageProto+Helpers.swift:77-79).
 */
export function storageInfoTotalModelsSize(info: StorageInfo): number {
  return info.totalModelsBytes > 0 ? info.totalModelsBytes : storageInfoTotalModelsSizeBytes(info);
}

/**
 * Number of stored models.
 * Swift parity: `RAStorageInfo.modelCount` (StorageProto+Helpers.swift:81).
 */
export function storageInfoModelCount(info: StorageInfo): number {
  return info.models.length;
}

// MARK: - ModelStorageMetrics

/**
 * Build a `ModelStorageMetrics` row.
 * Swift parity: `RAModelStorageMetrics.init(modelID:sizeOnDiskBytes:lastUsedMs:)`
 * (StorageProto+Helpers.swift:97-102).
 */
export function makeModelStorageMetrics(
  modelId: string,
  sizeOnDiskBytes: number,
  lastUsedMs?: number,
): ModelStorageMetrics {
  return ModelStorageMetrics.fromPartial({
    modelId,
    sizeOnDiskBytes,
    lastUsedMs,
  });
}

// MARK: - StorageAvailability

/**
 * Build a `StorageAvailability` result.
 * Swift parity: `RAStorageAvailability.make(isAvailable:requiredBytes:availableBytes:recommendation:)`
 * (StorageProto+Helpers.swift:139-151).
 */
export function makeStorageAvailability(
  isAvailable: boolean,
  requiredBytes: number,
  availableBytes: number,
  recommendation?: string,
): StorageAvailability {
  return StorageAvailability.fromPartial({
    isAvailable,
    requiredBytes,
    availableBytes,
    recommendation,
  });
}
