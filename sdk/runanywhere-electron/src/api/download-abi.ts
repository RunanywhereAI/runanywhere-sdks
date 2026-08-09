// download-abi.ts — typed access to the commons download orchestrator.
//
// Every task lives in commons, keyed by model id and task id; nothing here holds
// a handle. Two shapes are worth knowing before reading the callers:
//
// Progress is a process-wide callback, not a per-call stream. commons emits one
// `DownloadProgress` for every task through the single pointer
// `rac_download_set_progress_proto_callback` installs, so the subscription is
// opened once and each consumer filters by task id.
//
// There is no resume verb. `rac_download_resume_proto` is a retired stub
// (`download_orchestrator.cpp:3619`) because the IDL deleted
// DownloadResumeRequest: starting a download IS resuming it, and a start for a
// model already in flight coalesces onto the running task rather than spawning
// a second worker.

import {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadState,
  DownloadSubscribeRequest,
} from '../proto/download_service';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';

/** A task commons will not move any further on its own. */
export function isTerminalState(state: DownloadState): boolean {
  return (
    state === DownloadState.DOWNLOAD_STATE_COMPLETED ||
    state === DownloadState.DOWNLOAD_STATE_FAILED ||
    state === DownloadState.DOWNLOAD_STATE_CANCELLED
  );
}

/** Bytes done over bytes expected, clamped to 0..100 and 0 when the total is unknown. */
export function percentOf(progress: DownloadProgress): number {
  if (progress.totalBytes > 0) {
    const pct = (100 * progress.bytesDownloaded) / progress.totalBytes;
    return Math.max(0, Math.min(100, Math.round(pct)));
  }
  return Math.max(0, Math.min(100, Math.round(100 * (progress.overallProgress || 0))));
}

/** The commons download workflow: plan, start, cancel, poll, and purge. */
export class DownloadAbi {
  constructor(private readonly backend: RaBackend) {}

  plan(request: DownloadPlanRequest): Promise<DownloadPlanResult> {
    return invokeProto(
      (bytes) => this.backend.downloadPlan(bytes),
      DownloadPlanRequest,
      request,
      DownloadPlanResult
    );
  }

  start(request: DownloadStartRequest): Promise<DownloadStartResult> {
    return invokeProto(
      (bytes) => this.backend.downloadStart(bytes),
      DownloadStartRequest,
      request,
      DownloadStartResult
    );
  }

  cancel(request: DownloadCancelRequest): Promise<DownloadCancelResult> {
    return invokeProto(
      (bytes) => this.backend.downloadCancel(bytes),
      DownloadCancelRequest,
      request,
      DownloadCancelResult
    );
  }

  poll(request: DownloadSubscribeRequest): Promise<DownloadProgress> {
    return invokeProto(
      (bytes) => this.backend.downloadProgress(bytes),
      DownloadSubscribeRequest,
      request,
      DownloadProgress
    );
  }

  /**
   * Release the task slots of finished downloads. commons keeps a terminal task
   * alive so a late cancel or poll can still resolve it by id, so without this
   * the map grows once per download for the life of the process.
   */
  cleanup(): Promise<number> {
    return this.backend.downloadCleanup();
  }
}

export { DownloadPlanResult, DownloadProgress, DownloadState, DownloadStartResult };
export type { DownloadCancelResult };
