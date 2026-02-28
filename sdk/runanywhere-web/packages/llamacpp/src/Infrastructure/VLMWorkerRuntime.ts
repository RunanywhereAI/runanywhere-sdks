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
import type { AllOffsets } from '@runanywhere/web';

// Re-export for the bridge to import
export type { VLMWorkerResult };

// ---------------------------------------------------------------------------
// Worker state
// ---------------------------------------------------------------------------

let wasmModule: any = null;
let vlmHandle = 0;
let isWebGPU = false;
let offsets: AllOffsets | null = null;

// ---------------------------------------------------------------------------
// Inline offset loader for Worker context
//
// The Worker cannot import from the main SDK or LlamaCppBridge (they assume
// a main-thread context). Instead, we read offsets directly from the WASM
// module's _rac_wasm_offsetof_* / _rac_wasm_sizeof_* exports.
// ---------------------------------------------------------------------------

function workerOffsetOf(m: any, name: string): number {
  const fn = m[`_rac_wasm_offsetof_${name}`];
  return typeof fn === 'function' ? fn() : 0;
}

function workerSizeOf(m: any, name: string): number {
  const fn = m[`_rac_wasm_sizeof_${name}`];
  return typeof fn === 'function' ? fn() : 0;
}

function loadOffsetsFromModule(m: any): AllOffsets {
  return {
    config: { logLevel: workerOffsetOf(m, 'config_log_level') },
    llmOptions: {
      maxTokens: workerOffsetOf(m, 'llm_options_max_tokens'),
      temperature: workerOffsetOf(m, 'llm_options_temperature'),
      topP: workerOffsetOf(m, 'llm_options_top_p'),
      systemPrompt: workerOffsetOf(m, 'llm_options_system_prompt'),
    },
    llmResult: {
      text: workerOffsetOf(m, 'llm_result_text'),
      promptTokens: workerOffsetOf(m, 'llm_result_prompt_tokens'),
      completionTokens: workerOffsetOf(m, 'llm_result_completion_tokens'),
    },
    vlmImage: {
      format: workerOffsetOf(m, 'vlm_image_format'),
      filePath: workerOffsetOf(m, 'vlm_image_file_path'),
      pixelData: workerOffsetOf(m, 'vlm_image_pixel_data'),
      base64Data: workerOffsetOf(m, 'vlm_image_base64_data'),
      width: workerOffsetOf(m, 'vlm_image_width'),
      height: workerOffsetOf(m, 'vlm_image_height'),
      dataSize: workerOffsetOf(m, 'vlm_image_data_size'),
    },
    vlmOptions: {
      maxTokens: workerOffsetOf(m, 'vlm_options_max_tokens'),
      temperature: workerOffsetOf(m, 'vlm_options_temperature'),
      topP: workerOffsetOf(m, 'vlm_options_top_p'),
      streamingEnabled: workerOffsetOf(m, 'vlm_options_streaming_enabled'),
      systemPrompt: workerOffsetOf(m, 'vlm_options_system_prompt'),
      modelFamily: workerOffsetOf(m, 'vlm_options_model_family'),
    },
    vlmResult: {
      text: workerOffsetOf(m, 'vlm_result_text'),
      promptTokens: workerOffsetOf(m, 'vlm_result_prompt_tokens'),
      imageTokens: workerOffsetOf(m, 'vlm_result_image_tokens'),
      completionTokens: workerOffsetOf(m, 'vlm_result_completion_tokens'),
      totalTokens: workerOffsetOf(m, 'vlm_result_total_tokens'),
      timeToFirstTokenMs: workerOffsetOf(m, 'vlm_result_time_to_first_token_ms'),
      imageEncodeTimeMs: workerOffsetOf(m, 'vlm_result_image_encode_time_ms'),
      totalTimeMs: workerOffsetOf(m, 'vlm_result_total_time_ms'),
      tokensPerSecond: workerOffsetOf(m, 'vlm_result_tokens_per_second'),
    },
    structuredOutputConfig: {
      jsonSchema: workerOffsetOf(m, 'structured_output_config_json_schema'),
      includeSchemaInPrompt: workerOffsetOf(m, 'structured_output_config_include_schema_in_prompt'),
    },
    structuredOutputValidation: {
      isValid: workerOffsetOf(m, 'structured_output_validation_is_valid'),
      errorMessage: workerOffsetOf(m, 'structured_output_validation_error_message'),
      extractedJson: workerOffsetOf(m, 'structured_output_validation_extracted_json'),
    },
    embeddingsOptions: {
      normalize: workerOffsetOf(m, 'embeddings_options_normalize'),
      pooling: workerOffsetOf(m, 'embeddings_options_pooling'),
      nThreads: workerOffsetOf(m, 'embeddings_options_n_threads'),
    },
    embeddingsResult: {
      embeddings: workerOffsetOf(m, 'embeddings_result_embeddings'),
      numEmbeddings: workerOffsetOf(m, 'embeddings_result_num_embeddings'),
      dimension: workerOffsetOf(m, 'embeddings_result_dimension'),
      processingTimeMs: workerOffsetOf(m, 'embeddings_result_processing_time_ms'),
      totalTokens: workerOffsetOf(m, 'embeddings_result_total_tokens'),
    },
    embeddingVector: {
      data: workerOffsetOf(m, 'embedding_vector_data'),
      dimension: workerOffsetOf(m, 'embedding_vector_dimension'),
      structSize: workerSizeOf(m, 'embedding_vector'),
    },
    diffusionOptions: {
      prompt: workerOffsetOf(m, 'diffusion_options_prompt'),
      negativePrompt: workerOffsetOf(m, 'diffusion_options_negative_prompt'),
      width: workerOffsetOf(m, 'diffusion_options_width'),
      height: workerOffsetOf(m, 'diffusion_options_height'),
      steps: workerOffsetOf(m, 'diffusion_options_steps'),
      guidanceScale: workerOffsetOf(m, 'diffusion_options_guidance_scale'),
      seed: workerOffsetOf(m, 'diffusion_options_seed'),
      scheduler: workerOffsetOf(m, 'diffusion_options_scheduler'),
      mode: workerOffsetOf(m, 'diffusion_options_mode'),
      denoiseStrength: workerOffsetOf(m, 'diffusion_options_denoise_strength'),
      reportIntermediate: workerOffsetOf(m, 'diffusion_options_report_intermediate'),
      progressStride: workerOffsetOf(m, 'diffusion_options_progress_stride'),
    },
    diffusionResult: {
      imageData: workerOffsetOf(m, 'diffusion_result_image_data'),
      imageSize: workerOffsetOf(m, 'diffusion_result_image_size'),
      width: workerOffsetOf(m, 'diffusion_result_width'),
      height: workerOffsetOf(m, 'diffusion_result_height'),
      seedUsed: workerOffsetOf(m, 'diffusion_result_seed_used'),
      generationTimeMs: workerOffsetOf(m, 'diffusion_result_generation_time_ms'),
      safetyFlagged: workerOffsetOf(m, 'diffusion_result_safety_flagged'),
    },
  };
}

