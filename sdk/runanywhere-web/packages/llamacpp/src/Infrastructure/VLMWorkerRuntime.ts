/**
 * RunAnywhere Web SDK - VLM Worker Runtime (V2-canonical)
 *
 * Runs inside a dedicated Web Worker and manages its own WASM instance
 * so that the multi-second `rac_vlm_process_proto` call cannot block the
 * main-thread event loop.
 *
 * Protocol (matches `VLMWorkerBridge`):
 *   - `init`       : `{ wasmJsUrl, useWebGPU }`        → loads WASM, registers
 *                                                         VLM backend, creates
 *                                                         the VLM component.
 *   - `load-model` : `VLMLoadModelParams`              → writes model +
 *                                                         mmproj bytes into
 *                                                         Emscripten MEMFS and
 *                                                         calls
 *                                                         `rac_vlm_component_load_model`.
 *   - `process`    : `{ imageBytes, optionsBytes }`    → calls
 *                                                         `_rac_vlm_process_proto`
 *                                                         with the proto-encoded
 *                                                         `VLMImage` /
 *                                                         `VLMGenerationOptions`
 *                                                         and returns the
 *                                                         encoded `VLMResult`
 *                                                         bytes.
 *   - `cancel`     : best-effort cancel
 *   - `unload`     : releases the loaded model
 *
 * IMPORTANT: this file must NOT import from `@runanywhere/web` or
 * `LlamaCppBridge`. Workers run in an isolated context — a fresh WASM
 * module is loaded here, and the main-thread singletons do not exist
 * inside the worker. All offset/sizeof lookups go through the WASM
 * module's own `_rac_wasm_offsetof_*` / `_rac_wasm_sizeof_*` exports.
 */

// ---------------------------------------------------------------------------
// Minimal Emscripten module typing used by the worker
// ---------------------------------------------------------------------------

