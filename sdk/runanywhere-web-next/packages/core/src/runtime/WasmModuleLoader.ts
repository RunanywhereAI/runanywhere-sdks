import { RAC_OK, RAC_ERROR_MODULE_ALREADY_REGISTERED } from '../Foundation/RACErrors';
import { SDKLogger } from '../Foundation/SDKLogger';
import { FetchHttpTransport, type FetchHttpTransportModule } from './FetchHttpTransport';
import { PlatformAdapter, type PlatformAdapterModule, type SecureStore } from './PlatformAdapter';
import { TelemetryBridge, type TelemetryInit, type TelemetryModule } from './TelemetryBridge';
import type { WorkerWasmModule } from './WasmCallMarshaller';

const logger = new SDKLogger('WasmModuleLoader');

export interface BootModule extends WorkerWasmModule {
  addFunction(fn: (...args: never[]) => unknown, signature: string): number;
  removeFunction(ptr: number): void;
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
  FS?: unknown;
  _rac_wasm_sizeof_platform_adapter?(): number;
  _rac_wasm_ping?(): number | Promise<number>;
  _rac_init?(configPtr: number): number;
  _rac_shutdown?(): void;
  _rac_error_message?(code: number): number;
  _rac_wasm_sizeof_config?(): number;
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;
  _rac_model_paths_set_base_dir?(basePtr: number): number;
  _rac_http_transport_register_emscripten?(): number;
  _rac_http_transport_is_registered?(): number;
  _rac_set_inference_threads?(n: number): void;
}

interface CreateModuleOptions {
  print?: (text: string) => void;
  printErr?: (text: string) => void;
  locateFile?: (path: string) => string;
}
type CreateModuleFn = (options?: CreateModuleOptions) => Promise<BootModule>;

export interface BootOptions {
  wasmJsUrl: string;
  logLevel?: number;
  registerFns?: string[];
  secureStore?: SecureStore;
  baseDir?: string;
  telemetry?: TelemetryInit;
}

export interface LoadedModule {
  module: BootModule;
  adapter: PlatformAdapter;
  telemetry: TelemetryBridge | null;
}

export async function loadWasmModule(opts: BootOptions): Promise<LoadedModule> {
  const { wasmJsUrl, logLevel = 2, registerFns = [], secureStore, baseDir = '/opfs', telemetry } = opts;

  const glue = (await import(/* @vite-ignore */ wasmJsUrl)) as { default: CreateModuleFn };
  const baseUrl = wasmJsUrl.substring(0, wasmJsUrl.lastIndexOf('/') + 1);

  const module = await glue.default({
    print: (text) => logger.info(text),
    printErr: (text) => logger.info(text),
    locateFile: (path) => baseUrl + path,
  });

  await pingCheck(module);

  const adapter = new PlatformAdapter(module as unknown as PlatformAdapterModule, secureStore);
  adapter.register();

  let telemetryBridge: TelemetryBridge | null = null;
  try {
    initRAC(module, adapter.getAdapterPtr(), logLevel);
    setInferenceThreads(module);
    setBaseDir(module, baseDir);
    registerHttpTransport(module);
    if (telemetry) {
      telemetryBridge = TelemetryBridge.install(module as unknown as TelemetryModule, telemetry);
    }
    runRegisterFns(module, registerFns);
  } catch (err) {
    telemetryBridge?.uninstall();
    adapter.cleanup();
    throw err;
  }

  return { module, adapter, telemetry: telemetryBridge };
}

async function pingCheck(module: BootModule): Promise<void> {
  const pingFn = module._rac_wasm_ping;
  if (typeof pingFn !== 'function') throw new Error('WASM module missing _rac_wasm_ping export');
  const result = pingFn();
  const ping = typeof result === 'object' && result !== null && 'then' in result ? await result : result;
  if (ping !== 42) throw new Error(`WASM ping failed: expected 42, got ${ping}`);
}

