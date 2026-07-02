import {
  ModelImportRequest,
  ModelImportResult,
  ModelInfo,
  ModelInfoList,
  ModelQuery,
  ModelRegistryRefreshRequest,
  ModelRegistryRefreshResult,
  type ModelImportRequest as ProtoModelImportRequest,
  type ModelImportResult as ProtoModelImportResult,
  type ModelInfo as ProtoModelInfo,
  type ModelInfoList as ProtoModelInfoList,
  type ModelQuery as ProtoModelQuery,
} from '@runanywhere/proto-ts/model_types';
import { allClients, clientFor, type Capability } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const FREE = 'rac_model_registry_proto_free';

export interface RefreshOptions {
  includeRemoteCatalog?: boolean;
  rescanLocal?: boolean;
  pruneOrphans?: boolean;
}

export class ModelRegistryAdapter {
  static tryDefault(): ModelRegistryAdapter | null {
    const client = clientFor('commons');
    return client ? new ModelRegistryAdapter(client) : null;
  }

  // A model downloaded through a specific backend worker only has its
  // local_path in that worker's registry (self-heal is per-worker). Bind the
  // adapter to that worker to read it back.
  static tryDefaultFor(capability: Capability): ModelRegistryAdapter | null {
    const client = clientFor(capability);
    return client ? new ModelRegistryAdapter(client) : null;
  }

  private constructor(private readonly client: WorkerProtoClient) {}

  async get(modelId: string): Promise<ProtoModelInfo | null> {
    const handle = await this.registry(this.client);
    if (!handle) return null;
    return this.client.callProto(
      'rac_model_registry_get_proto',
      [Arg.num(handle), Arg.string(modelId), Arg.outBytesSize(FREE)],
      ModelInfo,
    );
  }

  async list(): Promise<ProtoModelInfoList | null> {
    const handle = await this.registry(this.client);
    if (!handle) return null;
    return this.client.callProto(
      'rac_model_registry_list_proto',
      [Arg.num(handle), Arg.outBytesSize(FREE)],
      ModelInfoList,
    );
  }

  async query(query: ProtoModelQuery): Promise<ProtoModelInfoList | null> {
    const handle = await this.registry(this.client);
    if (!handle) return null;
    return this.client.callProto(
      'rac_model_registry_query_proto',
      [Arg.num(handle), Arg.bytes(ModelQuery.encode(query).finish()), Arg.outBytesSize(FREE)],
      ModelInfoList,
    );
  }

  async listDownloaded(): Promise<ProtoModelInfoList | null> {
    const handle = await this.registry(this.client);
    if (!handle) return null;
    return this.client.callProto(
      'rac_model_registry_list_downloaded_proto',
      [Arg.num(handle), Arg.outBytesSize(FREE)],
      ModelInfoList,
    );
  }

  async refresh(options: RefreshOptions = {}): Promise<boolean> {
    const handle = await this.registry(this.client);
    if (!handle) return false;
    const req = ModelRegistryRefreshRequest.encode({
      includeRemoteCatalog: options.includeRemoteCatalog ?? false,
      rescanLocal: options.rescanLocal ?? false,
      pruneOrphans: options.pruneOrphans ?? false,
      catalogUri: '',
      forceRefresh: false,
      includeDownloadedState: options.rescanLocal ?? false,
    }).finish();
    const result = await this.client.callProto(
      'rac_model_registry_refresh_proto',
      [Arg.num(handle), Arg.bytes(req), Arg.outBytesSize(FREE)],
      ModelRegistryRefreshResult,
    );
    return result?.success ?? false;
  }

  async register(model: ProtoModelInfo): Promise<boolean> {
    const bytes = ModelInfo.encode(model).finish();
    return this.broadcastWrite((client, handle) =>
      client.callRc('rac_model_registry_register_proto', [Arg.num(handle), Arg.bytes(bytes)]),
    );
  }

  async update(model: ProtoModelInfo): Promise<boolean> {
    const bytes = ModelInfo.encode(model).finish();
    return this.broadcastWrite((client, handle) =>
      client.callRc('rac_model_registry_update_proto', [Arg.num(handle), Arg.bytes(bytes)]),
    );
  }

  async remove(modelId: string): Promise<boolean> {
    return this.broadcastWrite((client, handle) =>
      client.callRc('rac_model_registry_remove_proto', [Arg.num(handle), Arg.string(modelId)]),
    );
  }

  async importModel(request: ProtoModelImportRequest): Promise<ProtoModelImportResult | null> {
    const bytes = ModelImportRequest.encode(request).finish();
    let primaryResult: ProtoModelImportResult | null = null;
    for (const client of allClients()) {
      const handle = await this.registry(client);
      if (!handle) continue;
      const result = await client.callProto(
        'rac_model_registry_import_proto',
        [Arg.num(handle), Arg.bytes(bytes), Arg.outProto()],
        ModelImportResult,
      );
      if (client === this.client) primaryResult = result;
    }
    return primaryResult;
  }

  private async broadcastWrite(op: (client: WorkerProtoClient, handle: number) => Promise<number>): Promise<boolean> {
    let primaryOk = false;
    for (const client of allClients()) {
      const handle = await this.registry(client);
      if (!handle) continue;
      const rc = await op(client, handle);
      if (client === this.client) primaryOk = rc === 0;
    }
    return primaryOk;
  }

  private registry(client: WorkerProtoClient): Promise<number> {
    return client.callRc('rac_get_model_registry', []);
  }
}
