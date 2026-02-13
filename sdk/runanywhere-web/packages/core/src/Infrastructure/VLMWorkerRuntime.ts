/**
 * RunAnywhere Web SDK - VLM Worker Runtime
 *
 * Encapsulates the Worker-side logic for VLM inference. This module runs
 * inside a dedicated Web Worker and manages its own WASM instance
 * (separate from the main-thread SDK).
 *
 * Architecture:
 *   - Loads its OWN WASM instance (separate from the main thread SDK)
 *   - Reads model files from OPFS directly (no large postMessage transfers)
 *   - Communicates via typed postMessage RPC
 *
 * Why a separate WASM instance?
 *   The C function `rac_vlm_component_process` is synchronous and blocks for
 *   ~100s (2B model in WASM). Running it on the main thread freezes the entire UI.
 *   A Worker with its own WASM instance allows inference to happen concurrently.
 *
 * IMPORTANT: This file must NOT import from WASMBridge.ts or other SDK modules
 * that assume a main-thread context. The Worker has its own WASM instance and
 * should be self-contained. Only `type`-only imports are safe.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

// Type-only imports are safe — they are erased at compile time and don't pull
// SDK code into the Worker bundle.
import type { VLMWorkerCommand, VLMWorkerResponse, VLMWorkerResult } from './VLMWorkerBridge';

// Re-export for the bridge to import
export type { VLMWorkerResult };

// ---------------------------------------------------------------------------
// Worker state
// ---------------------------------------------------------------------------

let wasmModule: any = null;
let vlmHandle = 0;
let isWebGPU = false;

// ---------------------------------------------------------------------------
// Logging (lightweight — no SDKLogger dependency in Worker context)
// ---------------------------------------------------------------------------

const LOG_PREFIX = '[RunAnywhere:VLMWorker]';

function logDebug(...args: unknown[]): void { console.debug(LOG_PREFIX, ...args); }
function logInfo(...args: unknown[]): void { console.info(LOG_PREFIX, ...args); }
function logWarn(...args: unknown[]): void { console.warn(LOG_PREFIX, ...args); }
function logError(...args: unknown[]): void { console.error(LOG_PREFIX, ...args); }

// ---------------------------------------------------------------------------
// Helpers: string alloc / free on WASM heap
// ---------------------------------------------------------------------------

function allocString(str: string): number {
  const m = wasmModule;
  const len = m.lengthBytesUTF8(str) + 1; // +1 for null terminator
  const ptr = m._malloc(len);
  m.stringToUTF8(str, ptr, len);
  return ptr;
}

function readString(ptr: number): string {
  if (!ptr) return '';
  return wasmModule.UTF8ToString(ptr);
}

// ---------------------------------------------------------------------------
// Helpers: binary data ↔ WASM heap
//
// HEAPU8 may not be exported from the WASM module (depends on build config).
// Try HEAPU8 first for speed, fall back to setValue byte-by-byte.
// ---------------------------------------------------------------------------

function writeToWasmHeap(src: Uint8Array, destPtr: number): void {
  const m = wasmModule;

  // Fast path: direct HEAPU8 (available when exported via EXPORTED_RUNTIME_METHODS)
  if (m.HEAPU8) {
    m.HEAPU8.set(src, destPtr);
    return;
  }

  // Slow fallback: byte-by-byte via setValue (always available)
  for (let i = 0; i < src.length; i++) {
    m.setValue(destPtr + i, src[i], 'i8');
  }
}

// ---------------------------------------------------------------------------
// OPFS helpers (Workers have full OPFS access)
//
// Lightweight inline reader matching the same directory layout as OPFSStorage
// (root → models/ → nested paths). We don't import OPFSStorage because it
// uses SDKLogger and other SDK infrastructure that may not work in Workers.
// ---------------------------------------------------------------------------

const OPFS_MODELS_DIR = 'models';

async function loadFromOPFS(key: string): Promise<Uint8Array | null> {
  try {
    const root = await navigator.storage.getDirectory();
    const modelsDir = await root.getDirectoryHandle(OPFS_MODELS_DIR);

    let file: File;
    if (key.includes('/')) {
      const parts = key.split('/');
      let dir = modelsDir;
      for (let i = 0; i < parts.length - 1; i++) {
        dir = await dir.getDirectoryHandle(parts[i]);
      }
      const handle = await dir.getFileHandle(parts[parts.length - 1]);
      file = await handle.getFile();
    } else {
      const handle = await modelsDir.getFileHandle(key);
      file = await handle.getFile();
    }

    const buffer = await file.arrayBuffer();
    return new Uint8Array(buffer);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// WASM initialization
// ---------------------------------------------------------------------------

async function initWASM(wasmJsUrl: string, useWebGPU = false): Promise<void> {
  isWebGPU = useWebGPU;
  logInfo(`Loading WASM module (${useWebGPU ? 'WebGPU' : 'CPU'})...`);

  // Dynamically import the Emscripten ES6 glue JS
  const { default: createModule } = await import(/* @vite-ignore */ wasmJsUrl);

  wasmModule = await createModule({
    print: (text: string) => logInfo(text),
    printErr: (text: string) => logError(text),
  });

  const m = wasmModule;

  // ---- rac_init: minimal initialization ----
  // We need a platform adapter for rac_init. Create a minimal one.
  const adapterSize = m._rac_wasm_sizeof_platform_adapter();
  const adapterPtr = m._malloc(adapterSize);
  for (let i = 0; i < adapterSize; i++) m.setValue(adapterPtr + i, 0, 'i8');

  // Register essential callbacks via addFunction
  const PTR_SIZE = 4;
  let offset = 0;

  // file_exists (stub — VLM uses Emscripten's C fopen/fread, not the platform adapter)
  const fileExistsCb = m.addFunction(
    (_pathPtr: number, outExists: number, _ud: number): number => {
      m.setValue(outExists, 0, 'i32');
      return 0;
    },
    'iiii',
  );
  m.setValue(adapterPtr + offset, fileExistsCb, '*'); offset += PTR_SIZE;

  // file_read (no-op — model files use fopen/fread via Emscripten FS)
  const noopReadCb = m.addFunction((): number => -180, 'iiii');
  m.setValue(adapterPtr + offset, noopReadCb, '*'); offset += PTR_SIZE;

  // file_write (no-op)
  const noopWriteCb = m.addFunction((): number => -180, 'iiiii');
  m.setValue(adapterPtr + offset, noopWriteCb, '*'); offset += PTR_SIZE;

  // file_delete (no-op)
  const noopDelCb = m.addFunction((): number => -180, 'iii');
  m.setValue(adapterPtr + offset, noopDelCb, '*'); offset += PTR_SIZE;

  // secure_get (no-op, returns not-found)
  const secureGetCb = m.addFunction(
    (_kp: number, outPtr: number, _ud: number): number => {
      m.setValue(outPtr, 0, '*');
      return -182;
    },
    'iiii',
  );
  m.setValue(adapterPtr + offset, secureGetCb, '*'); offset += PTR_SIZE;

  // secure_set (no-op)
  const secureSetCb = m.addFunction((): number => 0, 'iiii');
  m.setValue(adapterPtr + offset, secureSetCb, '*'); offset += PTR_SIZE;

  // secure_delete (no-op)
  const secureDelCb = m.addFunction((): number => 0, 'iii');
  m.setValue(adapterPtr + offset, secureDelCb, '*'); offset += PTR_SIZE;

  // log
  const logCb = m.addFunction(
    (level: number, catPtr: number, msgPtr: number, _ud: number): void => {
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
  m.setValue(adapterPtr + offset, logCb, '*'); offset += PTR_SIZE;

  // track_error (null)
  m.setValue(adapterPtr + offset, 0, '*'); offset += PTR_SIZE;

  // now_ms
  const nowMsCb = m.addFunction((): number => performance.now(), 'i');
  m.setValue(adapterPtr + offset, nowMsCb, '*'); offset += PTR_SIZE;

  // get_memory_info (no-op)
  const memInfoCb = m.addFunction(
    (outPtr: number, _ud: number): number => {
      const total = (navigator as any).deviceMemory
        ? (navigator as any).deviceMemory * 1024 * 1024 * 1024
        : 4 * 1024 * 1024 * 1024;
      m.setValue(outPtr, total, 'i64');     // total
      m.setValue(outPtr + 8, total, 'i64'); // available (approximate)
      return 0;
    },
    'iii',
  );
  m.setValue(adapterPtr + offset, memInfoCb, '*'); offset += PTR_SIZE;

  // http_download (no-op)
  m.setValue(adapterPtr + offset, 0, '*'); offset += PTR_SIZE;

  // extract_archive (no-op)
  m.setValue(adapterPtr + offset, 0, '*'); offset += PTR_SIZE;

  // ---- Call rac_init ----
  const configSize = m._rac_wasm_sizeof_config();
  const configPtr = m._malloc(configSize);
  for (let i = 0; i < configSize; i++) m.setValue(configPtr + i, 0, 'i8');
  m.setValue(configPtr, adapterPtr, '*');   // platform_adapter
  m.setValue(configPtr + 4, 2, 'i32');     // log_level = INFO

  const initResult = m._rac_init(configPtr);
  m._free(configPtr);

  if (initResult !== 0) {
    throw new Error(`rac_init failed in Worker: ${initResult}`);
  }

  // ---- Register VLM backend ----
  const regFn = m['_rac_backend_llamacpp_vlm_register'];
  if (!regFn) {
    throw new Error('VLM backend not available in WASM build');
  }
  m.ccall('rac_backend_llamacpp_vlm_register', 'number', [], []);

  // ---- Create VLM component ----
  const handlePtr = m._malloc(4);
  const createResult = m.ccall('rac_vlm_component_create', 'number', ['number'], [handlePtr]) as number;
  if (createResult !== 0) {
    m._free(handlePtr);
    throw new Error(`rac_vlm_component_create failed: ${createResult}`);
  }
  vlmHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);

  logInfo(`WASM initialized, VLM component ready (${isWebGPU ? 'WebGPU' : 'CPU'})`);
}

