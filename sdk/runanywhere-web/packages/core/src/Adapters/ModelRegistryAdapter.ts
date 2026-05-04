/**
 * ModelRegistryAdapter.ts — T4.9 Web binding for
 * `rac_model_registry_refresh` plus the proto-byte model registry ABI.
 *
 * The Web SDK's `ModelRegistry` (pure-TS) still owns the JS-side catalog
 * (UI state, listeners), but this adapter exposes the unified C-ABI so the
 * browser surface is symmetric with Swift / Kotlin / RN / Flutter.
 * The remote-catalog step flows through whatever transport the caller
 * configured on the native side (typically a fetch-backed assignment
 * callback installed at SDK init); `rescan_local` and `prune_orphans` are
 * no-ops in the browser today because there is no persistent filesystem
 * for discovery.
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import {
  ModelInfo as ProtoModelInfoCodec,
  ModelInfoList as ProtoModelInfoListCodec,
  ModelQuery as ProtoModelQueryCodec,
  type ModelInfo as ProtoModelInfo,
  type ModelInfoList as ProtoModelInfoList,
  type ModelQuery as ProtoModelQuery,
} from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('ModelRegistryAdapter');
const RAC_SUCCESS = 0;
const RAC_ERROR_NOT_FOUND = -423;
const RAC_ERROR_FEATURE_NOT_AVAILABLE = -801;
const OUT_PTR_SIZE = 4;

export type ModelInfoList = ProtoModelInfoList;
export type ModelRegistryAvailability =
  | { status: 'available' }
  | { status: 'missingExports'; missingExports: string[] }
  | { status: 'unsupported'; resultCode: number; reason: string }
  | { status: 'notInstalled'; reason: string };

type DefaultModuleListener = (adapter: ModelRegistryAdapter) => void;

export interface ModelRegistryModule {
  _malloc?(size: number): number;
  _free?(ptr: number): void;
  setValue?(ptr: number, value: number, type: string): void;
  getValue?(ptr: number, type: string): number;
  UTF8ToString?(ptr: number, maxBytesToRead?: number): string;
  stringToUTF8?(str: string, ptr: number, maxBytesToWrite: number): void;
  lengthBytesUTF8?(str: string): number;
  HEAPU8?: Uint8Array;
  HEAPU32?: Uint32Array;

  _rac_get_model_registry?(): number;
  /**
   * Emscripten ABI lowering of
   * `rac_result_t rac_model_registry_refresh(handle, opts_by_value)`.
   *
   * Clang with the WASM ABI splits `rac_model_registry_refresh_opts_t`
   * (three `rac_bool_t` int32s + one pointer) into the individual scalar
   * arguments shown below. If the ABI version of clang ever changes to
   * pass the struct through a hidden sret pointer, this binding will need
   * to allocate and pass a pointer instead.
   */
  _rac_model_registry_refresh?(
    handle: number,
    includeRemoteCatalog: number,
    rescanLocal: number,
    pruneOrphans: number,
    discoveryCallbacks: number,
  ): number;
  _rac_model_registry_register_proto?(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_update_proto?(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_get_proto?(
    handle: number,
    modelId: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_proto?(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_query_proto?(
    handle: number,
    queryProtoBytes: number,
    queryProtoSize: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_downloaded_proto?(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_remove_proto?(
    handle: number,
    modelId: number,
  ): number;
  _rac_model_registry_proto_free?(protoBytes: number): void;
}

let defaultModule: ModelRegistryModule | null = null;
const defaultModuleListeners: DefaultModuleListener[] = [];
const protoAvailabilityByModule = new WeakMap<ModelRegistryModule, ModelRegistryAvailability>();

export interface RefreshOptions {
  includeRemoteCatalog?: boolean;
  rescanLocal?: boolean;
  pruneOrphans?: boolean;
}

export class ModelRegistryAdapter {
  /**
   * Install the default Emscripten module (called by backend packages on
   * load). Mirrors the pattern used by `HTTPAdapter.setDefaultModule`.
   */
  static setDefaultModule(module: ModelRegistryModule): void {
    defaultModule = module;
    const adapter = new ModelRegistryAdapter(module);
    for (const listener of defaultModuleListeners) {
      try {
        listener(adapter);
      } catch (error) {
        logger.warning(
          `default module listener failed: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
  }

  static clearDefaultModule(): void {
    defaultModule = null;
  }

  static onDefaultModuleReady(listener: DefaultModuleListener): () => void {
    defaultModuleListeners.push(listener);
    if (defaultModule) {
      try {
        listener(new ModelRegistryAdapter(defaultModule));
      } catch (error) {
        logger.warning(
          `default module listener failed: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
    return () => {
      const index = defaultModuleListeners.indexOf(listener);
      if (index >= 0) defaultModuleListeners.splice(index, 1);
    };
  }

  /** Returns the installed module, or `null` if no backend has loaded yet. */
  static tryDefault(): ModelRegistryAdapter | null {
    if (!defaultModule) return null;
    return new ModelRegistryAdapter(defaultModule);
  }

  private constructor(private readonly module: ModelRegistryModule) {}

  supportsProtoRegistry(): boolean {
    return this.getProtoRegistryAvailability().status === 'available';
  }

  getProtoRegistryAvailability(): ModelRegistryAvailability {
    const missingExports = this.getMissingProtoExports();
    if (missingExports.length > 0) {
      return { status: 'missingExports', missingExports };
    }
    return protoAvailabilityByModule.get(this.module) ?? { status: 'available' };
  }

  /** Refresh the registry via `rac_model_registry_refresh`. */
  refresh(options: RefreshOptions = {}): boolean {
    const mod = this.module;
    if (!mod._rac_get_model_registry || !mod._rac_model_registry_refresh) {
      logger.warning(
        'refresh: module missing rac_get_model_registry / rac_model_registry_refresh exports',
      );
      return false;
    }

    const handle = mod._rac_get_model_registry();
    if (!handle) {
      logger.warning('refresh: global registry handle is null');
      return false;
    }

    try {
      const rc = mod._rac_model_registry_refresh(
        handle,
        options.includeRemoteCatalog ? 1 : 0,
        options.rescanLocal ? 1 : 0,
        options.pruneOrphans ? 1 : 0,
        0, // discovery_callbacks = nullptr
      );
      if (rc !== 0) {
        logger.warning(`rac_model_registry_refresh returned rc=${rc}`);
        return false;
      }
      return true;
    } catch (error) {
      logger.warning(
        `rac_model_registry_refresh threw: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return false;
    }
  }

  register(model: ProtoModelInfo): boolean {
    const mod = this.module;
    if (!this.ensureProtoExports('register')) return false;
    const handle = this.getRegistryHandle('register');
    if (!handle) return false;

    const bytes = ProtoModelInfoCodec.encode(model).finish();
    return this.withHeapBytes(bytes, (bytesPtr, bytesLen) => {
      const rc = mod._rac_model_registry_register_proto!(handle, bytesPtr, bytesLen);
      return this.handleResult('rac_model_registry_register_proto', rc);
    });
  }

  update(model: ProtoModelInfo): boolean {
    const mod = this.module;
    if (!this.ensureProtoExports('update')) return false;
    const handle = this.getRegistryHandle('update');
    if (!handle) return false;

    const bytes = ProtoModelInfoCodec.encode(model).finish();
    return this.withHeapBytes(bytes, (bytesPtr, bytesLen) => {
      const rc = mod._rac_model_registry_update_proto!(handle, bytesPtr, bytesLen);
      return this.handleResult('rac_model_registry_update_proto', rc);
    });
  }

  get(modelId: string): ProtoModelInfo | null {
    const mod = this.module;
    if (!this.ensureProtoExports('get')) return null;
    const handle = this.getRegistryHandle('get');
    if (!handle) return null;

    const idPtr = this.allocUtf8(modelId);
    if (!idPtr) return null;

    try {
      const bytes = this.readOwnedProtoResult((outBytesPtr, outSizePtr) => (
        mod._rac_model_registry_get_proto!(handle, idPtr, outBytesPtr, outSizePtr)
      ), 'rac_model_registry_get_proto');
      return bytes ? ProtoModelInfoCodec.decode(bytes) : null;
    } finally {
      this.module._free?.(idPtr);
    }
  }

  list(): ModelInfoList | null {
    const mod = this.module;
    if (!this.ensureProtoExports('list')) return null;
    const handle = this.getRegistryHandle('list');
    if (!handle) return null;

    const bytes = this.readOwnedProtoResult((outBytesPtr, outSizePtr) => (
      mod._rac_model_registry_list_proto!(handle, outBytesPtr, outSizePtr)
    ), 'rac_model_registry_list_proto');
    return bytes ? ProtoModelInfoListCodec.decode(bytes) : null;
  }

  query(query: ProtoModelQuery): ModelInfoList | null {
    const mod = this.module;
    if (!this.ensureProtoExports('query')) return null;
    const handle = this.getRegistryHandle('query');
    if (!handle) return null;

    const bytes = ProtoModelQueryCodec.encode(query).finish();
    return this.withHeapBytes(bytes, (queryPtr, queryLen) => {
      const resultBytes = this.readOwnedProtoResult((outBytesPtr, outSizePtr) => (
        mod._rac_model_registry_query_proto!(
          handle,
          queryPtr,
          queryLen,
          outBytesPtr,
          outSizePtr,
        )
      ), 'rac_model_registry_query_proto');
      return resultBytes ? ProtoModelInfoListCodec.decode(resultBytes) : null;
    });
  }

  listDownloaded(): ModelInfoList | null {
    const mod = this.module;
    if (!this.ensureProtoExports('listDownloaded')) return null;
    const handle = this.getRegistryHandle('listDownloaded');
    if (!handle) return null;

    const bytes = this.readOwnedProtoResult((outBytesPtr, outSizePtr) => (
      mod._rac_model_registry_list_downloaded_proto!(handle, outBytesPtr, outSizePtr)
    ), 'rac_model_registry_list_downloaded_proto');
    return bytes ? ProtoModelInfoListCodec.decode(bytes) : null;
  }

  remove(modelId: string): boolean {
    const mod = this.module;
    if (!this.ensureProtoExports('remove')) return false;
    const handle = this.getRegistryHandle('remove');
    if (!handle) return false;

    const idPtr = this.allocUtf8(modelId);
    if (!idPtr) return false;

    try {
      const rc = mod._rac_model_registry_remove_proto!(handle, idPtr);
      return this.handleResult('rac_model_registry_remove_proto', rc);
    } finally {
      this.module._free?.(idPtr);
    }
  }

  private getRegistryHandle(operation: string): number {
    const mod = this.module;
    if (!mod._rac_get_model_registry) {
      logger.warning(`${operation}: module missing rac_get_model_registry export`);
      return 0;
    }
    const handle = mod._rac_get_model_registry();
    if (!handle) {
      logger.warning(`${operation}: global registry handle is null`);
      return 0;
    }
    return handle;
  }

  private ensureProtoExports(operation: string): boolean {
    const availability = this.getProtoRegistryAvailability();
    if (availability.status === 'missingExports') {
      logger.warning(
        `${operation}: module missing proto registry exports: ${availability.missingExports.join(', ')}`,
      );
      return false;
    }
    if (availability.status === 'unsupported' || availability.status === 'notInstalled') {
      return false;
    }
    return true;
  }

  private getMissingProtoExports(): string[] {
    const mod = this.module;
    const required: Array<keyof ModelRegistryModule> = [
      '_malloc',
      '_free',
      'HEAPU8',
      '_rac_get_model_registry',
      '_rac_model_registry_register_proto',
      '_rac_model_registry_update_proto',
      '_rac_model_registry_get_proto',
      '_rac_model_registry_list_proto',
      '_rac_model_registry_query_proto',
      '_rac_model_registry_list_downloaded_proto',
      '_rac_model_registry_remove_proto',
      '_rac_model_registry_proto_free',
    ];
    return required.filter((key) => !mod[key]).map(String);
  }

  private withHeapBytes<T>(bytes: Uint8Array, fn: (bytesPtr: number, bytesLen: number) => T): T {
    const mod = this.module;
    const ptr = mod._malloc!(Math.max(bytes.byteLength, 1));
    try {
      mod.HEAPU8!.set(bytes, ptr);
      return fn(ptr, bytes.byteLength);
    } finally {
      mod._free!(ptr);
    }
  }

  private allocUtf8(value: string): number {
    const mod = this.module;
    if (!mod._malloc || !mod._free || !mod.lengthBytesUTF8 || !mod.stringToUTF8) {
      logger.warning('module missing UTF-8 allocation helpers');
      return 0;
    }
    const size = mod.lengthBytesUTF8(value) + 1;
    const ptr = mod._malloc(size);
    if (!ptr) {
      logger.warning('failed to allocate UTF-8 string in WASM heap');
      return 0;
    }
    mod.stringToUTF8(value, ptr, size);
    return ptr;
  }

  private readOwnedProtoResult(
    call: (outBytesPtr: number, outSizePtr: number) => number,
    functionName: string,
  ): Uint8Array | null {
    const mod = this.module;
    if (!mod._malloc || !mod._free || !mod._rac_model_registry_proto_free || !mod.HEAPU8) {
      logger.warning(`${functionName}: module missing output buffer helpers`);
      return null;
    }

    const outBytesPtr = mod._malloc(OUT_PTR_SIZE);
    const outSizePtr = mod._malloc(OUT_PTR_SIZE);
    if (!outBytesPtr || !outSizePtr) {
      if (outBytesPtr) mod._free(outBytesPtr);
      if (outSizePtr) mod._free(outSizePtr);
      logger.warning(`${functionName}: failed to allocate output pointers`);
      return null;
    }

    try {
      this.writeU32(outBytesPtr, 0);
      this.writeU32(outSizePtr, 0);

      const rc = call(outBytesPtr, outSizePtr);
      if (rc === RAC_ERROR_NOT_FOUND) {
        return null;
      }
      if (!this.handleResult(functionName, rc)) {
        return null;
      }

      const bytesPtr = this.readU32(outBytesPtr);
      const size = this.readU32(outSizePtr);
      if (!bytesPtr || size === 0) {
        if (bytesPtr) mod._rac_model_registry_proto_free(bytesPtr);
        return new Uint8Array();
      }

      const bytes = mod.HEAPU8.slice(bytesPtr, bytesPtr + size);
      mod._rac_model_registry_proto_free(bytesPtr);
      return bytes;
    } finally {
      mod._free(outBytesPtr);
      mod._free(outSizePtr);
    }
  }

  private readU32(ptr: number): number {
    const mod = this.module;
    if (mod.HEAPU32) return mod.HEAPU32[ptr >>> 2] ?? 0;
    if (mod.getValue) return mod.getValue(ptr, '*') >>> 0;
    return 0;
  }

  private writeU32(ptr: number, value: number): void {
    const mod = this.module;
    if (mod.HEAPU32) {
      mod.HEAPU32[ptr >>> 2] = value;
      return;
    }
    mod.setValue?.(ptr, value, '*');
  }

  private handleResult(functionName: string, rc: number): boolean {
    if (rc === RAC_SUCCESS) return true;
    if (rc === RAC_ERROR_FEATURE_NOT_AVAILABLE) {
      this.markProtoRegistryUnsupported(functionName);
      return false;
    }
    logger.warning(`${functionName} returned ${formatRacResult(rc)}`);
    return false;
  }

  private markProtoRegistryUnsupported(functionName: string): void {
    const current = protoAvailabilityByModule.get(this.module);
    if (current?.status === 'unsupported') return;
    protoAvailabilityByModule.set(this.module, {
      status: 'unsupported',
      resultCode: RAC_ERROR_FEATURE_NOT_AVAILABLE,
      reason: `${functionName} returned RAC_ERROR_FEATURE_NOT_AVAILABLE`,
    });
    logger.debug(`${functionName}: proto registry ABI unavailable in this WASM build`);
  }
}

function formatRacResult(rc: number): string {
  switch (rc) {
    case RAC_ERROR_NOT_FOUND:
      return 'RAC_ERROR_NOT_FOUND';
    case RAC_ERROR_FEATURE_NOT_AVAILABLE:
      return 'RAC_ERROR_FEATURE_NOT_AVAILABLE';
    case -259:
      return 'RAC_ERROR_INVALID_ARGUMENT';
    case -252:
      return 'RAC_ERROR_INVALID_FORMAT';
    default:
      return `rc=${rc}`;
  }
}
