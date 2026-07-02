import {
  type DownloadCancelRequest as ProtoDownloadCancelRequest,
  type DownloadCancelResult as ProtoDownloadCancelResult,
  type DownloadPlanRequest as ProtoDownloadPlanRequest,
  type DownloadPlanResult as ProtoDownloadPlanResult,
  type DownloadProgress as ProtoDownloadProgress,
  type DownloadResumeRequest as ProtoDownloadResumeRequest,
  type DownloadResumeResult as ProtoDownloadResumeResult,
  type DownloadStartRequest as ProtoDownloadStartRequest,
  type DownloadStartResult as ProtoDownloadStartResult,
  type DownloadSubscribeRequest as ProtoDownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';
import { type InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { DownloadAdapter, type ProtoDownloadProgressHandler } from '../../Adapters/DownloadAdapter';
import { runDownload, type DownloadProgressHandler } from '../../Adapters/DownloadRunner';
import { ModelRegistryAdapter } from '../../Adapters/ModelRegistryAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { DownloadedModelStore } from '../../runtime/OpfsModelStore';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    planDownload(request: ProtoDownloadPlanRequest): Promise<ProtoDownloadPlanResult | null>;
    startDownload(request: ProtoDownloadStartRequest): Promise<ProtoDownloadStartResult | null>;
    cancelDownload(request: ProtoDownloadCancelRequest): Promise<ProtoDownloadCancelResult | null>;
    resumeDownload(request: ProtoDownloadResumeRequest): Promise<ProtoDownloadResumeResult | null>;
    pollDownload(request: ProtoDownloadSubscribeRequest): Promise<ProtoDownloadProgress | null>;
    onDownloadProgress(handler: ProtoDownloadProgressHandler): () => void;
    downloadModel(
      modelId: string,
      framework?: InferenceFramework,
      onProgress?: DownloadProgressHandler,
    ): Promise<void>;
    isModelDownloaded(modelId: string, framework?: InferenceFramework): Promise<boolean>;
  }
}

function downloads(): DownloadAdapter {
  const adapter = DownloadAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('Download');
  return adapter;
}

RunAnywhereSDK.prototype.planDownload = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return downloads().plan(request);
};

RunAnywhereSDK.prototype.startDownload = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return downloads().start(request);
};

RunAnywhereSDK.prototype.cancelDownload = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return downloads().cancel(request);
};

RunAnywhereSDK.prototype.resumeDownload = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return downloads().resume(request);
};

RunAnywhereSDK.prototype.pollDownload = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return downloads().poll(request);
};

RunAnywhereSDK.prototype.onDownloadProgress = function (this: RunAnywhereSDK, handler) {
  this.ensureInitialized();
  return downloads().setProgressHandler(handler);
};

RunAnywhereSDK.prototype.downloadModel = async function (this: RunAnywhereSDK, modelId, framework, onProgress) {
  this.ensureInitialized();
  const downloader = DownloadAdapter.tryDefaultForFramework(framework);
  if (!downloader) throw SDKException.backendNotAvailable('Download');
  const model = (await ModelRegistryAdapter.tryDefault()?.get(modelId)) ?? undefined;
  const files = await runDownload(downloader, modelId, model, onProgress);
  await DownloadedModelStore.mark(modelId, files);
};

RunAnywhereSDK.prototype.isModelDownloaded = async function (this: RunAnywhereSDK, modelId, framework) {
  this.ensureInitialized();
  const downloader = DownloadAdapter.tryDefaultForFramework(framework);
  if (!downloader) return false;
  const model = (await ModelRegistryAdapter.tryDefault()?.get(modelId)) ?? undefined;
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
  if (!plan || plan.files.length === 0) return false;
  for (const file of plan.files) {
    if ((await DownloadedModelStore.fileSize(file.destinationPath)) <= 0) return false;
  }
  return true;
};
