import { DownloadState, type DownloadProgress as ProtoDownloadProgress } from '@runanywhere/proto-ts/download_service';
import { type ModelInfo as ProtoModelInfo } from '@runanywhere/proto-ts/model_types';
import { SDKException } from '../Foundation/SDKException';
import type { DownloadAdapter } from './DownloadAdapter';

export type DownloadProgressHandler = (progress: ProtoDownloadProgress) => void;

const POLL_INTERVAL_MS = 150;

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export interface DownloadedFile {
  path: string;
  bytes: number;
}

export async function runDownload(
  downloader: DownloadAdapter,
  modelId: string,
  model: ProtoModelInfo | undefined,
  onProgress?: DownloadProgressHandler,
): Promise<DownloadedFile[]> {
  const plan = await downloader.plan({
    modelId,
    model,
    resumeExisting: true,
    availableStorageBytes: 0,
    allowMeteredNetwork: true,
    storageNamespace: '',
    validateExistingBytes: true,
    verifyChecksums: false,
    requiredFreeBytesAfterDownload: 0,
  });
  if (!plan?.canStart) {
    throw SDKException.processingFailed(plan?.errorMessage || 'download plan reports can_start=false');
  }

  const started = await downloader.start({
    modelId,
    plan,
    resume: false,
    resumeToken: '',
    updateRegistryOnCompletion: true,
  });
  if (!started?.accepted || !started.taskId) {
    throw SDKException.processingFailed(started?.errorMessage || 'download orchestrator rejected start');
  }

  const files: DownloadedFile[] = plan.files.map((f) => ({
    path: f.destinationPath,
    bytes: f.expectedBytes,
  }));

  const subscribe = { modelId, taskId: started.taskId };
  for (;;) {
    const progress = await downloader.poll(subscribe);
    if (!progress) throw SDKException.processingFailed('download progress poll failed');
    onProgress?.(progress);
    if (progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED) return files;
    if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
      throw SDKException.processingFailed(progress.errorMessage || 'download failed');
    }
    if (progress.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
      throw SDKException.processingFailed('download cancelled');
    }
    await delay(POLL_INTERVAL_MS);
  }
}