// ---------------------------------------------------------------------------
// Logging (lightweight — no SDKLogger dependency in Worker context)
// ---------------------------------------------------------------------------

const LOG_PREFIX = '[RunAnywhere:VLMWorker]';

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
  const wasmBaseUrl = wasmJsUrl.substring(0, wasmJsUrl.lastIndexOf('/') + 1);

  wasmModule = await createModule({
    print: (text: string) => logInfo(text),
    printErr: (text: string) => logError(text),
    locateFile: (path: string) => wasmBaseUrl + path,
  });

  const m = wasmModule;

  // ---- rac_init: minimal initialization ----
  // We need a platform adapter for rac_init. Create a minimal one.
  const adapterSize = m._rac_wasm_sizeof_platform_adapter();
  const adapterPtr = m._malloc(adapterSize);
  for (let i = 0; i < adapterSize; i++) m.setValue(adapterPtr + i, 0, 'i8');

  // Register essential callbacks via addFunction.
  // Signatures MUST match the main-thread PlatformAdapter.ts exactly —
  // Emscripten's indirect-call table traps on signature mismatch.
  const PTR_SIZE = 4;
  let offset = 0;

  // file_exists: rac_bool_t (*)(const char* path, void* user_data)
  const fileExistsCb = m.addFunction(
    (_pathPtr: number, _ud: number): number => {
      return 0; // nothing exists — VLM uses Emscripten's C fopen/fread
    },
    'iii',
  );
  m.setValue(adapterPtr + offset, fileExistsCb, '*'); offset += PTR_SIZE;

  // file_read: rac_result_t (*)(const char* path, void** out_data, size_t* out_size, void* user_data)
  const noopReadCb = m.addFunction(
    (_pathPtr: number, _outData: number, _outSize: number, _ud: number): number => -180,
    'iiiii',
  );
  m.setValue(adapterPtr + offset, noopReadCb, '*'); offset += PTR_SIZE;

  // file_write: rac_result_t (*)(const char* path, const void* data, size_t size, void* user_data)
  const noopWriteCb = m.addFunction(
    (_pathPtr: number, _data: number, _size: number, _ud: number): number => -180,
    'iiiii',
  );
  m.setValue(adapterPtr + offset, noopWriteCb, '*'); offset += PTR_SIZE;

  // file_delete: rac_result_t (*)(const char* path, void* user_data)
  const noopDelCb = m.addFunction((_pathPtr: number, _ud: number): number => -180, 'iii');
  m.setValue(adapterPtr + offset, noopDelCb, '*'); offset += PTR_SIZE;

  // secure_get: rac_result_t (*)(const char* key, char** out_value, void* user_data)
  const secureGetCb = m.addFunction(
    (_kp: number, outPtr: number, _ud: number): number => {
      m.setValue(outPtr, 0, '*');
      return -182;
    },
    'iiii',
  );
  m.setValue(adapterPtr + offset, secureGetCb, '*'); offset += PTR_SIZE;

  // secure_set: rac_result_t (*)(const char* key, const char* value, void* user_data)
  const secureSetCb = m.addFunction(
    (_keyPtr: number, _valPtr: number, _ud: number): number => 0,
    'iiii',
  );
  m.setValue(adapterPtr + offset, secureSetCb, '*'); offset += PTR_SIZE;

  // secure_delete: rac_result_t (*)(const char* key, void* user_data)
  const secureDelCb = m.addFunction((_keyPtr: number, _ud: number): number => 0, 'iii');
  m.setValue(adapterPtr + offset, secureDelCb, '*'); offset += PTR_SIZE;

  // log: void (*)(rac_log_level_t level, const char* category, const char* message, void* user_data)
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

  // now_ms: int64_t (*)(void* user_data)  — signature 'ii' (returns i32, takes i32 user_data)
  const nowMsCb = m.addFunction((_ud: number): number => Date.now(), 'ii');
  m.setValue(adapterPtr + offset, nowMsCb, '*'); offset += PTR_SIZE;

  // get_memory_info: rac_result_t (*)(rac_memory_info_t* out_info, void* user_data)
  const memInfoCb = m.addFunction(
    (outPtr: number, _ud: number): number => {
      const totalMB = (navigator as any).deviceMemory ?? 4;
      const totalBytes = totalMB * 1024 * 1024 * 1024;
      // rac_memory_info_t: { uint64_t total, available, used }
      // Write as two i32 values per uint64 (wasm32)
      m.setValue(outPtr, totalBytes & 0xFFFFFFFF, 'i32');      // total low
      m.setValue(outPtr + 4, 0, 'i32');                         // total high
      m.setValue(outPtr + 8, totalBytes & 0xFFFFFFFF, 'i32');  // available low
      m.setValue(outPtr + 12, 0, 'i32');                        // available high
      m.setValue(outPtr + 16, 0, 'i32');                        // used low
      m.setValue(outPtr + 20, 0, 'i32');                        // used high
      return 0;
    },
    'iii',
  );
  m.setValue(adapterPtr + offset, memInfoCb, '*'); offset += PTR_SIZE;

  // http_download (no-op)
  m.setValue(adapterPtr + offset, 0, '*'); offset += PTR_SIZE;

  // http_download_cancel (no-op) — main-thread PlatformAdapter also sets this slot
  m.setValue(adapterPtr + offset, 0, '*'); offset += PTR_SIZE;

  // extract_archive (no-op)
  m.setValue(adapterPtr + offset, 0, '*'); offset += PTR_SIZE;

  // user_data (null)
  m.setValue(adapterPtr + offset, 0, '*');

  // ---- Register the adapter with RACommons (must happen before rac_init) ----
  // _rac_set_platform_adapter is a simple pointer-store: it makes NO indirect
  // calls into JS, so Emscripten does NOT wrap it with JSPI → returns a plain
  // number synchronously.
  logInfo('Step 1: Registering platform adapter...');
  if (typeof m._rac_set_platform_adapter === 'function') {
    const adapterResult = m._rac_set_platform_adapter(adapterPtr);
    if (adapterResult !== 0) {
      logWarn(`rac_set_platform_adapter returned ${adapterResult}`);
    }
  }
  logInfo('Step 1 done: Platform adapter registered');

  // ---- Call rac_init ----
  //
  // rac_init is logically synchronous C++ (stores adapter, inits diffusion
  // registry, logs).  However, in the WebGPU WASM build **every** export that
  // transitively calls an addFunction-registered callback (e.g. the log
  // callback via adapter->log) is JSPI-wrapped and returns a Promise.
  //
  // The Worker's JSPI suspendable stack is smaller than the main thread's,
  // and the diffusion-model-registry init inside rac_init calls RAC_LOG_INFO
  // multiple times — each log allocates 2×2048-byte char[] buffers on the
  // stack — which overflows the JSPI stack with "memory access out of bounds".
  //
  // This is NON-FATAL for VLM: none of rac_backend_llamacpp_vlm_register,
  // rac_vlm_component_create, rac_vlm_component_load_model, or
  // rac_vlm_component_process check `s_initialized`. The platform adapter
  // was already stored in Step 1 via rac_set_platform_adapter, so logging
  // from subsequent calls still works.
  //
  // Strategy: try rac_init, and if it fails (JSPI stack overflow), continue.
  logInfo('Step 2: Calling rac_init...');
  const configSize = m._rac_wasm_sizeof_config();
  const configPtr = m._malloc(configSize);
  for (let i = 0; i < configSize; i++) m.setValue(configPtr + i, 0, 'i8');
  m.setValue(configPtr, adapterPtr, '*');   // platform_adapter (offset 0)

  const logLevelOffset = typeof m._rac_wasm_offsetof_config_log_level === 'function'
    ? m._rac_wasm_offsetof_config_log_level()
    : 4;
  m.setValue(configPtr + logLevelOffset, 2, 'i32'); // log_level = INFO

  try {
    const initResult = await m.ccall(
      'rac_init', 'number', ['number'], [configPtr], { async: true },
    ) as number;
    if (initResult !== 0) {
      logWarn(`rac_init returned non-zero (${initResult}), continuing without full core init`);
    } else {
      logInfo('Step 2 done: rac_init succeeded');
    }
  } catch (e) {
    // Expected on WebGPU Workers: diffusion registry logging overflows the
    // JSPI suspendable stack.  Non-fatal — VLM functions don't depend on it.
    logWarn(`rac_init failed in Worker (${e}), continuing — VLM does not require full core init`);
  }
  m._free(configPtr);

  // ---- Load struct field offsets ----
  // These are simple sizeof / offsetof helper exports that return plain ints.
  // They do NOT call any callbacks → not JSPI-wrapped → synchronous.
  logInfo('Step 3: Loading struct offsets...');
  offsets = loadOffsetsFromModule(m);
  logInfo('Step 3 done: Offsets loaded');

  // ---- Register VLM backend ----
  // rac_backend_llamacpp_vlm_register is only available when the WASM binary
  // was built with --vlm (RAC_WASM_VLM=ON).  It is in JSPI_EXPORTS so it
  // returns a Promise → use ccall({async: true}).
  logInfo('Step 4: Registering VLM backend...');
  if (typeof m['_rac_backend_llamacpp_vlm_register'] !== 'function') {
    throw new Error(
      'VLM backend not available in WASM build. '
      + 'Rebuild with: ./scripts/build.sh --webgpu --vlm',
    );
  }
  const regResult = await m.ccall(
    'rac_backend_llamacpp_vlm_register', 'number', [], [], { async: true },
  ) as number;
  logInfo(`Step 4 done: VLM backend registered (result: ${regResult})`);

  // ---- Create VLM component ----
  // rac_vlm_component_create is in JSPI_EXPORTS → returns Promise.
  logInfo('Step 5: Creating VLM component...');
  const handlePtr = m._malloc(4);
  const createResult = await m.ccall(
    'rac_vlm_component_create', 'number', ['number'], [handlePtr], { async: true },
  ) as number;
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
  providedModelData?: ArrayBuffer, providedMmprojData?: ArrayBuffer,
): Promise<void> {
  const m = wasmModule;

  // Ensure /models directory exists in Emscripten FS
  m.FS_createPath('/', 'models', true, true);

  // Read model: use provided data (transferred from main thread) or OPFS
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Reading model from storage...' } });
  let modelData: Uint8Array;
  if (providedModelData && providedModelData.byteLength > 0) {
    logInfo(`Using transferred model data: ${(providedModelData.byteLength / 1024 / 1024).toFixed(1)} MB`);
    modelData = new Uint8Array(providedModelData);
  } else {
    logInfo(`Reading model from OPFS: key=${modelOpfsKey}`);
    const opfsData = await loadFromOPFS(modelOpfsKey);
    if (!opfsData) throw new Error(`Model not found in OPFS: ${modelOpfsKey}`);
    modelData = opfsData;
  }
  logInfo(`Model data: ${(modelData.length / 1024 / 1024).toFixed(1)} MB`);

  // Write to WASM FS
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Preparing model...' } });
  const modelPath = `/models/${modelFilename}`;
  try { m.FS_unlink(modelPath); } catch { /* doesn't exist */ }
  logInfo(`Writing model to WASM FS: ${modelPath}`);
  m.FS_createDataFile('/models', modelFilename, modelData, true, true, true);
  logInfo('Model written to WASM FS');

  // Read mmproj: use provided data or OPFS
  self.postMessage({ id: -1, type: 'progress', payload: { stage: 'Reading vision encoder...' } });
  let mmprojData: Uint8Array;
  if (providedMmprojData && providedMmprojData.byteLength > 0) {
    logInfo(`Using transferred mmproj data: ${(providedMmprojData.byteLength / 1024 / 1024).toFixed(1)} MB`);
    mmprojData = new Uint8Array(providedMmprojData);
  } else {
    logInfo(`Reading mmproj from OPFS: key=${mmprojOpfsKey}`);
    const opfsMmproj = await loadFromOPFS(mmprojOpfsKey);
    if (!opfsMmproj) throw new Error(`mmproj not found in OPFS: ${mmprojOpfsKey}`);
    mmprojData = opfsMmproj;
  }
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
    // {async: true} for JSPI — model loading creates WebGPU buffers and
    // allocates GPU memory, which suspends the WASM stack.
    const result = await m.ccall(
      'rac_vlm_component_load_model', 'number',
      ['number', 'number', 'number', 'number', 'number'],
      [vlmHandle, pathPtr, projPtr, idPtr, namePtr],
      { async: true },
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

async function processImage(
  rgbPixels: ArrayBuffer,
  width: number, height: number,
  prompt: string,
  maxTokens: number, temperature: number,
  topP: number, systemPrompt?: string,
  modelFamily?: number,
): Promise<VLMWorkerResult> {
  const m = wasmModule;
  const pixelArray = new Uint8Array(rgbPixels);

  // Use C sizeof helpers for correct struct sizes (avoids 32/64-bit mismatch)
  const imageSize: number = m.ccall('rac_wasm_sizeof_vlm_image', 'number', [], []);
  const optSize: number = m.ccall('rac_wasm_sizeof_vlm_options', 'number', [], []);
  const resSize: number = m.ccall('rac_wasm_sizeof_vlm_result', 'number', [], []);

  // Build rac_vlm_image_t struct (format=1 for RGB pixels)
  const imagePtr = m._malloc(imageSize);
  for (let i = 0; i < imageSize; i++) m.setValue(imagePtr + i, 0, 'i8');

  const vi = offsets!.vlmImage;
  m.setValue(imagePtr + vi.format, 1, 'i32'); // format = RGBPixels

  const pixelPtr = m._malloc(pixelArray.length);
  writeToWasmHeap(pixelArray, pixelPtr);
  m.setValue(imagePtr + vi.pixelData, pixelPtr, '*');

  m.setValue(imagePtr + vi.width, width, 'i32');
  m.setValue(imagePtr + vi.height, height, 'i32');
  m.setValue(imagePtr + vi.dataSize, pixelArray.length, 'i32');

  // Build rac_vlm_options_t (offsets from compiler)
  const optPtr = m._malloc(optSize);
  for (let i = 0; i < optSize; i++) m.setValue(optPtr + i, 0, 'i8');
  const vo = offsets!.vlmOptions;
  m.setValue(optPtr + vo.maxTokens, maxTokens, 'i32');
  m.setValue(optPtr + vo.temperature, temperature, 'float');
  m.setValue(optPtr + vo.topP, topP, 'float');

  let systemPromptPtr = 0;
  if (systemPrompt) {
    systemPromptPtr = allocString(systemPrompt);
    m.setValue(optPtr + vo.systemPrompt, systemPromptPtr, '*');
  }

  m.setValue(optPtr + vo.modelFamily, modelFamily ?? 0, 'i32');

  const promptPtr = allocString(prompt);

  // Result struct
  const resPtr = m._malloc(resSize);
  for (let i = 0; i < resSize; i++) m.setValue(resPtr + i, 0, 'i8');

  try {
    // {async: true} for JSPI — VLM inference performs extensive GPU compute
    // (CLIP encoding + LLM generation) that suspends the WASM stack.
    const r = await m.ccall(
      'rac_vlm_component_process', 'number',
      ['number', 'number', 'number', 'number', 'number'],
      [vlmHandle, imagePtr, promptPtr, optPtr, resPtr],
      { async: true },
    ) as number;

    if (r !== 0) {
      throw new Error(`rac_vlm_component_process failed: ${r}`);
    }

    // Read rac_vlm_result_t (offsets from compiler via StructOffsets)
    const vr = offsets!.vlmResult;
    const textPtr = m.getValue(resPtr + vr.text, '*');
    const result: VLMWorkerResult = {
      text: readString(textPtr),
      promptTokens: m.getValue(resPtr + vr.promptTokens, 'i32'),
      imageTokens: m.getValue(resPtr + vr.imageTokens, 'i32'),
      completionTokens: m.getValue(resPtr + vr.completionTokens, 'i32'),
      totalTokens: m.getValue(resPtr + vr.totalTokens, 'i32'),
    };

    // Free C-allocated internal strings, then free JS-allocated struct
    m.ccall('rac_vlm_result_free', null, ['number'], [resPtr]);
    return result;
  } finally {
    if (systemPromptPtr) m._free(systemPromptPtr);
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
          (p as any).modelData, (p as any).mmprojData,
        );
        self.postMessage({ id, type: 'result', payload: { success: true } } satisfies VLMWorkerResponse);
        break;
      }

      case 'process': {
        const p = e.data.payload;
        const result = await processImage(
          p.rgbPixels, p.width, p.height,
          p.prompt, p.maxTokens, p.temperature,
          p.topP, p.systemPrompt, p.modelFamily,
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
