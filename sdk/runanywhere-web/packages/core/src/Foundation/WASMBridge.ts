/**
 * RunAnywhere Web SDK - WASM Bridge
 *
 * Loads the RACommons WASM module and provides typed wrappers
 * around the C API functions. This is the web equivalent of:
 *   - CppBridge.swift (iOS)
 *   - CppBridge.kt (Kotlin/Android)
 *   - dart_bridge.dart (Flutter)
 *   - HybridRunAnywhereCore.cpp (React Native)
 */

import { SDKError, SDKErrorCode } from './ErrorTypes';
import { SDKLogger } from './SDKLogger';

// ---------------------------------------------------------------------------
// Acceleration Mode
// ---------------------------------------------------------------------------

/** The hardware acceleration mode used by the loaded WASM module. */
export type AccelerationMode = 'webgpu' | 'cpu';

// ---------------------------------------------------------------------------
// Emscripten Module Type
// ---------------------------------------------------------------------------

/**
 * Emscripten module interface.
 * Defines the functions available on the loaded WASM module.
 */
export interface RACommonsModule extends EmscriptenModule {
  // -- Emscripten runtime helpers --
  ccall: typeof ccall;
  cwrap: typeof cwrap;
  addFunction: (func: (...args: number[]) => number | void, signature: string) => number;
  removeFunction: (ptr: number) => void;
  UTF8ToString: (ptr: number, maxBytesToRead?: number) => string;
  stringToUTF8: (str: string, outPtr: number, maxBytesToWrite: number) => void;
  lengthBytesUTF8: (str: string) => number;
  setValue: (ptr: number, value: number, type: string) => void;
  getValue: (ptr: number, type: string) => number;
  FS: typeof FS;

  // -- Memory --
  _malloc: (size: number) => number;
  _free: (ptr: number) => void;

  // -- RACommons Core --
  _rac_init: (configPtr: number) => number;
  _rac_shutdown: () => void;
  _rac_is_initialized: () => number;
  _rac_configure_logging: (environment: number) => number;

  // -- Platform Adapter --
  _rac_set_platform_adapter: (adapterPtr: number) => number;
  _rac_log: (level: number, categoryPtr: number, messagePtr: number) => void;

  // -- Events --
  _rac_event_subscribe: (category: number, callbackPtr: number, userDataPtr: number) => number;
  _rac_event_subscribe_all: (callbackPtr: number, userDataPtr: number) => number;
  _rac_event_unsubscribe: (subscriptionId: number) => void;
  _rac_event_track: (type: number, category: number, destination: number, propsJsonPtr: number) => number;

  // -- Error --
  _rac_error_message: (code: number) => number;

  // -- Model Registry --
  _rac_model_registry_create: (outHandlePtr: number) => number;
  _rac_model_registry_destroy: (handle: number) => void;
  _rac_model_registry_get_all: (handle: number, outModelsPtr: number, outCountPtr: number) => number;
  _rac_model_info_free: (modelPtr: number) => void;
  _rac_model_info_array_free: (modelsPtr: number, count: number) => void;

  // -- LLM Component --
  _rac_llm_component_create: (outHandlePtr: number) => number;
  _rac_llm_component_configure: (handle: number, configPtr: number) => number;
  _rac_llm_component_load_model: (handle: number, pathPtr: number, idPtr: number, namePtr: number) => number;
  _rac_llm_component_unload: (handle: number) => number;
  _rac_llm_component_is_loaded: (handle: number) => number;
  _rac_llm_component_generate: (handle: number, promptPtr: number, optionsPtr: number, outResultPtr: number) => number;
  _rac_llm_component_generate_stream: (
    handle: number, promptPtr: number, optionsPtr: number,
    tokenCb: number, completeCb: number, errorCb: number, userData: number
  ) => number;
  _rac_llm_component_cancel: (handle: number) => number;
  _rac_llm_component_get_model_id: (handle: number) => number;
  _rac_llm_component_get_state: (handle: number) => number;
  _rac_llm_component_destroy: (handle: number) => void;
  _rac_llm_result_free: (resultPtr: number) => void;

  // -- VLM Component --
  _rac_vlm_component_create: (outHandlePtr: number) => number;
  _rac_vlm_component_load_model: (handle: number, modelPath: number, mmprojPath: number, modelId: number, modelName: number) => number;
  _rac_vlm_component_process: (handle: number, imagePtr: number, promptPtr: number, optionsPtr: number, resultPtr: number) => number;
  _rac_vlm_component_is_loaded: (handle: number) => number;
  _rac_vlm_component_destroy: (handle: number) => void;
  _rac_vlm_component_cancel: (handle: number) => void;
  _rac_vlm_result_free: (resultPtr: number) => void;

