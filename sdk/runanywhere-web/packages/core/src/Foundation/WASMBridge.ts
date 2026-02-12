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

  // -- WASM Helpers --
  _rac_wasm_ping: () => number;
  _rac_wasm_sizeof_platform_adapter: () => number;
  _rac_wasm_sizeof_config: () => number;
  _rac_wasm_sizeof_llm_options: () => number;
  _rac_wasm_sizeof_llm_result: () => number;
  _rac_wasm_create_llm_options_default: () => number;

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

  /**
   * Load the RACommons WASM module.
   *
   * @param wasmUrl - URL or path to the racommons.js glue file.
   *                  Defaults to looking in the same directory.
   */
  async load(wasmUrl?: string): Promise<void> {
    if (this._loaded) {
      logger.debug('WASM module already loaded');
      return;
    }

    logger.info('Loading RACommons WASM module...');

    try {
      // Dynamic import of the Emscripten glue JS
      // The glue file exports a factory function: createRACommonsModule()
      const moduleUrl = wasmUrl ?? new URL('../wasm/racommons.js', import.meta.url).href;

      // Import the ES module
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
      logger.info('RACommons WASM module loaded successfully');
    } catch (error) {
      this._module = null;
      this._loaded = false;
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load WASM module: ${message}`);
      throw new SDKError(SDKErrorCode.WASMLoadFailed, `Failed to load WASM module: ${message}`);
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