interface WorkerWasmModule {
  _malloc(size: number): number;
  _free(ptr: number): void;
  HEAPU8?: Uint8Array;
  HEAPU32?: Uint32Array;
  HEAP32?: Int32Array;
  getValue(ptr: number, type: string): number;
  setValue(ptr: number, value: number, type: string): void;
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;
  stringToUTF8(str: string, ptr: number, maxBytesToWrite: number): void | number;
  lengthBytesUTF8(str: string): number;
  addFunction(fn: (...args: number[]) => number | void, signature: string): number;
  removeFunction?(ptr: number): void;
  ccall(
    name: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;
  FS_createPath(parent: string, path: string, canRead: boolean, canWrite: boolean): void;
  FS_createDataFile(
    parent: string,
    name: string,
    data: Uint8Array,
    canRead: boolean,
    canWrite: boolean,
    canOwn: boolean,
  ): void;
  FS_unlink(path: string): void;

  // Core helpers
  _rac_wasm_sizeof_platform_adapter(): number;
  _rac_wasm_sizeof_config(): number;
  _rac_set_platform_adapter?(adapterPtr: number): number;

  // Proto buffer helpers
  _rac_proto_buffer_init(bufferPtr: number): void;
  _rac_proto_buffer_free(bufferPtr: number): void;
  _rac_wasm_sizeof_proto_buffer(): number;
  _rac_wasm_offsetof_proto_buffer_data(): number;
  _rac_wasm_offsetof_proto_buffer_size(): number;
  _rac_wasm_offsetof_proto_buffer_status(): number;
  _rac_wasm_offsetof_proto_buffer_error_message(): number;

  // Dynamic access for ccall-only exports
  [key: string]: unknown;
}

type WorkerModuleFactory = (opts: {
  print?: (s: string) => void;
  printErr?: (s: string) => void;
  locateFile?: (path: string) => string;
}) => Promise<WorkerWasmModule>;

// ---------------------------------------------------------------------------
// Incoming RPC messages (must mirror the bridge's VLMWorkerCommand shape)
// ---------------------------------------------------------------------------

import type { VLMLoadModelParams } from '../Types/VLMWorkerTypes';

interface InitPayload {
  wasmJsUrl: string;
  useWebGPU: boolean;
}

interface ProcessPayload {
  imageBytes: Uint8Array;
  optionsBytes: Uint8Array;
}

type WorkerCommand =
  | { type: 'init'; id: number; payload: InitPayload }
  | { type: 'load-model'; id: number; payload: VLMLoadModelParams }
  | { type: 'process'; id: number; payload: ProcessPayload }
  | { type: 'cancel'; id: number }
  | { type: 'unload'; id: number };

// ---------------------------------------------------------------------------
// Worker state
// ---------------------------------------------------------------------------

let wasmModule: WorkerWasmModule | null = null;
let vlmHandle = 0;
let isWebGPU = false;

const RAC_SUCCESS = 0;
const RAC_ERROR_NOT_FOUND = -423;

// ---------------------------------------------------------------------------
// Logging — lightweight (no SDKLogger in worker context)
// ---------------------------------------------------------------------------

const LOG_PREFIX = '[RunAnywhere:VLMWorker]';
function logInfo(...args: unknown[]): void {
  console.info(LOG_PREFIX, ...args);
}
function logWarn(...args: unknown[]): void {
  console.warn(LOG_PREFIX, ...args);
}
function logError(...args: unknown[]): void {
  console.error(LOG_PREFIX, ...args);
}

// ---------------------------------------------------------------------------
// Heap helpers
// ---------------------------------------------------------------------------

function allocString(m: WorkerWasmModule, str: string): number {
  const len = m.lengthBytesUTF8(str) + 1;
  const ptr = m._malloc(len);
  m.stringToUTF8(str, ptr, len);
  return ptr;
}

function writeToWasmHeap(
  m: WorkerWasmModule,
  src: Uint8Array,
  destPtr: number,
): void {
  if (m.HEAPU8) {
    m.HEAPU8.set(src, destPtr);
    return;
  }
  for (let i = 0; i < src.length; i++) {
    m.setValue(destPtr + i, src[i] ?? 0, 'i8');
  }
}

function readU32(m: WorkerWasmModule, ptr: number): number {
  if (m.HEAPU32) return m.HEAPU32[ptr >>> 2] ?? 0;
  return m.getValue(ptr, '*') >>> 0;
}

function readI32(m: WorkerWasmModule, ptr: number): number {
  if (m.HEAP32) return m.HEAP32[ptr >>> 2] ?? 0;
  return m.getValue(ptr, 'i32') | 0;
}

// ---------------------------------------------------------------------------
// Decode a populated `rac_proto_buffer_t*` into its raw payload bytes.
// Mirrors `ProtoWasmBridge.readResultProto()` — split from the allocating
// caller so JSPI (`Promise`-returning) ccalls can populate the buffer
// asynchronously before we read it.
// ---------------------------------------------------------------------------

function readProtoBufferBytes(
  m: WorkerWasmModule,
  bufferPtr: number,
  functionName: string,
): Uint8Array | null {
  const status = readI32(m, bufferPtr + m._rac_wasm_offsetof_proto_buffer_status());
  if (status === RAC_ERROR_NOT_FOUND) return null;
  if (status !== RAC_SUCCESS) {
    const messagePtr = readU32(
      m,
      bufferPtr + m._rac_wasm_offsetof_proto_buffer_error_message(),
    );
    const message = messagePtr ? m.UTF8ToString(messagePtr) : '';
    logWarn(
      `${functionName} buffer status=${status}${message ? `: ${message}` : ''}`,
    );
    return null;
  }
  const dataPtr = readU32(m, bufferPtr + m._rac_wasm_offsetof_proto_buffer_data());
  const dataSize = readU32(m, bufferPtr + m._rac_wasm_offsetof_proto_buffer_size());
  if (!dataPtr || dataSize === 0) return new Uint8Array();
  if (!m.HEAPU8) {
    const bytes = new Uint8Array(dataSize);
    for (let i = 0; i < dataSize; i++) {
      bytes[i] = m.getValue(dataPtr + i, 'i8') & 0xff;
    }
    return bytes;
  }
  return m.HEAPU8.slice(dataPtr, dataPtr + dataSize);
}

// ---------------------------------------------------------------------------
// WASM initialization
//
// Mirrors `LlamaCppBridge` / `PlatformAdapter`: register a minimal platform
// adapter, call rac_init, register the VLM backend, create the VLM component.
//
// The JSPI-wrapped call set here is intentional — rac_init, the VLM backend
// register call, and the component create call all suspend on WebGPU builds.
// The log callback inside rac_init can overflow the worker's JSPI stack on
// WebGPU builds, so we tolerate a non-zero rac_init return (VLM does not
// depend on it once the adapter pointer is stored).
// ---------------------------------------------------------------------------

async function initWASM(wasmJsUrl: string, useWebGPU: boolean): Promise<void> {
  isWebGPU = useWebGPU;
  logInfo(`Loading WASM module (${useWebGPU ? 'WebGPU' : 'CPU'})...`);

  const imported = (await import(/* @vite-ignore */ wasmJsUrl)) as {
    default: WorkerModuleFactory;
  };
  const createModule = imported.default;
  const wasmBaseUrl = wasmJsUrl.substring(0, wasmJsUrl.lastIndexOf('/') + 1);

  wasmModule = await createModule({
    print: (text: string) => logInfo(text),
    printErr: (text: string) => logError(text),
    locateFile: (path: string) => wasmBaseUrl + path,
  });

  const m = wasmModule;

  // ---- Build minimal rac_platform_adapter_t ----
  // Signatures match the main-thread PlatformAdapter.ts — Emscripten's
  // indirect-call table traps on any mismatch.
  //
  // IMPORTANT: every field offset comes from a runtime
  // `_rac_wasm_offsetof_platform_adapter_<field>()` helper compiled into
  // `wasm/src/wasm_exports.cpp`. We do NOT hard-code `PTR_SIZE = 4` or a
  // sequential accumulator — the struct layout depends on alignment/padding
  // and would silently corrupt memory on any reorder/add if TypeScript baked
  // it in.
  const adapterSize = m._rac_wasm_sizeof_platform_adapter();
  const adapterPtr = m._malloc(adapterSize);
  for (let i = 0; i < adapterSize; i++) m.setValue(adapterPtr + i, 0, 'i8');

  const getAdapterOffset = (name: string): number => {
    const fn = (m as unknown as Record<string, unknown>)[
      `_rac_wasm_offsetof_platform_adapter_${name}`
    ];
    if (typeof fn !== 'function') {
      throw new Error(
        `WASM module missing _rac_wasm_offsetof_platform_adapter_${name} export; ` +
        `rebuild racommons-llamacpp.wasm from wasm/src/wasm_exports.cpp.`,
      );
    }
    return (fn as () => number)();
  };

  // file_exists: rac_bool_t (*)(const char* path, void* user_data)
  const fileExistsCb = m.addFunction((_pathPtr: number, _ud: number) => 0, 'iii');
  m.setValue(adapterPtr + getAdapterOffset('file_exists'), fileExistsCb, '*');

  // file_read: rac_result_t (*)(const char* path, void** out_data, size_t* out_size, void* user_data)
  const fileReadCb = m.addFunction(
    (_pathPtr: number, _outData: number, _outSize: number, _ud: number) => -180,
    'iiiii',
  );
  m.setValue(adapterPtr + getAdapterOffset('file_read'), fileReadCb, '*');

  // file_write: rac_result_t (*)(const char* path, const void* data, size_t size, void* user_data)
  const fileWriteCb = m.addFunction(
    (_pathPtr: number, _data: number, _size: number, _ud: number) => -180,
    'iiiii',
  );
  m.setValue(adapterPtr + getAdapterOffset('file_write'), fileWriteCb, '*');

  // file_delete: rac_result_t (*)(const char* path, void* user_data)
  const fileDeleteCb = m.addFunction(
    (_pathPtr: number, _ud: number) => -180,
    'iii',
  );
  m.setValue(adapterPtr + getAdapterOffset('file_delete'), fileDeleteCb, '*');

  // secure_get: rac_result_t (*)(const char* key, char** out_value, void* user_data)
  const secureGetCb = m.addFunction(
    (_keyPtr: number, outPtr: number, _ud: number) => {
      m.setValue(outPtr, 0, '*');
      return -182;
    },
    'iiii',
  );
  m.setValue(adapterPtr + getAdapterOffset('secure_get'), secureGetCb, '*');

  // secure_set: rac_result_t (*)(const char* key, const char* value, void* user_data)
  const secureSetCb = m.addFunction(
    (_keyPtr: number, _valPtr: number, _ud: number) => 0,
    'iiii',
  );
  m.setValue(adapterPtr + getAdapterOffset('secure_set'), secureSetCb, '*');

  // secure_delete: rac_result_t (*)(const char* key, void* user_data)
  const secureDeleteCb = m.addFunction(
    (_keyPtr: number, _ud: number) => 0,
    'iii',
  );
  m.setValue(adapterPtr + getAdapterOffset('secure_delete'), secureDeleteCb, '*');

  // log: void (*)(rac_log_level_t level, const char* category, const char* message, void* user_data)
  const logCb = m.addFunction(
    (level: number, catPtr: number, msgPtr: number, _ud: number) => {
      const cat = m.UTF8ToString(catPtr);
      const msg = m.UTF8ToString(msgPtr);
      const prefix = `[RunAnywhere:VLMWorker:${cat}]`;
      if (level <= 1) console.debug(prefix, msg);
      else if (level === 2) console.info(prefix, msg);
      else if (level === 3) console.warn(prefix, msg);
      else console.error(prefix, msg);
    },
    'viiii',
  );
  m.setValue(adapterPtr + getAdapterOffset('log'), logCb, '*');

  // track_error (null)
  m.setValue(adapterPtr + getAdapterOffset('track_error'), 0, '*');

  // now_ms: int64_t (*)(void* user_data)
  const nowMsCb = m.addFunction((_ud: number) => Date.now(), 'ii');
  m.setValue(adapterPtr + getAdapterOffset('now_ms'), nowMsCb, '*');

  // get_memory_info: rac_result_t (*)(rac_memory_info_t* out_info, void* user_data)
  const memInfoCb = m.addFunction((outPtr: number, _ud: number) => {
    const totalMB =
      typeof (navigator as { deviceMemory?: number }).deviceMemory === 'number'
        ? (navigator as { deviceMemory?: number }).deviceMemory!
        : 4;
    const totalBytes = totalMB * 1024 * 1024 * 1024;
    m.setValue(outPtr, totalBytes & 0xffffffff, 'i32'); // total low
    m.setValue(outPtr + 4, 0, 'i32'); // total high
    m.setValue(outPtr + 8, totalBytes & 0xffffffff, 'i32'); // available low
    m.setValue(outPtr + 12, 0, 'i32'); // available high
    m.setValue(outPtr + 16, 0, 'i32'); // used low
    m.setValue(outPtr + 20, 0, 'i32'); // used high
    return 0;
  }, 'iii');
  m.setValue(adapterPtr + getAdapterOffset('get_memory_info'), memInfoCb, '*');

  // http_download (null)
  m.setValue(adapterPtr + getAdapterOffset('http_download'), 0, '*');
  // http_download_cancel (null)
  m.setValue(adapterPtr + getAdapterOffset('http_download_cancel'), 0, '*');
  // extract_archive (null)
  m.setValue(adapterPtr + getAdapterOffset('extract_archive'), 0, '*');
  // user_data (null)
  m.setValue(adapterPtr + getAdapterOffset('user_data'), 0, '*');

  // ---- Register the adapter ----
  logInfo('Step 1: Registering platform adapter...');
  if (typeof m._rac_set_platform_adapter === 'function') {
    const adapterResult = m._rac_set_platform_adapter(adapterPtr);
    if (adapterResult !== 0) {
      logWarn(`rac_set_platform_adapter returned ${adapterResult}`);
    }
  }
  logInfo('Step 1 done: Platform adapter registered');

  // ---- rac_init ----
  logInfo('Step 2: Calling rac_init...');
  const configSize = m._rac_wasm_sizeof_config();
  const configPtr = m._malloc(configSize);
  for (let i = 0; i < configSize; i++) m.setValue(configPtr + i, 0, 'i8');

  // rac_config_t field offsets — same rule as rac_platform_adapter_t above:
  // fail loudly if the helper is missing rather than silently corrupting
  // memory with a hard-coded offset that could break on any struct reorder.
  const configPlatformAdapterOffsetFn = (
    m as unknown as Record<string, unknown>
  )['_rac_wasm_offsetof_config_platform_adapter'];
  if (typeof configPlatformAdapterOffsetFn !== 'function') {
    throw new Error(
      'WASM module missing _rac_wasm_offsetof_config_platform_adapter export; ' +
      'rebuild racommons-llamacpp.wasm from wasm/src/wasm_exports.cpp.',
    );
  }
  const configLogLevelOffsetFn = (
    m as unknown as Record<string, unknown>
  )['_rac_wasm_offsetof_config_log_level'];
  if (typeof configLogLevelOffsetFn !== 'function') {
    throw new Error(
      'WASM module missing _rac_wasm_offsetof_config_log_level export; ' +
      'rebuild racommons-llamacpp.wasm from wasm/src/wasm_exports.cpp.',
    );
  }
  const platformAdapterOffset = (configPlatformAdapterOffsetFn as () => number)();
  const logLevelOffset = (configLogLevelOffsetFn as () => number)();
  m.setValue(configPtr + platformAdapterOffset, adapterPtr, '*');
  m.setValue(configPtr + logLevelOffset, 2, 'i32'); // INFO

  try {
    const initResult = (await m.ccall(
      'rac_init',
      'number',
      ['number'],
      [configPtr],
      { async: true },
    )) as number;
    if (initResult !== 0) {
      logWarn(
        `rac_init returned non-zero (${initResult}), continuing without full core init`,
      );
    } else {
      logInfo('Step 2 done: rac_init succeeded');
    }
  } catch (e) {
    // Expected on WebGPU workers — diffusion registry logging can overflow
    // the JSPI suspendable stack. Non-fatal for VLM.
    logWarn(
      `rac_init failed in worker (${e instanceof Error ? e.message : String(e)}), continuing — VLM does not require full core init`,
    );
  }
  m._free(configPtr);

  // ---- Register VLM backend ----
  logInfo('Step 3: Registering VLM backend...');
  if (typeof m['_rac_backend_llamacpp_vlm_register'] !== 'function') {
    throw new Error(
      'VLM backend not available in WASM build. Rebuild with: ./scripts/build.sh --webgpu --vlm',
    );
  }
  const regResult = (await m.ccall(
    'rac_backend_llamacpp_vlm_register',
    'number',
    [],
    [],
    { async: true },
  )) as number;
  logInfo(`Step 3 done: VLM backend registered (result: ${regResult})`);

  // ---- Create VLM component ----
  logInfo('Step 4: Creating VLM component...');
  const handlePtr = m._malloc(4);
  const createResult = (await m.ccall(
    'rac_vlm_component_create',
    'number',
    ['number'],
    [handlePtr],
    { async: true },
  )) as number;
  if (createResult !== 0) {
    m._free(handlePtr);
    throw new Error(`rac_vlm_component_create failed: ${createResult}`);
  }
  vlmHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logInfo(
    `WASM initialised, VLM component ready (${isWebGPU ? 'WebGPU' : 'CPU'})`,
  );
}

// ---------------------------------------------------------------------------
// Model loading
// ---------------------------------------------------------------------------

async function loadModel(payload: VLMLoadModelParams): Promise<void> {
  if (!wasmModule) throw new Error('[VLMWorker] initWASM() has not run');
  const m = wasmModule;

  m.FS_createPath('/', 'models', true, true);

  // Model bytes
  self.postMessage({
    id: -1,
    type: 'progress',
    payload: { stage: 'Preparing model...' },
  });
  const modelBytes = new Uint8Array(payload.modelData);
  const modelPath = `/models/${payload.modelFilename}`;
  try {
    m.FS_unlink(modelPath);
  } catch {
    /* doesn't exist */
  }
  logInfo(
    `Writing model to WASM FS: ${modelPath} (${(modelBytes.byteLength / 1024 / 1024).toFixed(1)} MB)`,
  );
  m.FS_createDataFile(
    '/models',
    payload.modelFilename,
    modelBytes,
    true,
    true,
    true,
  );

  // mmproj bytes
  self.postMessage({
    id: -1,
    type: 'progress',
    payload: { stage: 'Preparing vision encoder...' },
  });
  const mmprojBytes = new Uint8Array(payload.mmprojData);
  const mmprojPath = `/models/${payload.mmprojFilename}`;
  try {
    m.FS_unlink(mmprojPath);
  } catch {
    /* doesn't exist */
  }
  logInfo(
    `Writing mmproj to WASM FS: ${mmprojPath} (${(mmprojBytes.byteLength / 1024 / 1024).toFixed(1)} MB)`,
  );
  m.FS_createDataFile(
    '/models',
    payload.mmprojFilename,
    mmprojBytes,
    true,
    true,
    true,
  );

  // ---- rac_vlm_component_load_model ----
  self.postMessage({
    id: -1,
    type: 'progress',
    payload: { stage: 'Loading model...' },
  });
  const pathPtr = allocString(m, modelPath);
  const projPtr = allocString(m, mmprojPath);
  const idPtr = allocString(m, payload.modelId);
  const namePtr = allocString(m, payload.modelName);

  try {
    const result = (await m.ccall(
      'rac_vlm_component_load_model',
      'number',
      ['number', 'number', 'number', 'number', 'number'],
      [vlmHandle, pathPtr, projPtr, idPtr, namePtr],
      { async: true },
    )) as number;
    if (result !== 0) {
      throw new Error(`rac_vlm_component_load_model failed: ${result}`);
    }
    logInfo(`Model loaded: ${payload.modelId}`);
  } finally {
    m._free(pathPtr);
    m._free(projPtr);
    m._free(idPtr);
    m._free(namePtr);
  }
}

// ---------------------------------------------------------------------------
// Image processing — proto-byte protocol
//
// Forwards encoded VLMImage + VLMGenerationOptions to `_rac_vlm_process_proto`
// and returns the encoded `VLMResult` bytes to the main thread, which decodes
// them there. The worker stays codec-free.
// ---------------------------------------------------------------------------

async function processImage(payload: ProcessPayload): Promise<Uint8Array> {
  if (!wasmModule) throw new Error('[VLMWorker] initWASM() has not run');
  const m = wasmModule;

  if (typeof m['_rac_vlm_process_proto'] !== 'function') {
    throw new Error(
      '[VLMWorker] _rac_vlm_process_proto not exported — rebuild WASM with --vlm',
    );
  }

  const imageBytes = payload.imageBytes;
  const optionsBytes = payload.optionsBytes;

  const imagePtr = m._malloc(Math.max(imageBytes.byteLength, 1));
  const optionsPtr = m._malloc(Math.max(optionsBytes.byteLength, 1));
  if (!imagePtr || !optionsPtr) {
    if (imagePtr) m._free(imagePtr);
    if (optionsPtr) m._free(optionsPtr);
    throw new Error('[VLMWorker] failed to allocate proto input buffers');
  }

  writeToWasmHeap(m, imageBytes, imagePtr);
  writeToWasmHeap(m, optionsBytes, optionsPtr);

  const bufferSize = m._rac_wasm_sizeof_proto_buffer();
  const bufferPtr = m._malloc(Math.max(bufferSize, 1));
  if (!bufferPtr) {
    m._free(imagePtr);
    m._free(optionsPtr);
    throw new Error('[VLMWorker] failed to allocate proto result buffer');
  }

  try {
    m._rac_proto_buffer_init(bufferPtr);
    // _rac_vlm_process_proto is JSPI-wrapped on WebGPU builds — inference
    // suspends the WASM stack while running CLIP encode + LLM decode.
    const rc = (await m.ccall(
      'rac_vlm_process_proto',
      'number',
      ['number', 'number', 'number', 'number', 'number', 'number'],
      [
        vlmHandle,
        imagePtr,
        imageBytes.byteLength,
        optionsPtr,
        optionsBytes.byteLength,
        bufferPtr,
      ],
      { async: true },
    )) as number;

    if (rc === RAC_ERROR_NOT_FOUND) {
      throw new Error('rac_vlm_process_proto: handle not found');
    }
    if (rc !== RAC_SUCCESS) {
      throw new Error(`rac_vlm_process_proto returned rc=${rc}`);
    }

    const responseBytes = readProtoBufferBytes(m, bufferPtr, 'rac_vlm_process_proto');
    if (!responseBytes) {
      throw new Error('rac_vlm_process_proto returned no result');
    }
    return responseBytes;
  } finally {
    m._rac_proto_buffer_free(bufferPtr);
    m._free(bufferPtr);
    m._free(imagePtr);
    m._free(optionsPtr);
  }
}

// ---------------------------------------------------------------------------
// RPC message handler
// ---------------------------------------------------------------------------

function handleMessage(e: MessageEvent<WorkerCommand>): void {
  const { type, id } = e.data;

  const respond = async (): Promise<void> => {
    switch (type) {
      case 'init': {
        await initWASM(e.data.payload.wasmJsUrl, e.data.payload.useWebGPU ?? false);
        self.postMessage({
          id,
          type: 'result',
          payload: { success: true, useWebGPU: isWebGPU },
        });
        break;
      }
      case 'load-model': {
        await loadModel(e.data.payload);
        self.postMessage({ id, type: 'result', payload: { success: true } });
        break;
      }
      case 'process': {
        const responseBytes = await processImage(e.data.payload);
        // Transfer the underlying ArrayBuffer back zero-copy.
        self.postMessage(
          { id, type: 'result', payload: responseBytes },
          [responseBytes.buffer as ArrayBuffer],
        );
        break;
      }
      case 'cancel': {
        if (wasmModule && vlmHandle) {
          try {
            wasmModule.ccall(
              'rac_vlm_component_cancel',
              'number',
              ['number'],
              [vlmHandle],
            );
          } catch (err) {
            logWarn(
              `rac_vlm_component_cancel threw: ${err instanceof Error ? err.message : String(err)}`,
            );
          }
        }
        self.postMessage({ id, type: 'result', payload: { success: true } });
        break;
      }
      case 'unload': {
        if (wasmModule && vlmHandle) {
          try {
            wasmModule.ccall(
              'rac_vlm_component_unload',
              'number',
              ['number'],
              [vlmHandle],
            );
          } catch (err) {
            logWarn(
              `rac_vlm_component_unload threw: ${err instanceof Error ? err.message : String(err)}`,
            );
          }
        }
        self.postMessage({ id, type: 'result', payload: { success: true } });
        break;
      }
    }
  };

  respond().catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    logError(`Error in ${type}:`, message);
    self.postMessage({ id, type: 'error', payload: { message } });
  });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Boot the VLM Worker runtime. Call this from the worker entry point
 * (`workers/vlm-worker.ts` / `.js`).
 */
export function startVLMWorkerRuntime(): void {
  logInfo('VLM Worker runtime starting...');
  self.onmessage = handleMessage;
}
