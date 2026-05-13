/**
 * helpers/storage
 *
 * Swift-parity conveniences for generated storage proto types.
 */

import {
  AppStorageInfo,
  DeviceStorageInfo,
  ModelStorageMetrics,
  StorageAvailability,
  StorageInfo,
  StoredModel,
  type AppStorageInfo as AppStorageInfoType,
  type DeviceStorageInfo as DeviceStorageInfoType,
  type ModelStorageMetrics as ModelStorageMetricsType,
  type StorageAvailability as StorageAvailabilityType,
  type StorageInfo as StorageInfoType,
  type StoredModel as StoredModelType,
} from '@runanywhere/proto-ts/storage_types';

export {
  AppStorageInfo,
  DeviceStorageInfo,
  ModelStorageMetrics,
  StorageAvailability,
  StorageInfo,
  StoredModel,
  type AppStorageInfo as AppStorageInfoType,
  type DeviceStorageInfo as DeviceStorageInfoType,
  type ModelStorageMetrics as ModelStorageMetricsType,
  type StorageAvailability as StorageAvailabilityType,
  type StorageInfo as StorageInfoType,
  type StoredModel as StoredModelType,
} from '@runanywhere/proto-ts/storage_types';

export function makeDeviceStorageInfo(
  totalBytes: number,
  freeBytes: number,
  usedBytes: number
): DeviceStorageInfoType {
  return DeviceStorageInfo.create({
    totalBytes,
    freeBytes,
    usedBytes,
    usedPercent: totalBytes > 0 ? (usedBytes / totalBytes) * 100 : 0,
  });
}

export function deviceStorageUsagePercentage(
  info: DeviceStorageInfoType
): number {
  return info.totalBytes > 0 ? (info.usedBytes / info.totalBytes) * 100 : 0;
}

export function makeAppStorageInfo(
  documentsBytes: number,
  cacheBytes: number,
  appSupportBytes: number,
  totalBytes: number
): AppStorageInfoType {
  return AppStorageInfo.create({
    documentsBytes,
    cacheBytes,
    appSupportBytes,
    totalBytes,
  });
}

export function emptyStorageInfo(): StorageInfoType {
  return StorageInfo.create({
    app: AppStorageInfo.create(),
    device: DeviceStorageInfo.create(),
    models: [],
    totalModels: 0,
    totalModelsBytes: 0,
  });
}

export function storageInfoTotalModelsSizeBytes(info: StorageInfoType): number {
  return info.models.reduce((total, model) => total + model.sizeOnDiskBytes, 0);
}

export function storageInfoTotalModelsSize(info: StorageInfoType): number {
  return info.totalModelsBytes > 0
    ? info.totalModelsBytes
    : storageInfoTotalModelsSizeBytes(info);
}

export function storageInfoModelCount(info: StorageInfoType): number {
  return info.models.length;
}

export function storageInfoStoredModels(info: StorageInfoType): StoredModelType[] {
  return info.models.map((metrics) =>
    StoredModel.create({
      modelId: metrics.modelId,
      name: metrics.modelId,
      sizeBytes: metrics.sizeOnDiskBytes,
    })
  );
}

export function makeModelStorageMetrics(
  modelId: string,
  sizeOnDiskBytes: number,
  lastUsedMs?: number
): ModelStorageMetricsType {
  return ModelStorageMetrics.create({
    modelId,
    sizeOnDiskBytes,
    lastUsedMs,
  });
}

export function storedModelId(model: StoredModelType): string {
  return model.modelId;
}

export function storedModelSize(model: StoredModelType): number {
  return model.sizeBytes;
}

export function storedModelPath(model: StoredModelType): string {
  return model.localPath.length > 0 ? model.localPath : '/unknown';
}

export function storedModelCreatedDate(model: StoredModelType): Date {
  return new Date(model.downloadedAtMs ?? 0);
}

export function makeStorageAvailability(
  isAvailable: boolean,
  requiredBytes: number,
  availableBytes: number,
  recommendation?: string
): StorageAvailabilityType {
  return StorageAvailability.create({
    isAvailable,
    requiredBytes,
    availableBytes,
    recommendation,
  });
}
