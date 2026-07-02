import {
  LoRAAdapterConfig,
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  LoraAdapterImportRequest,
  LoraAdapterImportResult,
  LoraCompatibilityResult,
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
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

function emptyLoRAState(): ProtoLoRAState {
  return { loadedAdapters: [], hasActiveAdapters: false, errorCode: 0 };
}

export class LoRAProtoAdapter {
  static tryDefault(): LoRAProtoAdapter | null {
    const client = clientFor('lora') ?? clientFor('llm');
    return client ? new LoRAProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  async register(entry: ProtoLoraAdapterCatalogEntry, registry?: number): Promise<ProtoLoraAdapterCatalogEntry | null> {
    return this.client.callProto(
      'rac_lora_register_proto',
      [Arg.num(await this.registry(registry)), Arg.bytes(LoraAdapterCatalogEntry.encode(entry).finish()), Arg.outProto()],
      LoraAdapterCatalogEntry,
    );
  }

  async listCatalog(request: ProtoLoraAdapterCatalogListRequest, registry?: number): Promise<ProtoLoraAdapterCatalogListResult | null> {
    return this.client.callProto(
      'rac_lora_catalog_list_proto',
      [Arg.num(await this.registry(registry)), Arg.bytes(LoraAdapterCatalogListRequest.encode(request).finish()), Arg.outProto()],
      LoraAdapterCatalogListResult,
    );
  }

  async queryCatalog(query: ProtoLoraAdapterCatalogQuery, registry?: number): Promise<ProtoLoraAdapterCatalogListResult | null> {
    return this.client.callProto(
      'rac_lora_catalog_query_proto',
      [Arg.num(await this.registry(registry)), Arg.bytes(LoraAdapterCatalogQuery.encode(query).finish()), Arg.outProto()],
      LoraAdapterCatalogListResult,
    );
  }

  async getCatalogEntry(request: ProtoLoraAdapterCatalogGetRequest, registry?: number): Promise<ProtoLoraAdapterCatalogGetResult | null> {
    return this.client.callProto(
      'rac_lora_catalog_get_proto',
      [Arg.num(await this.registry(registry)), Arg.bytes(LoraAdapterCatalogGetRequest.encode(request).finish()), Arg.outProto()],
      LoraAdapterCatalogGetResult,
    );
  }

  async markDownloadCompleted(request: ProtoLoraAdapterDownloadCompletedRequest, registry?: number): Promise<ProtoLoraAdapterDownloadCompletedResult | null> {
    return this.client.callProto(
      'rac_lora_catalog_mark_download_completed_proto',
      [Arg.num(await this.registry(registry)), Arg.bytes(LoraAdapterDownloadCompletedRequest.encode(request).finish()), Arg.outProto()],
      LoraAdapterDownloadCompletedResult,
    );
  }

  async importAdapter(request: ProtoLoraAdapterImportRequest, registry?: number): Promise<ProtoLoraAdapterImportResult | null> {
    return this.client.callProto(
      'rac_lora_adapter_import_proto',
      [Arg.num(await this.registry(registry)), Arg.bytes(LoraAdapterImportRequest.encode(request).finish()), Arg.outProto()],
      LoraAdapterImportResult,
    );
  }

  compatibility(config: ProtoLoRAAdapterConfig): Promise<ProtoLoraCompatibilityResult | null> {
    return this.client.callProto(
      'rac_lora_compatibility_proto',
      [Arg.bytes(LoRAAdapterConfig.encode(config).finish()), Arg.outProto()],
      LoraCompatibilityResult,
    );
  }

  apply(request: ProtoLoRAApplyRequest): Promise<ProtoLoRAApplyResult | null> {
    return this.client.callProto(
      'rac_lora_apply_proto',
      [Arg.bytes(LoRAApplyRequest.encode(request).finish()), Arg.outProto()],
      LoRAApplyResult,
    );
  }

  remove(request: ProtoLoRARemoveRequest): Promise<ProtoLoRAState | null> {
    return this.client.callProto(
      'rac_lora_remove_proto',
      [Arg.bytes(LoRARemoveRequest.encode(request).finish()), Arg.outProto()],
      LoRAState,
    );
  }

  list(request: ProtoLoRAState = emptyLoRAState()): Promise<ProtoLoRAState | null> {
    return this.client.callProto(
      'rac_lora_list_proto',
      [Arg.bytes(LoRAState.encode(request).finish()), Arg.outProto()],
      LoRAState,
    );
  }

  state(request: ProtoLoRAState = emptyLoRAState()): Promise<ProtoLoRAState | null> {
    return this.client.callProto(
      'rac_lora_state_proto',
      [Arg.bytes(LoRAState.encode(request).finish()), Arg.outProto()],
      LoRAState,
    );
  }

  private async registry(registry?: number): Promise<number> {
    if (registry && registry > 0) return registry;
    return this.client.callRc('rac_get_lora_registry', []);
  }
}