  // -- Backend Registration --
  _rac_backend_llamacpp_vlm_register: () => number;
  _rac_backend_llamacpp_vlm_unregister: () => void;

  // -- WASM Helpers --
  _rac_wasm_ping: () => number;
  _rac_wasm_sizeof_platform_adapter: () => number;
  _rac_wasm_sizeof_config: () => number;
  _rac_wasm_sizeof_llm_options: () => number;
  _rac_wasm_sizeof_llm_result: () => number;
  _rac_wasm_create_llm_options_default: () => number;
  _rac_wasm_sizeof_vlm_image: () => number;
  _rac_wasm_sizeof_vlm_options: () => number;
  _rac_wasm_sizeof_vlm_result: () => number;
  _rac_wasm_sizeof_diffusion_options: () => number;
  _rac_wasm_sizeof_diffusion_result: () => number;
  _rac_wasm_sizeof_embeddings_options: () => number;
  _rac_wasm_sizeof_embeddings_result: () => number;
  _rac_wasm_sizeof_structured_output_config: () => number;
  _rac_wasm_sizeof_voice_agent_config: () => number;
  _rac_wasm_sizeof_voice_agent_result: () => number;
  _rac_wasm_sizeof_stt_options: () => number;
  _rac_wasm_sizeof_stt_result: () => number;
  _rac_wasm_sizeof_tts_options: () => number;
  _rac_wasm_sizeof_tts_result: () => number;
  _rac_wasm_sizeof_vad_config: () => number;

  // -- SDK Config --
  _rac_sdk_init: (configPtr: number) => number;
  _rac_sdk_is_initialized: () => number;
  _rac_sdk_reset: () => void;

  // -- Telemetry --
  _rac_telemetry_manager_create: (env: number, deviceIdPtr: number, platformPtr: number, versionPtr: number) => number;
  _rac_telemetry_manager_destroy: (manager: number) => void;
}

// ---------------------------------------------------------------------------
// WASM Bridge
// ---------------------------------------------------------------------------

const logger = new SDKLogger('WASMBridge');

/**
 * WASMBridge - Loads and manages the RACommons WASM module.
 *
 * Singleton that provides access to all RACommons C API functions
 * compiled to WebAssembly. This is the central point through which
 * all SDK operations flow, identical to CppBridge on mobile platforms.
 */
export class WASMBridge {
  private static _instance: WASMBridge | null = null;
  private _module: RACommonsModule | null = null;
  private _loaded = false;
  private _loading: Promise<void> | null = null;
  private _accelerationMode: AccelerationMode = 'cpu';
  /** The URL that was used to load the WASM glue JS (for worker reuse). */
  private _loadedModuleUrl: string | null = null;

  static get shared(): WASMBridge {
    if (!WASMBridge._instance) {
      WASMBridge._instance = new WASMBridge();
    }
    return WASMBridge._instance;
  }

  /** Whether the WASM module is loaded */
  get isLoaded(): boolean {
    return this._loaded && this._module !== null;
  }

  /** Get the raw Emscripten module (throws if not loaded) */
  get module(): RACommonsModule {
    if (!this._module) {
      throw SDKError.wasmNotLoaded();
    }
    return this._module;
  }

  /** The hardware acceleration mode in use (webgpu or cpu). */
  get accelerationMode(): AccelerationMode {
    return this._accelerationMode;
  }

  /**
   * The URL of the WASM glue JS that was successfully loaded.
   * Web Workers should use this URL to load the same WASM variant
   * (WebGPU or CPU) that the main thread is using.
   *
   * Returns `null` if `load()` has not been called yet.
   */
  get workerWasmUrl(): string | null {
    return this._loadedModuleUrl;
  }

  /**
   * Load the RACommons WASM module.
   *
   * Detects WebGPU at init time and loads the appropriate build variant:
   *   - `racommons-webgpu.js` when WebGPU + JSPI are available
   *   - `racommons.js` as the CPU-only fallback
   *
   * Safe to call concurrently -- only the first caller triggers the actual
   * load; subsequent callers await the same in-flight promise.
   *
   * @param wasmUrl        - URL to the CPU-only racommons.js glue file.
   * @param webgpuWasmUrl  - URL to the WebGPU racommons-webgpu.js glue file.
   * @param acceleration   - Force a specific mode ('auto' detects, 'webgpu' forces GPU, 'cpu' forces CPU).
   */
  async load(
    wasmUrl?: string,
    webgpuWasmUrl?: string,
    acceleration: 'auto' | 'webgpu' | 'cpu' = 'auto',
  ): Promise<void> {
    if (this._loaded) {
      logger.debug('WASM module already loaded');
      return;
    }

    // Prevent duplicate loading -- return the in-flight promise
    if (this._loading) {
      await this._loading;
      return;
    }

    this._loading = this._doLoad(wasmUrl, webgpuWasmUrl, acceleration);
    try {
      await this._loading;
    } finally {
      this._loading = null;
    }
  }

