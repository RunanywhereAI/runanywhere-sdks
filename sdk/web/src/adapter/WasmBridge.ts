// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// PlatformBridge implementation over the Emscripten WASM module. The
// WASM module is produced by `scripts/build-core-wasm.sh` and exports
// every `ra_*` ABI function via EXPORTED_FUNCTIONS in
// sdk/web/wasm/CMakeLists.txt.
//
// setPlatformBridge(wasmBridge) during app initialization to wire
// Telemetry / Auth / ModelHelpers / RagStore / FileIntegrity to the
// real core.

/// Duplicated locally to avoid cross-package rootDir TypeScript headaches.
/// Kept in lockstep with `sdk/ts/src/adapter/PlatformBridge.ts` — see that
/// file for the canonical definition and the registry helpers.
export interface PlatformBridge {
  authIsAuthenticated(): boolean;
  authNeedsRefresh(horizonSeconds?: number): boolean;
  authGetAccessToken(): string;
  authGetRefreshToken(): string;
  authGetDeviceId(): string;
  authBuildAuthenticateRequest(apiKey: string, deviceId: string): string;
  authHandleAuthenticateResponse(body: string): boolean;
  authHandleRefreshResponse(body: string): boolean;
  authClear(): void;

  telemetryTrack(event: string, propertiesJson?: string): boolean;
  telemetryFlush(): boolean;
  telemetryDefaultPayloadJson(): string;

  modelFrameworkSupports(framework: string, category: string): boolean;
  modelDetectFormat(urlOrPath: string): number;
  modelInferCategory(modelId: string): number;
  modelIsArchive(urlOrPath: string): boolean;

  ragStoreCreate(dim: number): number;
  ragStoreDestroy(handle: number): void;
  ragStoreSize(handle: number): number;
  ragStoreAdd(handle: number, rowId: string, metadataJson: string,
                embedding: Float32Array): boolean;
  ragStoreSearch(handle: number, query: Float32Array, topK: number):
    Array<{ id: string; metadataJson: string; score: number }>;

  sha256File(path: string): string | null;
  verifySha256(path: string, expectedHex: string): boolean;
}

/** Shape of the Emscripten module exposed to TS. */
export interface RAWasmModule {
  cwrap(fn: string, ret: string | null, args: string[]): (...a: unknown[]) => unknown;
  ccall(fn: string, ret: string | null, args: string[], values: unknown[]): unknown;
  _malloc(n: number): number;
  _free(p: number): void;
  HEAPU8: Uint8Array;
  HEAPF32: Float32Array;
  UTF8ToString(p: number, maxBytes?: number): string;
  stringToUTF8(s: string, p: number, maxBytes: number): void;
  lengthBytesUTF8(s: string): number;
}

/// Copies a Float32Array into WASM heap; returns the byte pointer.
/// Caller must `_free(ptr)` when done.
function writeFloats(mod: RAWasmModule, arr: Float32Array): number {
  const bytes = arr.length * 4;
  const ptr   = mod._malloc(bytes);
  mod.HEAPF32.set(arr, ptr / 4);
  return ptr;
}

/// Reads a C-string pointer returned through a `char**` out-param.
function readOutString(mod: RAWasmModule, outPtrPtr: number,
                         freeFn: (ptr: number) => void): string {
  const strPtr = new Uint32Array(mod.HEAPU8.buffer, outPtrPtr, 1)[0];
  const s = mod.UTF8ToString(strPtr);
  freeFn(strPtr);
  return s;
}