// ---------------------------------------------------------------------------
// Model loading (reads from OPFS, writes to Worker's WASM FS)
// ---------------------------------------------------------------------------

async function loadModel(
  modelOpfsKey: string, modelFilename: string,
  mmprojOpfsKey: string, mmprojFilename: string,
  modelId: string, modelName: string,
): Promise<void> {
  const m = wasmModule;

  // Ensure /models directory exists in Emscripten FS
  m.FS_createPath('/', 'models', true, true);

  // Read model from OPFS
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Reading model from storage...' } });
  logInfo(`Reading model from OPFS: key=${modelOpfsKey}`);
  const modelData = await loadFromOPFS(modelOpfsKey);
  if (!modelData) throw new Error(`Model not found in OPFS: ${modelOpfsKey}`);
  logInfo(`Model data: ${(modelData.length / 1024 / 1024).toFixed(1)} MB`);

  // Write to WASM FS
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Preparing model...' } });
  const modelPath = `/models/${modelFilename}`;
  try { m.FS_unlink(modelPath); } catch { /* doesn't exist */ }
  logInfo(`Writing model to WASM FS: ${modelPath}`);
  m.FS_createDataFile('/models', modelFilename, modelData, true, true, true);
  logInfo('Model written to WASM FS');

  // Read mmproj from OPFS
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Reading vision encoder...' } });
  logInfo(`Reading mmproj from OPFS: key=${mmprojOpfsKey}`);
  const mmprojData = await loadFromOPFS(mmprojOpfsKey);
  if (!mmprojData) throw new Error(`mmproj not found in OPFS: ${mmprojOpfsKey}`);
  logInfo(`mmproj data: ${(mmprojData.length / 1024 / 1024).toFixed(1)} MB`);

  const mmprojPath = `/models/${mmprojFilename}`;
  try { m.FS_unlink(mmprojPath); } catch { /* doesn't exist */ }
  logInfo(`Writing mmproj to WASM FS: ${mmprojPath}`);
  m.FS_createDataFile('/models', mmprojFilename, mmprojData, true, true, true);
  logInfo('mmproj written to WASM FS');

  // Load model via VLM component
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Loading model...' } });
  const pathPtr = allocString(modelPath);
  const projPtr = allocString(mmprojPath);
  const idPtr = allocString(modelId);
  const namePtr = allocString(modelName);

  try {
    const result = m.ccall(
      'rac_vlm_component_load_model', 'number',
      ['number', 'number', 'number', 'number', 'number'],
      [vlmHandle, pathPtr, projPtr, idPtr, namePtr],
    ) as number;

    if (result !== 0) {
      throw new Error(`rac_vlm_component_load_model failed: ${result}`);
    }

    logInfo(`Model loaded: ${modelId}`);
  } finally {
    m._free(pathPtr);
    m._free(projPtr);
    m._free(idPtr);
    m._free(namePtr);
  }
}

