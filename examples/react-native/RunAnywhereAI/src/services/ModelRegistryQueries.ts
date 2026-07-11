import { RunAnywhere } from '@runanywhere/core';
import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
import { filterVisibleNativeNpuCatalog } from './NpuModelCatalog';

/** Native registry query with the accepted QHexRT catalog boundary applied. */
export async function listVisibleCatalogModels(
  registeredNpuIds?: ReadonlySet<string>
): Promise<ModelInfo[]> {
  const models = (await RunAnywhere.listModels()).models?.models ?? [];
  return filterVisibleNativeNpuCatalog(models, registeredNpuIds);
}

/**
 * Storage-management inventory. Keep stale/unaccepted QHexRT downloads visible
 * here so users can remove orphaned on-disk models after a device/catalog change.
 */
export async function listDownloadedCatalogModels(): Promise<ModelInfo[]> {
  return (await RunAnywhere.downloadedModels()).models?.models ?? [];
}
