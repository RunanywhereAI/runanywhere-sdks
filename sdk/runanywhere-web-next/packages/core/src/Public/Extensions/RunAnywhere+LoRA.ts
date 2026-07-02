import {
  type LoRAAdapterConfig as ProtoLoRAAdapterConfig,
  type LoRAApplyRequest as ProtoLoRAApplyRequest,
  type LoRAApplyResult as ProtoLoRAApplyResult,
  type LoRARemoveRequest as ProtoLoRARemoveRequest,
  type LoRAState as ProtoLoRAState,
  type LoraAdapterCatalogEntry as ProtoLoraAdapterCatalogEntry,
  type LoraAdapterCatalogGetRequest as ProtoLoraAdapterCatalogGetRequest,
  type LoraAdapterCatalogGetResult as ProtoLoraAdapterCatalogGetResult,
  type LoraAdapterCatalogListRequest as ProtoLoraAdapterCatalogListRequest,
  type LoraAdapterCatalogListResult as ProtoLoraAdapterCatalogListResult,
  type LoraAdapterCatalogQuery as ProtoLoraAdapterCatalogQuery,
  type LoraAdapterDownloadCompletedRequest as ProtoLoraAdapterDownloadCompletedRequest,
  type LoraAdapterDownloadCompletedResult as ProtoLoraAdapterDownloadCompletedResult,
  type LoraAdapterImportRequest as ProtoLoraAdapterImportRequest,
  type LoraAdapterImportResult as ProtoLoraAdapterImportResult,
  type LoraCompatibilityResult as ProtoLoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';
import { LoRAProtoAdapter } from '../../Adapters/LoRAProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    applyLoRA(request: ProtoLoRAApplyRequest): Promise<ProtoLoRAApplyResult | null>;
    removeLoRA(request: ProtoLoRARemoveRequest): Promise<ProtoLoRAState | null>;
    listLoRA(request?: ProtoLoRAState): Promise<ProtoLoRAState | null>;
    loraState(request?: ProtoLoRAState): Promise<ProtoLoRAState | null>;
    loraCompatibility(config: ProtoLoRAAdapterConfig): Promise<ProtoLoraCompatibilityResult | null>;
    registerLoRA(entry: ProtoLoraAdapterCatalogEntry): Promise<ProtoLoraAdapterCatalogEntry | null>;
    listLoRACatalog(request: ProtoLoraAdapterCatalogListRequest): Promise<ProtoLoraAdapterCatalogListResult | null>;
    queryLoRACatalog(query: ProtoLoraAdapterCatalogQuery): Promise<ProtoLoraAdapterCatalogListResult | null>;
    getLoRACatalogEntry(request: ProtoLoraAdapterCatalogGetRequest): Promise<ProtoLoraAdapterCatalogGetResult | null>;
    markLoRADownloadCompleted(request: ProtoLoraAdapterDownloadCompletedRequest): Promise<ProtoLoraAdapterDownloadCompletedResult | null>;
    importLoRAAdapter(request: ProtoLoraAdapterImportRequest): Promise<ProtoLoraAdapterImportResult | null>;
  }
}

function lora(): LoRAProtoAdapter {
  const adapter = LoRAProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('LoRA');
  return adapter;
}

RunAnywhereSDK.prototype.applyLoRA = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lora().apply(request);
};

RunAnywhereSDK.prototype.removeLoRA = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lora().remove(request);
};

RunAnywhereSDK.prototype.listLoRA = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return request ? lora().list(request) : lora().list();
};

RunAnywhereSDK.prototype.loraState = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return request ? lora().state(request) : lora().state();
};

RunAnywhereSDK.prototype.loraCompatibility = function (this: RunAnywhereSDK, config) {
  this.ensureInitialized();
  return lora().compatibility(config);
};

RunAnywhereSDK.prototype.registerLoRA = function (this: RunAnywhereSDK, entry) {
  this.ensureInitialized();
  return lora().register(entry);
};

RunAnywhereSDK.prototype.listLoRACatalog = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lora().listCatalog(request);
};

RunAnywhereSDK.prototype.queryLoRACatalog = function (this: RunAnywhereSDK, query) {
  this.ensureInitialized();
  return lora().queryCatalog(query);
};

RunAnywhereSDK.prototype.getLoRACatalogEntry = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lora().getCatalogEntry(request);
};

RunAnywhereSDK.prototype.markLoRADownloadCompleted = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lora().markDownloadCompleted(request);
};

RunAnywhereSDK.prototype.importLoRAAdapter = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return lora().importAdapter(request);
};
