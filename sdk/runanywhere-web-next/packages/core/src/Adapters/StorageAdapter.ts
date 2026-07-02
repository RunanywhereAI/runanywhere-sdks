import {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
  type StorageAvailabilityRequest as ProtoStorageAvailabilityRequest,
  type StorageAvailabilityResult as ProtoStorageAvailabilityResult,
  type StorageDeletePlan as ProtoStorageDeletePlan,
  type StorageDeletePlanRequest as ProtoStorageDeletePlanRequest,
  type StorageDeleteRequest as ProtoStorageDeleteRequest,
  type StorageDeleteResult as ProtoStorageDeleteResult,
  type StorageInfoRequest as ProtoStorageInfoRequest,
  type StorageInfoResult as ProtoStorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class StorageAdapter {
  static create(analyzerHandle: number, registryHandle = 0): StorageAdapter | null {
    const client = clientFor('commons');
    return client && analyzerHandle ? new StorageAdapter(client, analyzerHandle, registryHandle) : null;
  }

  constructor(
    private readonly client: WorkerProtoClient,
    private readonly analyzerHandle: number,
    private registryHandle = 0,
  ) {}

  async info(request: ProtoStorageInfoRequest): Promise<ProtoStorageInfoResult | null> {
    return this.client.callProto(
      'rac_storage_analyzer_info_proto',
      [Arg.num(this.analyzerHandle), Arg.num(await this.registry()), Arg.bytes(StorageInfoRequest.encode(request).finish()), Arg.outProto()],
      StorageInfoResult,
    );
  }

  async availability(request: ProtoStorageAvailabilityRequest): Promise<ProtoStorageAvailabilityResult | null> {
    return this.client.callProto(
      'rac_storage_analyzer_availability_proto',
      [Arg.num(this.analyzerHandle), Arg.num(await this.registry()), Arg.bytes(StorageAvailabilityRequest.encode(request).finish()), Arg.outProto()],
      StorageAvailabilityResult,
    );
  }

  async deletePlan(request: ProtoStorageDeletePlanRequest): Promise<ProtoStorageDeletePlan | null> {
    return this.client.callProto(
      'rac_storage_analyzer_delete_plan_proto',
      [Arg.num(this.analyzerHandle), Arg.num(await this.registry()), Arg.bytes(StorageDeletePlanRequest.encode(request).finish()), Arg.outProto()],
      StorageDeletePlan,
    );
  }

  async delete(request: ProtoStorageDeleteRequest): Promise<ProtoStorageDeleteResult | null> {
    return this.client.callProto(
      'rac_storage_analyzer_delete_proto',
      [Arg.num(this.analyzerHandle), Arg.num(await this.registry()), Arg.bytes(StorageDeleteRequest.encode(request).finish()), Arg.outProto()],
      StorageDeleteResult,
    );
  }

  private async registry(): Promise<number> {
    if (!this.registryHandle) this.registryHandle = await this.client.callRc('rac_get_model_registry', []);
    return this.registryHandle;
  }
}
