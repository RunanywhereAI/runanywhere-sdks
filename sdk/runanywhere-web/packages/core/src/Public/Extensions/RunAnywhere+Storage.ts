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

import { OPFSStorage } from '../../Infrastructure/OPFSStorage';
import { LocalFileStorage } from '../../Infrastructure/LocalFileStorage';
import { ModelManager } from '../../Infrastructure/ModelManager';
import { SDKLogger } from '../../Foundation/SDKLogger';
import type { StorageInfo } from '../../types/models';
import type { StorageProviderId } from '../../Infrastructure/StorageProvider';

const logger = new SDKLogger('Storage');

/**
 * Aggregate storage info — extends the Web SDK `StorageInfo` shape with the
 * active backend identifier so apps can render "Stored on disk" /
 * "Stored in browser storage" hints without duplicating the resolution logic.
 */
export interface StorageInfoExtended extends StorageInfo {
  /** Stable identifier for the active backend ('fsAccess' | 'opfs' | 'memory'). */
  backend: StorageProviderId;
  /** Whether the backend persists across page reloads. */
  isPersistent: boolean;
  /** Whether the user explicitly picked a directory (true only for fsAccess). */
  isUserChosen: boolean;
}

/**
 * Free-function namespace mirroring Swift's `RunAnywhere.Storage` extension.
 */
export const Storage = {
  /**
   * Gather aggregate storage info — total quota, used bytes, models path,
   * and active backend identifier. Uses `navigator.storage.estimate()` when
   * available; falls back to zeroes when unsupported.
   */
  async info(): Promise<StorageInfoExtended> {
    const backend: StorageProviderId =
      LocalFileStorage.isSupported && LocalFileStorage.storedDirectoryName
        ? 'fsAccess'
        : OPFSStorage.isSupported
          ? 'opfs'
          : 'memory';

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
      totalSpace,
      usedSpace,
      freeSpace,
      modelsPath: 'models',
      backend,
      isPersistent: backend !== 'memory',
      isUserChosen: backend === 'fsAccess',
    };
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