export function createWasmBridge(mod: RAWasmModule): PlatformBridge {
  // Cwrap'd functions — cached once per call site to avoid per-call lookup.
  const c = (fn: string, ret: string | null, args: string[]) =>
    mod.cwrap(fn, ret, args);

  const auth_is_auth        = c('ra_auth_is_authenticated',    'number', []);
  const auth_needs_refresh  = c('ra_auth_needs_refresh',       'number', ['number']);
  const auth_access         = c('ra_auth_get_access_token',    'string', []);
  const auth_refresh        = c('ra_auth_get_refresh_token',   'string', []);
  const auth_device         = c('ra_auth_get_device_id',       'string', []);
  const auth_handle_resp    = c('ra_auth_handle_authenticate_response', 'number', ['string']);
  const auth_handle_ref     = c('ra_auth_handle_refresh_response',     'number', ['string']);
  const auth_clear          = c('ra_auth_clear', null, []);

  const tel_track           = c('ra_telemetry_track',          'number', ['string', 'string']);
  const tel_flush           = c('ra_telemetry_flush',          'number', []);
  const tel_default_payload = c('ra_telemetry_payload_default','number', ['number']);
  const tel_string_free     = c('ra_telemetry_string_free',    null,     ['number']);

  const model_fw_supports   = c('ra_framework_supports',       'number', ['string', 'string']);
  const model_detect_format = c('ra_model_detect_format',      'number', ['string']);
  const model_infer_cat     = c('ra_model_infer_category',     'number', ['string']);
  const model_is_archive    = c('ra_artifact_is_archive',      'number', ['string']);

  const rag_create     = c('ra_rag_store_create',       'number', ['number', 'number']);
  const rag_destroy    = c('ra_rag_store_destroy',      null,     ['number']);
  const rag_size       = c('ra_rag_store_size',         'number', ['number']);
  const rag_add        = c('ra_rag_store_add',          'number',
                             ['number', 'string', 'string', 'number', 'number']);
  const rag_search     = c('ra_rag_store_search',       'number',
                             ['number', 'number', 'number', 'number',
                              'number', 'number', 'number', 'number']);

  const dl_sha256      = c('ra_download_sha256_file',   'number', ['string', 'number']);
  const dl_verify      = c('ra_download_verify_sha256', 'number', ['string', 'string']);
  const dl_str_free    = c('ra_download_string_free',   null,     ['number']);

  // Helper: call a fn that takes `T** out` and return the populated string.
  function callForOutString(fn: (...a: unknown[]) => unknown,
                              args: unknown[],
                              freeStr: (p: number) => void): string | null {
    const outPtrPtr = mod._malloc(4);
    try {
      const rc = fn(...args, outPtrPtr) as number;
      if (rc !== 0) return null;
      return readOutString(mod, outPtrPtr, freeStr);
    } finally { mod._free(outPtrPtr); }
  }

  return {
    // Auth
    authIsAuthenticated:        () => (auth_is_auth() as number) !== 0,
    authNeedsRefresh:           (h = 60) => (auth_needs_refresh(h) as number) !== 0,
    authGetAccessToken:         () => (auth_access() as string) ?? '',
    authGetRefreshToken:        () => (auth_refresh() as string) ?? '',
    authGetDeviceId:            () => (auth_device() as string) ?? '',
    authBuildAuthenticateRequest(apiKey, deviceId) {
      // out-string helper with 2-arg prefix
      const outPtrPtr = mod._malloc(4);
      try {
        const rc = mod.ccall('ra_auth_build_authenticate_request', 'number',
                              ['string', 'string', 'number'],
                              [apiKey, deviceId, outPtrPtr]) as number;
        if (rc !== 0) return '{}';
        return readOutString(mod, outPtrPtr,
          (p) => mod.ccall('ra_auth_string_free', null, ['number'], [p]));
      } finally { mod._free(outPtrPtr); }
    },
    authHandleAuthenticateResponse: (body) => (auth_handle_resp(body) as number) === 0,
    authHandleRefreshResponse:      (body) => (auth_handle_ref(body)  as number) === 0,
    authClear:                  () => { auth_clear(); },

    // Telemetry
    telemetryTrack:             (e, p = '{}') => (tel_track(e, p) as number) === 0,
    telemetryFlush:             () => (tel_flush() as number) === 0,
    telemetryDefaultPayloadJson() {
      return callForOutString(tel_default_payload, [], tel_string_free) ?? '{}';
    },

    // Model
    modelFrameworkSupports:     (f, c_) => (model_fw_supports(f, c_) as number) !== 0,
    modelDetectFormat:          (u)     => model_detect_format(u) as number,
    modelInferCategory:         (m)     => model_infer_cat(m) as number,
    modelIsArchive:             (u)     => (model_is_archive(u) as number) !== 0,

    // RAG
    ragStoreCreate(dim) {
      const outPtr = mod._malloc(4);
      try {
        const rc = rag_create(dim, outPtr) as number;
        if (rc !== 0) return 0;
        return new Uint32Array(mod.HEAPU8.buffer, outPtr, 1)[0];
      } finally { mod._free(outPtr); }
    },
    ragStoreDestroy: (h) => { rag_destroy(h); },
    ragStoreSize:    (h) => rag_size(h) as number,
    ragStoreAdd(handle, rowId, metaJson, embedding) {
      const p = writeFloats(mod, embedding);
      try {
        return (rag_add(handle, rowId, metaJson, p, embedding.length) as number) === 0;
      } finally { mod._free(p); }
    },
    ragStoreSearch(handle, query, topK) {
      const qp = writeFloats(mod, query);
      const idsPtrPtr    = mod._malloc(4);
      const metasPtrPtr  = mod._malloc(4);
      const scoresPtrPtr = mod._malloc(4);
      const countPtr     = mod._malloc(4);
      try {
        const rc = rag_search(handle, qp, query.length, topK,
                                idsPtrPtr, metasPtrPtr, scoresPtrPtr, countPtr) as number;
        if (rc !== 0) return [];
        const count = new Uint32Array(mod.HEAPU8.buffer, countPtr, 1)[0];
        if (count === 0) return [];
        const idsBase    = new Uint32Array(mod.HEAPU8.buffer, idsPtrPtr, 1)[0];
        const metasBase  = new Uint32Array(mod.HEAPU8.buffer, metasPtrPtr, 1)[0];
        const scoresBase = new Uint32Array(mod.HEAPU8.buffer, scoresPtrPtr, 1)[0];
        const out: Array<{ id: string; metadataJson: string; score: number }> = [];
        for (let i = 0; i < count; i++) {
          const idPtr    = new Uint32Array(mod.HEAPU8.buffer, idsBase + i*4, 1)[0];
          const metaPtr  = new Uint32Array(mod.HEAPU8.buffer, metasBase + i*4, 1)[0];
          const scoreVal = new Float32Array(mod.HEAPU8.buffer, scoresBase + i*4, 1)[0];
          out.push({
            id: mod.UTF8ToString(idPtr),
            metadataJson: mod.UTF8ToString(metaPtr),
            score: scoreVal
          });
        }
        // Free the C-side arrays.
        mod.ccall('ra_rag_strings_free', null, ['number', 'number'], [idsBase, count]);
        mod.ccall('ra_rag_strings_free', null, ['number', 'number'], [metasBase, count]);
        mod.ccall('ra_rag_floats_free',  null, ['number'],          [scoresBase]);
        return out;
      } finally {
        mod._free(qp); mod._free(idsPtrPtr); mod._free(metasPtrPtr);
        mod._free(scoresPtrPtr); mod._free(countPtr);
      }
    },

    // File integrity
    sha256File(path) {
      const outPtrPtr = mod._malloc(4);
      try {
        const rc = dl_sha256(path, outPtrPtr) as number;
        if (rc !== 0) return null;
        return readOutString(mod, outPtrPtr, dl_str_free);
      } finally { mod._free(outPtrPtr); }
    },
    verifySha256: (p, expected) => (dl_verify(p, expected) as number) === 0,
  };
}
