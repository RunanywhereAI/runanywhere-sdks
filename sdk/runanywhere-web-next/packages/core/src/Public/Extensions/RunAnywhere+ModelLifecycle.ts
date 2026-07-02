import {
  type CurrentModelRequest as ProtoCurrentModelRequest,
  type CurrentModelResult as ProtoCurrentModelResult,
  type ModelLoadRequest as ProtoModelLoadRequest,
  type ModelLoadResult as ProtoModelLoadResult,
  type ModelUnloadRequest as ProtoModelUnloadRequest,
  type ModelUnloadResult as ProtoModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import {
  type ComponentLifecycleSnapshot as ProtoComponentLifecycleSnapshot,
  type SDKComponent as ProtoSDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import { DownloadAdapter } from '../../Adapters/DownloadAdapter';
import { runDownload, type DownloadProgressHandler } from '../../Adapters/DownloadRunner';
import { ModelLifecycleAdapter } from '../../Adapters/ModelLifecycleAdapter';
import { ModelRegistryAdapter } from '../../Adapters/ModelRegistryAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { DownloadedModelStore } from '../../runtime/OpfsModelStore';
import { RunAnywhereSDK } from '../RunAnywhere';

export type { DownloadProgressHandler };

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    loadModel(request: ProtoModelLoadRequest): Promise<ProtoModelLoadResult | null>;
    downloadAndLoad(
      request: ProtoModelLoadRequest,
      onProgress?: DownloadProgressHandler,
    ): Promise<ProtoModelLoadResult | null>;
    unloadModel(request: ProtoModelUnloadRequest): Promise<ProtoModelUnloadResult | null>;
    currentModel(request?: ProtoCurrentModelRequest): Promise<ProtoCurrentModelResult | null>;
    componentSnapshot(component: ProtoSDKComponent): Promise<ProtoComponentLifecycleSnapshot | null>;
    resetLifecycle(): Promise<void>;
  }
}

function lifecycle(): ModelLifecycleAdapter {
  const adapter = ModelLifecycleAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('ModelLifecycle');
  return adapter;
}

RunAnywhereSDK.prototype.loadModel = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  const adapter = ModelLifecycleAdapter.tryDefaultForFramework(request.framework);
  if (!adapter) throw SDKException.backendNotAvailable('ModelLifecycle');
  return adapter.load(request);
};

RunAnywhereSDK.prototype.downloadAndLoad = async function (
  this: RunAnywhereSDK,
  request,
  onProgress,
) {
  this.ensureInitialized();

  const loader = ModelLifecycleAdapter.tryDefaultForFramework(request.framework);
  if (!loader) throw SDKException.backendNotAvailable('ModelLifecycle');

  const loadRequest = { ...request, validateAvailability: false };
  const existing = await loader.load(loadRequest);
  if (existing?.success) return existing;

  const downloader = DownloadAdapter.tryDefaultForFramework(request.framework);
  if (!downloader) throw SDKException.backendNotAvailable('Download');

  const model = (await ModelRegistryAdapter.tryDefault()?.get(request.modelId)) ?? undefined;
  const files = await runDownload(downloader, request.modelId, model, onProgress);
  await DownloadedModelStore.mark(request.modelId, files);

  const loaded = await loader.load(loadRequest);
  if (!loaded?.success) {
    throw SDKException.processingFailed(loaded?.errorMessage || 'model load failed after download');
  }
  return loaded;
};

RunAnywhereSDK.prototype.unloadModel = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lifecycle().unload(request);
};

RunAnywhereSDK.prototype.currentModel = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lifecycle().currentModel(request);
};

RunAnywhereSDK.prototype.componentSnapshot = function (this: RunAnywhereSDK, component) {
  this.ensureInitialized();
  return lifecycle().componentSnapshot(component);
};

RunAnywhereSDK.prototype.resetLifecycle = function (this: RunAnywhereSDK) {
  return lifecycle().reset();
};
