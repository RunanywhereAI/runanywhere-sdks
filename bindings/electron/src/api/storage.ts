// storage.ts — the `storage` namespace.
//
// Swift's storage surface is four loose statics on `RunAnywhere`
// (`storageInfo`, `deleteStorage`, `clearCache`, `cleanTempFiles`); this is the
// same capability as one namespace, plus the two analyzer verbs Swift keeps
// internal (`availability`, `deletePlan`) because a desktop Storage pane wants a
// preview before it deletes anything.
//
// Every verb is a pass-through: commons measures, plans, and deletes — the
// analyzer decides which paths are safe to remove and the addon's `delete_path`
// callback is the only thing that removes bytes. Nothing here walks a directory.
//
// `models.state()` answers the two aggregate numbers a dashboard needs
// (`storageUsedBytes` / `storageFreeBytes`) off the same analyzer; this is where
// the per-model breakdown and the delete plan behind those numbers live.

import { SDKException } from '../errors';
import { StorageAbi } from './storage-abi';
import type { RaBackend } from './backend';
import {
  StorageAvailabilityRequest,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageInfoRequest,
} from '@runanywhere/proto-ts/storage_types';
import type {
  DeepPartial,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeleteResult,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';

/** What the storage namespace needs from the facade. */
export interface StorageDeps {
  backend: RaBackend;
  requireReady(): void;
}

/**
 * What is on disk, what would fit, and what it would cost to make room.
 *
 * Every verb hands back the generated result message unchanged: `warnings`,
 * `skippedModelIds`, and `requiresUnload` are what a caller needs to render an
 * honest outcome, and folding them away is how a UI ends up reporting a skipped
 * delete as a success.
 *
 * `error` on those messages is not one thing, so it is not treated as one:
 * commons uses it for a failed *call* on {@link info} and {@link availability}
 * (bad request, no analyzer — there is no payload to read), and for a
 * partial *answer* on {@link deletePlan} and {@link delete}, where it sits
 * beside a fully populated plan or a per-model breakdown of what did and did not
 * go. The first pair therefore throws and the second pair does not.
 */
export interface StorageNamespace {
  /**
   * Device totals, the SDK's own directories, and a per-model breakdown.
   *
   * Defaults to the full picture; pass a request to narrow it (each section
   * costs a directory walk).
   */
  info(request?: DeepPartial<StorageInfoRequest>): Promise<StorageInfoResult>;
  /**
   * Whether `requiredBytes` fit, optionally with a plan for making room
   * (`includeDeletePlan`).
   *
   * "It does not fit" is `availability.isAvailable === false`, not a throw.
   */
  availability(request: DeepPartial<StorageAvailabilityRequest>): Promise<StorageAvailabilityResult>;
  /**
   * Non-destructive: what deleting these models would reclaim, and what it needs
   * first (`requiresUnload` / `requiresPlatformDelete`).
   *
   * When `requiredBytes` cannot be reached, `canReclaimRequiredBytes` is false
   * and `error` says so — with `candidates` still populated, because "here is
   * everything I could free, and it is not enough" is the answer.
   */
  deletePlan(request?: DeepPartial<StorageDeletePlanRequest>): Promise<StorageDeletePlan>;
  /**
   * Execute (or `dryRun`) a deletion.
   *
   * `allowPlatformDelete` is the opt-in commons requires before it will call the
   * adapter's delete callback; without it every model comes back skipped.
   *
   * A batch settles per model: read `deletedModelIds` / `failedModelIds` /
   * `skippedModelIds` and `warnings`. `error` summarizes that any of them was
   * non-empty, so it is returned rather than thrown — throwing would discard the
   * models that did delete.
   */
  delete(request: DeepPartial<StorageDeleteRequest>): Promise<StorageDeleteResult>;
  /** Empty the SDK's cache directory (`{baseDir}/RunAnywhere/Cache`). */
  clearCache(): Promise<void>;
  /** Empty the SDK's temp directory (`{baseDir}/RunAnywhere/Temp`). */
  cleanTempFiles(): Promise<void>;
}

/** Everything an unnarrowed {@link StorageNamespace.info} reports. */
const FULL_INFO: DeepPartial<StorageInfoRequest> = {
  includeDevice: true,
  includeApp: true,
  includeModels: true,
  includeCache: true,
};

export function createStorageNamespace(deps: StorageDeps): StorageNamespace {
  const abi = new StorageAbi(deps.backend);

  return {
    async info(request = FULL_INFO) {
      deps.requireReady();
      const result = await abi.info(StorageInfoRequest.fromPartial(request));
      if (result.error) throw SDKException.fromProto(result.error);
      return result;
    },

    async availability(request) {
      deps.requireReady();
      const result = await abi.availability(StorageAvailabilityRequest.fromPartial(request));
      if (result.error) throw SDKException.fromProto(result.error);
      return result;
    },

    async deletePlan(request = {}) {
      deps.requireReady();
      return abi.deletePlan(StorageDeletePlanRequest.fromPartial(request));
    },

    async delete(request) {
      deps.requireReady();
      return abi.delete(StorageDeleteRequest.fromPartial(request));
    },

    async clearCache() {
      deps.requireReady();
      await deps.backend.clearCache();
    },

    async cleanTempFiles() {
      deps.requireReady();
      await deps.backend.clearTemp();
    },
  };
}