  /**
   * Internal load implementation.
   * Separated from `load()` so the concurrent-load guard can wrap it.
   */
  private async _doLoad(
    wasmUrl?: string,
    webgpuWasmUrl?: string,
    acceleration: 'auto' | 'webgpu' | 'cpu' = 'auto',
  ): Promise<void> {
    logger.info('Loading RACommons WASM module...');

    try {
      // Determine whether to use the WebGPU variant
      const useWebGPU = await this.resolveAcceleration(acceleration);
      this._accelerationMode = useWebGPU ? 'webgpu' : 'cpu';

      // Select the correct module URL
      const moduleUrl = useWebGPU
        ? (webgpuWasmUrl ?? new URL('../../wasm/racommons-webgpu.js', import.meta.url).href)
        : (wasmUrl ?? new URL('../../wasm/racommons.js', import.meta.url).href);

      this._loadedModuleUrl = moduleUrl;
      logger.info(`Acceleration mode: ${this._accelerationMode} (loading ${useWebGPU ? 'racommons-webgpu' : 'racommons'})`);

      // Dynamic import of the Emscripten glue JS
      // The glue file exports a factory function: createRACommonsModule()
      const { default: createModule } = await import(/* @vite-ignore */ moduleUrl);

      // Instantiate the WASM module
      this._module = await createModule({
        // Emscripten module overrides
        print: (text: string) => logger.info(text),
        printErr: (text: string) => logger.error(text),
      }) as RACommonsModule;

      // Verify module loaded correctly
      const pingResult = this._module._rac_wasm_ping();
      if (pingResult !== 42) {
        throw new Error(`WASM ping failed: expected 42, got ${pingResult}`);
      }

      this._loaded = true;
      logger.info(`RACommons WASM module loaded successfully (${this._accelerationMode})`);
    } catch (error) {
      // If WebGPU load failed, fall back to CPU automatically
      if (this._accelerationMode === 'webgpu' && acceleration === 'auto') {
        logger.warning('WebGPU WASM module failed to load, falling back to CPU');
        this._accelerationMode = 'cpu';
        this._module = null;
        this._loaded = false;
        return this._doLoad(wasmUrl, undefined, 'cpu');
      }

      this._module = null;
      this._loaded = false;
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load WASM module: ${message}`);
      throw new SDKError(SDKErrorCode.WASMLoadFailed, `Failed to load WASM module: ${message}`);
    }
  }

  // -----------------------------------------------------------------------
  // WebGPU Detection
  // -----------------------------------------------------------------------

  /**
   * Determine whether to use WebGPU based on the acceleration preference
   * and actual browser capability.
   */
  private async resolveAcceleration(preference: 'auto' | 'webgpu' | 'cpu'): Promise<boolean> {
    if (preference === 'cpu') return false;

    const hasWebGPU = await WASMBridge.detectWebGPU();
    if (preference === 'webgpu' && !hasWebGPU) {
      logger.warning('WebGPU requested but not available; falling back to CPU');
      return false;
    }

    return hasWebGPU;
  }

  /**
   * Probe for a functional WebGPU adapter.
   * Returns true only when the browser exposes navigator.gpu AND
   * a valid adapter can be obtained.
   */
  static async detectWebGPU(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !('gpu' in navigator)) return false;
    try {
      const gpu = (navigator as NavigatorWithGPU).gpu;
      const adapter = await gpu?.requestAdapter();
      return adapter !== null;
    } catch {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // String Helpers
  // -----------------------------------------------------------------------

  /** Allocate a C string in WASM memory. Caller must free. */
  allocString(str: string): number {
    const m = this.module;
    const len = m.lengthBytesUTF8(str) + 1;
    const ptr = m._malloc(len);
    m.stringToUTF8(str, ptr, len);
    return ptr;
  }

  /** Read a C string from WASM memory */
  readString(ptr: number): string {
    if (ptr === 0) return '';
    return this.module.UTF8ToString(ptr);
  }

  /** Free WASM memory */
  free(ptr: number): void {
    if (ptr !== 0) {
      this.module._free(ptr);
    }
  }

  // -----------------------------------------------------------------------
  // Binary Data Helpers
  //
  // HEAPU8 / HEAPF32 may not be exported by the Emscripten module.
  // These helpers try the fast HEAPU8/HEAPF32 path first, then fall
  // back to byte-by-byte setValue/getValue which is always available.
  // -----------------------------------------------------------------------

  /**
   * Write a Uint8Array into WASM linear memory at `destPtr`.
   *
   * Fast path uses `HEAPU8.set()` when available (after WASM rebuild).
   * Fallback uses `setValue` byte-by-byte (works with any build).
   */
  writeBytes(src: Uint8Array, destPtr: number): void {
    const m = this.module;
    if ((m as any).HEAPU8) {
      (m as any).HEAPU8.set(src, destPtr);
      return;
    }
    for (let i = 0; i < src.length; i++) {
      m.setValue(destPtr + i, src[i], 'i8');
    }
  }

  /**
   * Read `length` bytes from WASM linear memory starting at `srcPtr`.
   *
   * Fast path uses `HEAPU8.slice()` when available.
   * Fallback uses `getValue` byte-by-byte.
   */
  readBytes(srcPtr: number, length: number): Uint8Array {
    const m = this.module;
    if ((m as any).HEAPU8) {
      return (m as any).HEAPU8.slice(srcPtr, srcPtr + length);
    }
    const result = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      result[i] = m.getValue(srcPtr + i, 'i8') & 0xFF;
    }
    return result;
  }

  /**
   * Read `count` float32 values from WASM linear memory starting at `srcPtr`.
   *
   * Fast path uses `HEAPF32` when available.
   * Fallback reads 4 bytes at a time via getValue('float').
   */
  readFloat32Array(srcPtr: number, count: number): Float32Array {
    const m = this.module;
    if ((m as any).HEAPF32) {
      const startIndex = srcPtr >> 2; // byte offset → float32 index
      return (m as any).HEAPF32.slice(startIndex, startIndex + count);
    }
    const result = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      result[i] = m.getValue(srcPtr + i * 4, 'float');
    }
    return result;
  }

  /**
   * Write a Float32Array into WASM linear memory at `destPtr`.
   * `destPtr` must be 4-byte aligned.
   *
   * Fast path uses `HEAPF32.set()` when available.
   * Fallback uses `setValue` with 'float'.
   */
  writeFloat32Array(src: Float32Array, destPtr: number): void {
    const m = this.module;
    if ((m as any).HEAPF32) {
      (m as any).HEAPF32.set(src, destPtr >> 2);
      return;
    }
    for (let i = 0; i < src.length; i++) {
      m.setValue(destPtr + i * 4, src[i], 'float');
    }
  }

  /**
   * Read a single float32 value from WASM linear memory.
   */
  readFloat32(ptr: number): number {
    const m = this.module;
    if ((m as any).HEAPF32) {
      return (m as any).HEAPF32[ptr >> 2];
    }
    return m.getValue(ptr, 'float');
  }

  // -----------------------------------------------------------------------
  // C API Wrappers
  // -----------------------------------------------------------------------

  /** Check a rac_result_t and throw SDKError if not success */
  checkResult(result: number, operation: string): void {
    if (result !== 0) {
      const errMsgPtr = this.module._rac_error_message(result);
      const errMsg = this.readString(errMsgPtr);
      throw SDKError.fromRACResult(result, `${operation}: ${errMsg}`);
    }
  }

  /** Get RACommons error message for a result code */
  getErrorMessage(resultCode: number): string {
    const ptr = this.module._rac_error_message(resultCode);
    return this.readString(ptr);
  }

  // -----------------------------------------------------------------------
  // Cleanup
  // -----------------------------------------------------------------------

  /** Shutdown the WASM module */
  shutdown(): void {
    if (this._module && this._loaded) {
      try {
        this._module._rac_shutdown();
      } catch {
        // Ignore shutdown errors
      }
    }
    this._module = null;
    this._loaded = false;
    this._loading = null;
    this._accelerationMode = 'cpu';
    this._loadedModuleUrl = null;
    WASMBridge._instance = null;
    logger.info('WASM bridge shut down');
  }
}

// Re-export for convenience
export type { EmscriptenModule };

// Emscripten type stubs (these come from the Emscripten glue code at runtime)
declare function ccall(
  ident: string, returnType: string | null,
  argTypes: string[], args: unknown[], opts?: object
): unknown;

declare function cwrap(
  ident: string, returnType: string | null,
  argTypes: string[]
): (...args: unknown[]) => unknown;

// Emscripten FS type stub
declare const FS: {
  mkdir: (path: string) => void;
  writeFile: (path: string, data: Uint8Array) => void;
  readFile: (path: string) => Uint8Array;
  unlink: (path: string) => void;
  stat: (path: string) => { size: number };
  analyzePath: (path: string) => { exists: boolean };
  mount: (type: unknown, opts: unknown, mountpoint: string) => void;
  syncfs: (populate: boolean, callback: (err: unknown) => void) => void;
};

// Emscripten module base type
interface EmscriptenModule {
  onRuntimeInitialized?: () => void;
  print?: (text: string) => void;
  printErr?: (text: string) => void;
}

// WebGPU navigator type stub
interface NavigatorWithGPU extends Navigator {
  gpu?: {
    requestAdapter: () => Promise<unknown | null>;
  };
}
