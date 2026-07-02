import {
  type ModelImportRequest as ProtoModelImportRequest,
  type ModelImportResult as ProtoModelImportResult,
  type ModelInfo as ProtoModelInfo,
  type ModelInfoList as ProtoModelInfoList,
  type ModelQuery as ProtoModelQuery,
} from '@runanywhere/proto-ts/model_types';
import { ModelRegistryAdapter, type RefreshOptions } from '../../Adapters/ModelRegistryAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    registerModel(model: ProtoModelInfo): Promise<boolean>;
    updateModel(model: ProtoModelInfo): Promise<boolean>;
    getModel(modelId: string): Promise<ProtoModelInfo | null>;
    listModels(): Promise<ProtoModelInfoList | null>;
    queryModels(query: ProtoModelQuery): Promise<ProtoModelInfoList | null>;
    listDownloadedModels(): Promise<ProtoModelInfoList | null>;
    removeModel(modelId: string): Promise<boolean>;
    importModel(request: ProtoModelImportRequest): Promise<ProtoModelImportResult | null>;
    refreshRegistry(options?: RefreshOptions): Promise<boolean>;
  }
}

function registry(): ModelRegistryAdapter {
  const adapter = ModelRegistryAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('ModelRegistry');
  return adapter;
}

RunAnywhereSDK.prototype.registerModel = function (this: RunAnywhereSDK, model) {
  this.ensureInitialized();
  return registry().register(model);
};

RunAnywhereSDK.prototype.updateModel = function (this: RunAnywhereSDK, model) {
  this.ensureInitialized();
  return registry().update(model);
};

RunAnywhereSDK.prototype.getModel = function (this: RunAnywhereSDK, modelId) {
  this.ensureInitialized();
  return registry().get(modelId);
};

RunAnywhereSDK.prototype.listModels = function (this: RunAnywhereSDK) {
  this.ensureInitialized();
  return registry().list();
};

RunAnywhereSDK.prototype.queryModels = function (this: RunAnywhereSDK, query) {
  this.ensureInitialized();
  return registry().query(query);
};

RunAnywhereSDK.prototype.listDownloadedModels = function (this: RunAnywhereSDK) {
  this.ensureInitialized();
  return registry().listDownloaded();
};

RunAnywhereSDK.prototype.removeModel = function (this: RunAnywhereSDK, modelId) {
  this.ensureInitialized();
  return registry().remove(modelId);
};

RunAnywhereSDK.prototype.importModel = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return registry().importModel(request);
};

RunAnywhereSDK.prototype.refreshRegistry = function (this: RunAnywhereSDK, options) {
  this.ensureInitialized();
  return registry().refresh(options);
};
