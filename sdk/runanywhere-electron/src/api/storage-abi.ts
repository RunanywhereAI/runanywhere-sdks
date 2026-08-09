// storage-abi.ts — typed access to the commons storage analyzer.
//
// Unlike the inference surfaces, these four entry points take a handle built
// from a `rac_storage_callbacks_t`. The addon owns that handle and its
// filesystem callbacks (`native/download_bridge.cpp`), so the request here
// carries no handle and the SDK never walks a directory itself.
//
// Deletion is deliberately a two-party affair: commons decides which paths are
// safe to remove and reconciles the registry, and only the adapter's
// `delete_path` callback removes bytes. `allowPlatformDelete` is the opt-in that
// lets it run at all; without it commons reports the model as skipped.

import {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';

/** The commons storage analyzer: what is on disk, what fits, and what to remove. */
export class StorageAbi {
  constructor(private readonly backend: RaBackend) {}

  info(request: StorageInfoRequest): Promise<StorageInfoResult> {
    return invokeProto(
      (bytes) => this.backend.storageInfoProto(bytes),
      StorageInfoRequest,
      request,
      StorageInfoResult
    );
  }

  availability(request: StorageAvailabilityRequest): Promise<StorageAvailabilityResult> {
    return invokeProto(
      (bytes) => this.backend.storageAvailabilityProto(bytes),
      StorageAvailabilityRequest,
      request,
      StorageAvailabilityResult
    );
  }

  deletePlan(request: StorageDeletePlanRequest): Promise<StorageDeletePlan> {
    return invokeProto(
      (bytes) => this.backend.storageDeletePlanProto(bytes),
      StorageDeletePlanRequest,
      request,
      StorageDeletePlan
    );
  }

  delete(request: StorageDeleteRequest): Promise<StorageDeleteResult> {
    return invokeProto(
      (bytes) => this.backend.storageDeleteProto(bytes),
      StorageDeleteRequest,
      request,
      StorageDeleteResult
    );
  }
}

export { StorageDeletePlan, StorageDeleteResult, StorageInfoResult };
export type { StorageAvailabilityResult };
