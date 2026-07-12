/**
 * ModelRegistryAdapter.ts — Web binding for
 * `rac_model_registry_refresh_proto` plus the proto-byte model registry ABI.
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

import { SDKLogger } from '../Foundation/SDKLogger.js';
import {
  RAC_OK as RAC_SUCCESS,
  RAC_ERROR_NOT_FOUND,
  RAC_ERROR_FEATURE_NOT_AVAILABLE,
  RAC_ERROR_INVALID_ARGUMENT,
} from '../Foundation/RACErrors.js';
import {
  ModelImportRequest as ProtoModelImportRequestCodec,
  ModelImportResult as ProtoModelImportResultCodec,
  ModelInfo as ProtoModelInfoCodec,
  ModelInfoList as ProtoModelInfoListCodec,
  ModelQuery as ProtoModelQueryCodec,
  ModelRegistryRefreshRequest as ProtoModelRegistryRefreshRequestCodec,
  ModelRegistryRefreshResult as ProtoModelRegistryRefreshResultCodec,
  type ModelImportRequest as ProtoModelImportRequest,
  type ModelImportResult as ProtoModelImportResult,
  type ModelInfo as ProtoModelInfo,
  type ModelInfoList as ProtoModelInfoList,
  type ModelQuery as ProtoModelQuery,
} from '@runanywhere/proto-ts/model_types';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm.js';

const logger = new SDKLogger('ModelRegistryAdapter');
const OUT_PTR_SIZE = 4;

export type ModelInfoList = ProtoModelInfoList;
export type ModelRegistryAvailability =
  | { status: 'available' }
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

  _rac_get_model_registry(): number;
  /**
   * `rac_result_t rac_model_registry_refresh_proto(handle, req_bytes,
   * req_size, out_proto_buffer)` — the single refresh entry point. Takes a
   * serialized `ModelRegistryRefreshRequest` and returns an owned
   * `ModelRegistryRefreshResult` via the out (bytes, size) pointer pair,
   * same shape as the other proto-byte registry calls in this file.
   */
  _rac_model_registry_refresh_proto(
    handle: number,
    reqBytes: number,
    reqSize: number,
    outBytesPtr: number,
    outSizePtr: number,
  ): number;
  _rac_model_registry_register_proto(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_update_proto(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_update_download_status(
    handle: number,
    modelId: number,
    localPath: number,
  ): number;
  _rac_model_registry_get_proto(
    handle: number,
    modelId: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_proto(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_query_proto(
    handle: number,
    queryProtoBytes: number,
    queryProtoSize: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_downloaded_proto(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_remove_proto(
    handle: number,
    modelId: number,
  ): number;
  /**
   * `rac_result_t rac_model_registry_import_proto(handle, req_bytes,
   * req_size, rac_proto_buffer_t* out_result)` — registers/merges a model
   * from a serialized `ModelImportRequest`; returns an owned
   * `ModelImportResult` via the proto buffer. C++ owns import semantics
   * (Swift parity: CppBridge.ModelRegistry.importModel).
   */
  _rac_model_registry_import_proto(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_model_registry_proto_free(protoBytes: number): void;
}

let defaultModule: ModelRegistryModule | null = null;
const defaultModuleListeners: DefaultModuleListener[] = [];
const protoAvailabilityByModule = new WeakMap<ModelRegistryModule, ModelRegistryAvailability>();
// Every WASM module that has ever been installed as a registry target — even
// after `setDefaultModule` reassigns the "primary" to a sibling backend.
// `register`/`update`/`remove` operations are broadcast across every module
// in this set so the per-module C++ `s_model_registry` singletons stay in
// sync. Without this, the catalog ends up populated in (say) LlamaCpp's
// registry while the commons WASM — which runs the C++ download orchestrator
// — sees an empty registry and can't self-heal post-download state.
const knownModules = new Set<ModelRegistryModule>();

export interface RefreshOptions {
  includeRemoteCatalog?: boolean;
  rescanLocal?: boolean;
  pruneOrphans?: boolean;
}

export class ModelRegistryAdapter {
  /**
   * Install the default Emscripten module (called by backend packages on
   * load). Mirrors the pattern used by `HTTPAdapter.setDefaultModule`.
   *
   * Each call ALSO adds the module to the broadcast set. Read operations
   * (`get`/`list`/`query`) continue to target the "default" module (the
   * last writer wins so the backend that owns the plugin route also owns
   * read lookups), while writes (`register`/`update`/`remove`) fan out to
   * every module in the set. That keeps commons + every backend WASM's
   * per-module `s_model_registry` consistent — the C++ download
   * orchestrator runs in whichever module owns the `DownloadAdapter`, and
   * its `rac_get_model(...)` lookup must succeed regardless of which
   * backend bridge happens to own the `ModelRegistryAdapter` primary slot.
  */
  static setDefaultModule(module: ModelRegistryModule): void {
    const adapter = new ModelRegistryAdapter(module);
    const missingExports = adapter.getMissingProtoExports();
    if (missingExports.length > 0) {
      throw new Error(
        `Current RunAnywhere WASM artifact is missing required model-registry exports: ${missingExports.join(', ')}`,
      );
    }
    const isNewModule = !knownModules.has(module);
    defaultModule = module;
    knownModules.add(module);

    // When a new backend WASM joins (e.g. ONNX after LlamaCPP), replay the
    // full model catalog from any existing module to the newcomer. Without
    // this, models registered before this module arrived are invisible to
    // its s_model_registry — causing RAC_ERROR_MODEL_NOT_FOUND when the new
    // WASM tries to resolve model paths (e.g. RAG session creation needs the
    // embedding model entry in the ONNX WASM's registry).
    if (isNewModule && knownModules.size > 1) {
      for (const existing of knownModules) {
        if (existing === module) continue;
        const sourceAdapter = new ModelRegistryAdapter(existing);
        const list = sourceAdapter.list();
        if (!list?.models?.length) continue;
        const targetAdapter = new ModelRegistryAdapter(module);
        for (const m of list.models) {
          targetAdapter.registerDirect(m);
        }
        break; // one source is sufficient
      }
    }

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

  /** Drop a single module from the broadcast set (e.g. on backend teardown). */
  static unregisterModule(module: ModelRegistryModule): void {
    knownModules.delete(module);
    if (defaultModule === module) {
      defaultModule = null;
    }
  }

  static clearDefaultModule(): void {
    defaultModule = null;
    knownModules.clear();
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
    return protoAvailabilityByModule.get(this.module) ?? { status: 'available' };
  }

  /**
   * Refresh the registry via `rac_model_registry_refresh_proto`. Encodes a
   * `ModelRegistryRefreshRequest`, calls the proto entry point, and decodes
   * the returned `ModelRegistryRefreshResult` to read `success`. Mirrors the
   * encode → withHeapBytes → readOwnedProtoResult pattern used by `query`.
   */
  refresh(options: RefreshOptions = {}): boolean {
    const mod = this.module;
    const handle = mod._rac_get_model_registry();
    if (!handle) {
      logger.warning('refresh: global registry handle is null');
      return false;
    }

    const reqBytes = ProtoModelRegistryRefreshRequestCodec.encode({
      includeRemoteCatalog: options.includeRemoteCatalog ?? false,
      rescanLocal: options.rescanLocal ?? false,
      pruneOrphans: options.pruneOrphans ?? false,
      catalogUri: '',
      forceRefresh: false,
      includeDownloadedState: options.rescanLocal ?? false,
    }).finish();

    try {
      const resultBytes = this.withHeapBytes(reqBytes, (reqPtr, reqLen) => (
        this.readOwnedProtoResult((outBytesPtr, outSizePtr) => (
          mod._rac_model_registry_refresh_proto!(
            handle,
            reqPtr,
            reqLen,
            outBytesPtr,
            outSizePtr,
          )
        ), 'rac_model_registry_refresh_proto')
      ));
      if (!resultBytes) {
        return false;
      }
      const result = ProtoModelRegistryRefreshResultCodec.decode(resultBytes);
      return result.success;
    } catch (error) {
      logger.warning(
        `rac_model_registry_refresh_proto threw: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return false;
    }
  }

  /**
   * Register a model in every known WASM module's `s_model_registry`.
   *
   * Emscripten modules do not share global state, so each backend owns an
   * `s_model_registry` singleton. The write is broadcast to every live module
   * and returns true only when all modules accept it; partial synchronization
   * is surfaced as failure.
   */
  register(model: ProtoModelInfo): boolean {
    const bytes = ProtoModelInfoCodec.encode(model).finish();
    return this.broadcastWrite('rac_model_registry_register_proto', (mod, handle) => (
      this.withHeapBytesOnModule(mod, bytes, (bytesPtr, bytesLen) => (
        mod._rac_model_registry_register_proto!(handle, bytesPtr, bytesLen)
      ))
    ));
  }

  /**
   * Update an existing model entry in every known WASM module's registry.
   * Uses the same all-live-modules contract as {@link register}.
   */
  update(model: ProtoModelInfo): boolean {
    const bytes = ProtoModelInfoCodec.encode(model).finish();
    return this.broadcastWrite('rac_model_registry_update_proto', (mod, handle) => (
      this.withHeapBytesOnModule(mod, bytes, (bytesPtr, bytesLen) => (
        mod._rac_model_registry_update_proto!(handle, bytesPtr, bytesLen)
      ))
    ));
  }

  /**
   * Set or explicitly clear a model's downloaded path in every known WASM
   * registry. The dedicated C ABI is required for clears: proto3 cannot
   * distinguish an omitted string from an explicitly empty `local_path`, so
   * `update(...)` intentionally preserves the existing path in that case.
   * Passing `null` forwards a null C pointer and resets downloaded state.
   */
  updateDownloadStatus(modelId: string, localPath: string | null): boolean {
    if (modelId.length === 0) {
      logger.warning('rac_model_registry_update_download_status requires a model id');
      return false;
    }
    return this.broadcastWrite(
      'rac_model_registry_update_download_status',
      (mod, handle) => {
        const idPtr = this.allocUtf8OnModule(mod, modelId);
        if (!idPtr) return RAC_ERROR_INVALID_ARGUMENT;
        const pathPtr = localPath === null ? 0 : this.allocUtf8OnModule(mod, localPath);
        if (localPath !== null && !pathPtr) {
          mod._free?.(idPtr);
          return RAC_ERROR_INVALID_ARGUMENT;
        }
        try {
          return mod._rac_model_registry_update_download_status!(handle, idPtr, pathPtr);
        } finally {
          mod._free?.(idPtr);
          if (pathPtr) mod._free?.(pathPtr);
        }
      },
    );
  }

  /**
   * Import a model through `rac_model_registry_import_proto` so commons owns
   * the import semantics (merge, overwrite, validation). Swift parity:
   * `CppBridge.ModelRegistry.importModel(request)`.
   *
   * Broadcast across every known module (same rationale as {@link register}:
   * per-module C++ `s_model_registry` singletons must stay in sync); the
   * primary module's decoded `ModelImportResult` is returned.
   */
  importModel(request: ProtoModelImportRequest): ProtoModelImportResult | null {
    const primary = this.module;
    let primaryResult: ProtoModelImportResult | null = null;

    const targets = new Set<ModelRegistryModule>(knownModules);
    if (!targets.has(primary)) targets.add(primary);

    for (const mod of targets) {
      const isPrimary = mod === primary;
      const adapter = isPrimary ? this : new ModelRegistryAdapter(mod);
      const handle = adapter.getRegistryHandle('importModel');
      if (!handle) continue;
      const bridge = new ProtoWasmBridge(mod as unknown as ProtoWasmModule, logger);
      const result = bridge.withEncodedRequest(
        request,
        ProtoModelImportRequestCodec,
        ProtoModelImportResultCodec,
        (requestPtr, requestSize, outResult) => (
          mod._rac_model_registry_import_proto!(handle, requestPtr, requestSize, outResult)
        ),
        'rac_model_registry_import_proto',
      );
      if (isPrimary) primaryResult = result;
    }
    return primaryResult;
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

  /**
   * Remove a model from every known WASM module's registry.
   * Uses the same all-live-modules contract as {@link register}. A missing
   * model in any live registry makes the operation fail.
   */
  remove(modelId: string): boolean {
    return this.broadcastWrite('rac_model_registry_remove_proto', (mod, handle) => {
      const idPtr = this.allocUtf8OnModule(mod, modelId);
      if (!idPtr) return -1;
      try {
        return mod._rac_model_registry_remove_proto!(handle, idPtr);
      } finally {
        mod._free?.(idPtr);
      }
    });
  }

  /**
   * Register a model directly on this adapter's module WITHOUT broadcasting
   * to other known modules. Used during catalog replay when a new WASM joins.
   */
  private registerDirect(model: ProtoModelInfo): void {
    if (!this.ensureProtoExports('registerDirect')) return;
    const handle = this.getRegistryHandle('registerDirect');
    if (!handle) return;
    const bytes = ProtoModelInfoCodec.encode(model).finish();
    try {
      this.withHeapBytesOnModule(this.module, bytes, (bytesPtr, bytesLen) => (
        this.module._rac_model_registry_register_proto!(handle, bytesPtr, bytesLen)
      ));
    } catch (error) {
      logger.debug(
        `registerDirect(${model.id}) failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  private getRegistryHandle(operation: string): number {
    const mod = this.module;
    const handle = mod._rac_get_model_registry();
    if (!handle) {
      logger.warning(`${operation}: global registry handle is null`);
      return 0;
    }
    return handle;
  }

  private ensureProtoExports(_operation: string): boolean {
    const availability = this.getProtoRegistryAvailability();
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
      'lengthBytesUTF8',
      'stringToUTF8',
      '_rac_get_model_registry',
      '_rac_model_registry_refresh_proto',
      '_rac_model_registry_register_proto',
      '_rac_model_registry_update_proto',
      '_rac_model_registry_update_download_status',
      '_rac_model_registry_get_proto',
      '_rac_model_registry_list_proto',
      '_rac_model_registry_query_proto',
      '_rac_model_registry_list_downloaded_proto',
      '_rac_model_registry_remove_proto',
      '_rac_model_registry_import_proto',
      '_rac_model_registry_proto_free',
    ];
    return required.filter((key) => !mod[key]).map(String);
  }

  private withHeapBytes<T>(bytes: Uint8Array, fn: (bytesPtr: number, bytesLen: number) => T): T {
    return this.withHeapBytesOnModule(this.module, bytes, fn);
  }

  private withHeapBytesOnModule<T>(
    mod: ModelRegistryModule,
    bytes: Uint8Array,
    fn: (bytesPtr: number, bytesLen: number) => T,
  ): T {
    const ptr = mod._malloc!(Math.max(bytes.byteLength, 1));
    try {
      mod.HEAPU8!.set(bytes, ptr);
      return fn(ptr, bytes.byteLength);
    } finally {
      mod._free!(ptr);
    }
  }

  private allocUtf8(value: string): number {
    return this.allocUtf8OnModule(this.module, value);
  }

  private allocUtf8OnModule(mod: ModelRegistryModule, value: string): number {
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

  /**
   * Run a write op against every known WASM module (commons + every backend
   * registered against `ModelRegistryAdapter`). Returns true only when the
   * primary and every sibling succeed.
   *
   * Every current WASM module must expose the registry ABI; installation
   * rejects incomplete artifacts before they can enter this broadcast set.
   *
   * Used by `register`, `update`, and `remove` to keep the per-module C++
   * `s_model_registry` singletons in sync. Without this fan-out, the C++
   * download orchestrator (which runs in whichever module owns
   * `DownloadAdapter`) cannot find a model when its own `s_model_registry`
   * is empty while a sibling module's registry is fully populated.
   */
  private broadcastWrite(
    functionName: string,
    invoke: (mod: ModelRegistryModule, handle: number) => number,
  ): boolean {
    const primary = this.module;
    let primaryResult: boolean | null = null;
    let allSucceeded = true;

    // Snapshot the set so re-entrant register/listener pairs don't mutate
    // the iteration target. The primary module is guaranteed to be present
    // because `setDefaultModule(mod)` adds it to `knownModules` before
    // assigning the primary slot.
    const targets = new Set<ModelRegistryModule>(knownModules);
    if (!targets.has(primary)) targets.add(primary);

    for (const mod of targets) {
      const isPrimary = mod === primary;
      const tempAdapter = isPrimary ? this : new ModelRegistryAdapter(mod);
      if (!tempAdapter.ensureProtoExports(functionName)) {
        allSucceeded = false;
        if (isPrimary) primaryResult = false;
        continue;
      }
      const handle = tempAdapter.getRegistryHandle(functionName);
      if (!handle) {
        allSucceeded = false;
        if (isPrimary) primaryResult = false;
        continue;
      }
      let rc: number;
      try {
        rc = invoke(mod, handle);
      } catch (error) {
        logger.warning(
          `${functionName} threw on sibling module: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
        allSucceeded = false;
        if (isPrimary) primaryResult = false;
        continue;
      }
      const ok = tempAdapter.handleResult(functionName, rc);
      if (!ok) allSucceeded = false;
      if (isPrimary) primaryResult = ok;
    }

    return primaryResult === true && allSucceeded;
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
    case RAC_ERROR_INVALID_ARGUMENT:
      return 'RAC_ERROR_INVALID_ARGUMENT';
    case -252:
      return 'RAC_ERROR_INVALID_FORMAT';
    default:
      return `rc=${rc}`;
  }
}