// ---------------------------------------------------------------------------
// Image processing
// ---------------------------------------------------------------------------

function processImage(
  rgbPixels: ArrayBuffer,
  width: number, height: number,
  prompt: string,
  maxTokens: number, temperature: number,
): VLMWorkerResult {
  const m = wasmModule;
  const pixelArray = new Uint8Array(rgbPixels);

  // Use C sizeof helpers for correct struct sizes (avoids 32/64-bit mismatch)
  const imageSize: number = m.ccall('rac_wasm_sizeof_vlm_image', 'number', [], []);
  const optSize: number = m.ccall('rac_wasm_sizeof_vlm_options', 'number', [], []);
  const resSize: number = m.ccall('rac_wasm_sizeof_vlm_result', 'number', [], []);

  // Build rac_vlm_image_t struct (format=1 for RGB pixels)
  const imagePtr = m._malloc(imageSize);
  for (let i = 0; i < imageSize; i++) m.setValue(imagePtr + i, 0, 'i8');

  m.setValue(imagePtr, 1, 'i32'); // format = RGBPixels

  // pixel_data (offset 8 in WASM32: format(4) + file_path_ptr(4) = 8)
  const pixelPtr = m._malloc(pixelArray.length);
  writeToWasmHeap(pixelArray, pixelPtr);
  m.setValue(imagePtr + 8, pixelPtr, '*');

  // width at offset 16: format(4) + file_path(4) + pixel_data(4) + base64_data(4) = 16
  m.setValue(imagePtr + 16, width, 'i32');
  m.setValue(imagePtr + 20, height, 'i32');
  m.setValue(imagePtr + 24, pixelArray.length, 'i32'); // data_size

  // Build rac_vlm_options_t
  const optPtr = m._malloc(optSize);
  for (let i = 0; i < optSize; i++) m.setValue(optPtr + i, 0, 'i8');
  m.setValue(optPtr, maxTokens, 'i32');        // max_tokens at offset 0
  m.setValue(optPtr + 4, temperature, 'float'); // temperature at offset 4
  m.setValue(optPtr + 8, 0.9, 'float');         // top_p at offset 8

  const promptPtr = allocString(prompt);

  // Result struct
  const resPtr = m._malloc(resSize);
  for (let i = 0; i < resSize; i++) m.setValue(resPtr + i, 0, 'i8');

  try {
    const r = m.ccall(
      'rac_vlm_component_process', 'number',
      ['number', 'number', 'number', 'number', 'number'],
      [vlmHandle, imagePtr, promptPtr, optPtr, resPtr],
    ) as number;

    if (r !== 0) {
      throw new Error(`rac_vlm_component_process failed: ${r}`);
    }

    // Read rac_vlm_result_t
    const textPtr = m.getValue(resPtr, '*');
    const result: VLMWorkerResult = {
      text: readString(textPtr),
      promptTokens: m.getValue(resPtr + 4, 'i32'),
      imageTokens: m.getValue(resPtr + 8, 'i32'),
      completionTokens: m.getValue(resPtr + 12, 'i32'),
      totalTokens: m.getValue(resPtr + 16, 'i32'),
    };

    // Free C-allocated internal strings, then free JS-allocated struct
    m.ccall('rac_vlm_result_free', null, ['number'], [resPtr]);
    return result;
  } finally {
    m._free(promptPtr);
    m._free(imagePtr);
    m._free(optPtr);
    m._free(pixelPtr);
    m._free(resPtr);
  }
}

