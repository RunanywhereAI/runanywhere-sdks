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
} from '@runanywhere/proto-ts/download_service';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';
import type { DownloadProgressSnapshot } from './types';

/** A task commons will not move any further on its own. */
export function isTerminalState(state: DownloadState): boolean {
  return (
    state === DownloadState.DOWNLOAD_STATE_COMPLETED ||
    state === DownloadState.DOWNLOAD_STATE_FAILED ||
    state === DownloadState.DOWNLOAD_STATE_CANCELLED
  );
}

/**
 * Canonical 0..100 via `rac_download_progress_percent` (overall preferred when
 * finite and in [0,1]; else bytes ratio; else 0). Never re-derive locally.
 */
export async function percentOf(
  progress: DownloadProgress,
  percentFn: (
    overall: number,
    downloaded: number,
    total: number
  ) => number | Promise<number>
): Promise<number> {
  return percentFn(
    progress.overallProgress,
    Number(progress.bytesDownloaded),
    Number(progress.totalBytes)
  );
}

/**
 * One `DownloadProgress` as the public snapshot, carrying every field commons
 * measured. `percent` / `fraction` come from {@link percentOf} (commons), not a
 * local bytes-ratio multiply.
 *
 * The normalizations for throughput / ETA are all "absent means unknown":
 * commons writes 0 into `bytes_per_second` before it has a sample and leaves
 * `eta_seconds` unset (or negative) when it cannot project one. Mapping those
 * to absent lets a caller show nothing instead of "0 B/s · 0s left" while the
 * connection is still opening.
 */
export async function toProgressSnapshot(
  progress: DownloadProgress,
  operationId: string,
  sequence: number,
  percentFn: (
    overall: number,
    downloaded: number,
    total: number
  ) => number | Promise<number>
): Promise<DownloadProgressSnapshot> {
  const percent = await percentOf(progress, percentFn);
  const sizeKnown = progress.totalBytes > 0 || progress.overallProgress > 0;
  const fraction = sizeKnown || percent > 0 ? Math.min(Math.max(percent / 100, 0), 1) : undefined;
  return {
    operationId,
    sequence,
    bytesDone: Number(progress.bytesDownloaded),
    bytesTotal: Number(progress.totalBytes),
    file: progress.currentFileName || undefined,
    bytesPerSecond: progress.bytesPerSecond > 0 ? progress.bytesPerSecond : undefined,
    etaSeconds:
      progress.etaSeconds !== undefined && progress.etaSeconds >= 0
        ? Number(progress.etaSeconds)
        : undefined,
    retryAttempt: progress.retryAttempt,
    currentFileIndex: progress.currentFileIndex,
    totalFiles: Math.max(progress.totalFiles, 1),
    fraction,
    percent: fraction === undefined ? undefined : percent,
    isIndeterminate: fraction === undefined,
  };
}

/** The commons download workflow: plan, start, cancel, poll, and purge. */
export class DownloadAbi {
  constructor(private readonly backend: RaBackend) {}

  /** Percent helper bound to this backend's commons ABI (sync or RPC). */
  percent(progress: DownloadProgress): Promise<number> {
    return percentOf(progress, (o, d, t) => this.backend.downloadProgressPercent(o, d, t));
  }

  /** Public progress snapshot with commons-owned percent. */
  snapshot(
    progress: DownloadProgress,
    operationId: string,
    sequence: number
  ): Promise<DownloadProgressSnapshot> {
    return toProgressSnapshot(progress, operationId, sequence, (o, d, t) =>
      this.backend.downloadProgressPercent(o, d, t)
    );
  }

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