function initRAC(module: BootModule, adapterPtr: number, logLevel: number): void {
  const sizeofConfig = module._rac_wasm_sizeof_config;
  const adapterOffsetFn = module._rac_wasm_offsetof_config_platform_adapter;
  const logLevelOffsetFn = module._rac_wasm_offsetof_config_log_level;
  if (typeof sizeofConfig !== 'function' || typeof module._rac_init !== 'function'
    || typeof adapterOffsetFn !== 'function' || typeof logLevelOffsetFn !== 'function') {
    throw new Error('WASM module missing rac_init / config struct exports');
  }

  const configSize = sizeofConfig();
  const configPtr = module._malloc(configSize);
  try {
    for (let i = 0; i < configSize; i++) module.setValue(configPtr + i, 0, 'i8');
    module.setValue(configPtr + adapterOffsetFn(), adapterPtr, '*');
    module.setValue(configPtr + logLevelOffsetFn(), logLevel, 'i32');

    const rc = Number(module.ccall('rac_init', 'number', ['number'], [configPtr], { async: true }));
    if (rc !== RAC_OK) {
      const errPtr = module._rac_error_message?.(rc) ?? 0;
      const errMsg = errPtr ? module.UTF8ToString(errPtr) : `rac_init failed with code ${rc}`;
      throw new Error(`rac_init failed: ${errMsg}`);
    }
  } finally {
    module._free(configPtr);
  }
}

// Inference thread count for the ONNX/Sherpa backends. Small models (e.g. the
// VITS TTS voice) regress badly with a large ORT thread pool: the per-inference
// thread spawn/sync + SharedArrayBuffer contention dwarfs the parallelism and
// can be ~10x slower than single-threaded. Keep this low; 1-2 is the sweet spot
// for these small speech models. Tunable at runtime via
// RunAnywhere.setInferenceThreads() before loading a model.
const DEFAULT_INFERENCE_THREADS = 1;

function setInferenceThreads(module: BootModule): void {
  const set = module._rac_set_inference_threads;
  if (typeof set !== 'function') return;
  set(DEFAULT_INFERENCE_THREADS);
}

function setBaseDir(module: BootModule, baseDir: string): void {
  const setFn = module._rac_model_paths_set_base_dir;
  if (typeof setFn !== 'function') {
    logger.warning('WASM module missing _rac_model_paths_set_base_dir export; download path composition may fail');
    return;
  }
  const len = module.lengthBytesUTF8(baseDir) + 1;
  const ptr = module._malloc(len);
  try {
    module.stringToUTF8(baseDir, ptr, len);
    const rc = setFn(ptr);
    if (rc !== RAC_OK) logger.warning(`rac_model_paths_set_base_dir('${baseDir}') returned ${rc}`);
  } finally {
    module._free(ptr);
  }
}

// Prefer the JS-side transport (worker XHR) over the built-in emscripten_fetch
// path. emscripten_fetch issues its request with EMSCRIPTEN_FETCH_SYNCHRONOUS,
// which needs a separate proxying thread to run the blocking XHR; the web-next
// WASM is built single-threaded, so that path has no worker to proxy to and
// every request fails immediately with status=0. FetchHttpTransport runs the
// sync XHR directly from JS inside this worker, sidestepping that requirement.
function registerHttpTransport(module: BootModule): void {
  if (FetchHttpTransport.install(module as FetchHttpTransportModule) !== null) {
    return;
  }
  const register = module._rac_http_transport_register_emscripten;
  if (typeof register !== 'function') {
    logger.warning('WASM module missing HTTP transport exports; commons HTTP (auth/device/API) unavailable');
    return;
  }
  const rc = register();
  if (rc !== RAC_OK) logger.warning(`rac_http_transport_register_emscripten returned ${rc}`);
}

function runRegisterFns(module: BootModule, registerFns: string[]): void {
  for (const fn of registerFns) {
    const rc = Number(module.ccall(fn, 'number', [], []));
    if (rc !== RAC_OK && rc !== RAC_ERROR_MODULE_ALREADY_REGISTERED) {
      throw new Error(`${fn} failed with code ${rc}`);
    }
  }
}
