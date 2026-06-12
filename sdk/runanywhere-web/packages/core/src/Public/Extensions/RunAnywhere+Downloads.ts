import type {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadResumeRequest,
  DownloadResumeResult,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';
import {
  DownloadAdapter,
  type ProtoDownloadProgressHandler,
} from '../../Adapters/DownloadAdapter';

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

  resume(request: DownloadResumeRequest): DownloadResumeResult | null {
    return requireAdapter().resume(request);
  },

  poll(request: DownloadSubscribeRequest): DownloadProgress | null {
    return requireAdapter().poll(request);
  },

  setProgressHandler(handler: ProtoDownloadProgressHandler | null): boolean {
    return requireAdapter().setProgressHandler(handler);
  },
};
