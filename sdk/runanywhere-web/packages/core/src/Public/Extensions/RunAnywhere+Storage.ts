/**
 * RunAnywhere+Storage.ts
 *
 * Top-level storage information API — mirrors the Swift / Kotlin / RN
 * `RunAnywhere+Storage` namespace extensions. Aggregates the OPFS / File
 * System Access / memory backends behind a single capability surface.
 *
 * Phase C-prime WEB: closes the gap where the Web SDK had storage logic
 * scattered across `RunAnywhere.ts`, `OPFSStorage.ts`, and
 * `LocalFileStorage.ts` with no single namespace summary.
 *
 * Reference (Swift): `RunAnywhere+Storage.swift`
 *
 * @example
 *   import { Storage } from '@runanywhere/web';
 *   const info = await Storage.info();
 *   console.log(`Storage backend: ${info.backend}, used ${info.usedSpace}b`);
 */

import { ModelManager } from '../../Infrastructure/ModelManager';
import { OPFSStorage } from '../../Infrastructure/OPFSStorage';
import { LocalFileStorage } from '../../Infrastructure/LocalFileStorage';
import { SDKLogger } from '../../Foundation/SDKLogger';
import type { StorageProviderId } from '../../Infrastructure/StorageProvider';
import { StorageAdapter } from '../../Adapters/StorageAdapter';
import type {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';

const logger = new SDKLogger('Storage');

/**
 * Free-function namespace mirroring Swift's `RunAnywhere.Storage` extension.
 */
export const Storage = {
  /**
   * Gather aggregate storage info — total quota, used bytes, models path,
   * and active backend identifier. Uses `navigator.storage.estimate()` when
   * available; falls back to zeroes when unsupported.
   */
  async info(request: StorageInfoRequest = {
    includeDevice: true,
    includeApp: true,
    includeModels: true,
  }): Promise<StorageInfoResult> {
    const protoResult = StorageAdapter.tryDefault()?.info(request);
    if (protoResult) return protoResult;

    let totalSpace = 0;
    let usedSpace = 0;
    try {
      if (typeof navigator !== 'undefined' && navigator.storage?.estimate) {
        const estimate = await navigator.storage.estimate();
        totalSpace = estimate.quota ?? 0;
        usedSpace = estimate.usage ?? 0;
      }
    } catch (err) {
      logger.debug(
        `navigator.storage.estimate() unavailable: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    const freeSpace = Math.max(0, totalSpace - usedSpace);
    return {
      success: true,
      info: {
        app: request.includeApp
          ? {
              documentsBytes: Storage.modelsUsedBytes(),
              cacheBytes: 0,
              appSupportBytes: 0,
              totalBytes: Storage.modelsUsedBytes(),
            }
          : undefined,
        device: request.includeDevice
          ? {
              totalBytes: totalSpace,
              freeBytes: freeSpace,
              usedBytes: usedSpace,
              usedPercent: totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0,
            }
          : undefined,
        models: request.includeModels
          ? ModelManager.getModels().map((model) => ({
              modelId: model.id,
              sizeOnDiskBytes: model.sizeBytes ?? 0,
            }))
          : [],
        totalModels: request.includeModels ? ModelManager.getModels().length : 0,
        totalModelsBytes: request.includeModels ? Storage.modelsUsedBytes() : 0,
      },
      errorMessage: '',
    };
  },

  availability(request: StorageAvailabilityRequest): StorageAvailabilityResult | null {
    return StorageAdapter.tryDefault()?.availability(request) ?? null;
  },

  deletePlan(request: StorageDeletePlanRequest): StorageDeletePlan | null {
    return StorageAdapter.tryDefault()?.deletePlan(request) ?? null;
  },

  delete(request: StorageDeleteRequest): StorageDeleteResult | null {
    return StorageAdapter.tryDefault()?.delete(request) ?? null;
  },

  /**
   * Stable id of the active storage backend ('fsAccess' | 'opfs' | 'memory').
   */
  get backendId(): StorageProviderId {
    if (LocalFileStorage.isSupported && LocalFileStorage.storedDirectoryName) {
      return 'fsAccess';
    }
    if (OPFSStorage.isSupported) return 'opfs';
    return 'memory';
  },

  /** Total disk space used by the SDK's tracked models, in bytes. */
  modelsUsedBytes(): number {
    let total = 0;
    for (const m of ModelManager.getModels()) {
      total += m.sizeBytes ?? 0;
    }
    return total;
  },

  /**
   * Request that the user agent persist the SDK's storage so it isn't
   * evicted under storage pressure. Mirrors Swift's
   * `RunAnywhere.requestPersistentStorage`.
   *
   * Returns whether persistence was granted (always true once granted —
   * subsequent calls may resolve to true without prompting).
   */
  async requestPersistence(): Promise<boolean> {
    try {
      if (typeof navigator !== 'undefined' && navigator.storage?.persist) {
        return await navigator.storage.persist();
      }
    } catch (err) {
      logger.debug(
        `navigator.storage.persist() failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    return false;
  },
};