// ---------------------------------------------------------------------------
// RPC message handler
// ---------------------------------------------------------------------------

function handleMessage(e: MessageEvent<VLMWorkerCommand>): void {
  const { type, id } = e.data;

  const respond = async () => {
    switch (type) {
      case 'init': {
        await initWASM(e.data.payload.wasmJsUrl, e.data.payload.useWebGPU ?? false);
        self.postMessage({ id, type: 'result', payload: { success: true, useWebGPU: isWebGPU } } satisfies VLMWorkerResponse);
        break;
      }

      case 'load-model': {
        const p = e.data.payload;
        await loadModel(
          p.modelOpfsKey, p.modelFilename,
          p.mmprojOpfsKey, p.mmprojFilename,
          p.modelId, p.modelName,
        );
        self.postMessage({ id, type: 'result', payload: { success: true } } satisfies VLMWorkerResponse);
        break;
      }

      case 'process': {
        const p = e.data.payload;
        const result = processImage(
          p.rgbPixels, p.width, p.height,
          p.prompt, p.maxTokens, p.temperature,
        );
        self.postMessage({ id, type: 'result', payload: result } satisfies VLMWorkerResponse);
        break;
      }

      case 'cancel': {
        if (wasmModule && vlmHandle) {
          wasmModule.ccall('rac_vlm_component_cancel', 'number', ['number'], [vlmHandle]);
        }
        self.postMessage({ id, type: 'result', payload: { success: true } } satisfies VLMWorkerResponse);
        break;
      }

      case 'unload': {
        if (wasmModule && vlmHandle) {
          wasmModule.ccall('rac_vlm_component_unload', 'number', ['number'], [vlmHandle]);
        }
        self.postMessage({ id, type: 'result', payload: { success: true } } satisfies VLMWorkerResponse);
        break;
      }
    }
  };

  respond().catch((err) => {
    const message = err instanceof Error ? err.message : String(err);
    logError(`Error in ${type}:`, message);
    self.postMessage({ id, type: 'error', payload: { message } } satisfies VLMWorkerResponse);
  });
}

// ---------------------------------------------------------------------------
// Public API: start the runtime
// ---------------------------------------------------------------------------

/**
 * Start the VLM Worker runtime.
 *
 * Call this once from the Worker entry point. It sets up the `self.onmessage`
 * handler that processes RPC commands from the main-thread VLMWorkerBridge.
 *
 * @example
 * ```typescript
 * // workers/vlm-worker.ts
 * import { startVLMWorkerRuntime } from '../Infrastructure/VLMWorkerRuntime';
 * startVLMWorkerRuntime();
 * ```
 */
export function startVLMWorkerRuntime(): void {
  logInfo('VLM Worker runtime starting...');
  self.onmessage = handleMessage;
}
