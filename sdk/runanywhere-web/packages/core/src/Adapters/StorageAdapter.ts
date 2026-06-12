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
import { SDKLogger } from '../Foundation/SDKLogger';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm';

const logger = new SDKLogger('StorageAdapter');

export interface StorageModule extends ProtoWasmModule {
  _rac_get_model_registry?(): number;
  _rac_storage_analyzer_info_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_availability_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_delete_plan_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_delete_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
}

let defaultModule: StorageModule | null = null;
let defaultAnalyzerHandle = 0;
let defaultRegistryHandle = 0;

export class StorageAdapter {
  static setDefaultHandles(
    module: StorageModule,
    analyzerHandle: number,
    registryHandle = 0,
  ): void {
    defaultModule = module;
    defaultAnalyzerHandle = analyzerHandle;
    defaultRegistryHandle = registryHandle;
  }

  static clearDefaultHandles(): void {
    defaultModule = null;
    defaultAnalyzerHandle = 0;
    defaultRegistryHandle = 0;
  }

  static tryDefault(): StorageAdapter | null {
    if (!defaultModule || !defaultAnalyzerHandle) return null;
    return new StorageAdapter(defaultModule, defaultAnalyzerHandle, defaultRegistryHandle);
  }

  constructor(
    private readonly module: StorageModule,
    private readonly analyzerHandle: number,
    private readonly registryHandle = 0,
  ) {}

  supportsProtoStorage(): boolean {
    return this.missingExports().length === 0 && this.analyzerHandle !== 0;
  }

  info(request: ProtoStorageInfoRequest): ProtoStorageInfoResult | null {
    if (!this.ensureExports('info', ['_rac_storage_analyzer_info_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      StorageInfoRequest,
      StorageInfoResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_info_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_info_proto',
    );
  }

  availability(
    request: ProtoStorageAvailabilityRequest,
  ): ProtoStorageAvailabilityResult | null {
    if (!this.ensureExports('availability', ['_rac_storage_analyzer_availability_proto'])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      request,
      StorageAvailabilityRequest,
      StorageAvailabilityResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_availability_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_availability_proto',
    );
  }

  deletePlan(request: ProtoStorageDeletePlanRequest): ProtoStorageDeletePlan | null {
    if (!this.ensureExports('deletePlan', ['_rac_storage_analyzer_delete_plan_proto'])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      request,
      StorageDeletePlanRequest,
      StorageDeletePlan,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_delete_plan_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_delete_plan_proto',
    );
  }

  delete(request: ProtoStorageDeleteRequest): ProtoStorageDeleteResult | null {
    if (!this.ensureExports('delete', ['_rac_storage_analyzer_delete_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      StorageDeleteRequest,
      StorageDeleteResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_delete_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_delete_proto',
    );
  }

  private getRegistryHandle(): number {
    if (this.registryHandle) return this.registryHandle;
    return this.module._rac_get_model_registry?.() ?? 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private missingExports(): string[] {
    const required: Array<keyof StorageModule> = [
      '_rac_get_model_registry',
      '_rac_storage_analyzer_info_proto',
      '_rac_storage_analyzer_availability_proto',
      '_rac_storage_analyzer_delete_plan_proto',
      '_rac_storage_analyzer_delete_proto',
    ];
    return [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
  }

  private ensureExports(operation: string, required: Array<keyof StorageModule>): boolean {
    if (!this.analyzerHandle) {
      logger.warning(`${operation}: storage analyzer handle is null`);
      return false;
    }
    const missing = [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
    if (missing.length > 0) {
      logger.warning(`${operation}: module missing storage proto exports: ${missing.join(', ')}`);
      return false;
    }
    return true;
  }
}
