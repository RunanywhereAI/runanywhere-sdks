import type {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';
import {
  DownloadAdapter,
  type ProtoDownloadProgressHandler,
} from '../../Adapters/DownloadAdapter.js';

function requireAdapter(): DownloadAdapter {
  const adapter = DownloadAdapter.tryDefault();
  if (!adapter) {
    throw new Error('RunAnywhere download proto adapter is not installed');
  }
  return adapter;
}

export const Downloads = {
  plan(request: DownloadPlanRequest): DownloadPlanResult | null {
    return requireAdapter().plan(request);
  },

  start(request: DownloadStartRequest): DownloadStartResult | null {
    return requireAdapter().start(request);
  },

  cancel(request: DownloadCancelRequest): DownloadCancelResult | null {
    return requireAdapter().cancel(request);
  },

  poll(request: DownloadSubscribeRequest): DownloadProgress | null {
    return requireAdapter().poll(request);
  },

  setProgressHandler(handler: ProtoDownloadProgressHandler | null): boolean {
    return requireAdapter().setProgressHandler(handler);
  },
};
