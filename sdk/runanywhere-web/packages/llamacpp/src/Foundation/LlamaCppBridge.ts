/**
 * LlamaCppBridge — V2 canonical proto-byte WASM bridge for `@runanywhere/web-llamacpp`.
 *
 * Loads `racommons-llamacpp.wasm` (CPU) or `racommons-llamacpp-webgpu.wasm` (WebGPU)
 * as a fully independent Emscripten module, registers the platform adapter,
 * runs `rac_init`, registers the llama.cpp + llama.cpp-VLM backends, then
 * installs the loaded module on every core proto-byte adapter through
 * `setRunanywhereModule(...)`.
 *
 * This is intentionally MINIMAL — the heavy lifting (LLM/VLM/structured/tool
 * calling/embeddings/diffusion) flows through `@runanywhere/web` core's
 * proto-byte adapters (`LLMProtoAdapter`, `VLMProtoAdapter`, etc.) once the
 * module is installed on the singleton.
 */

import {
  HTTPAdapter,
  ModelRegistryAdapter,
  SDKException,
  SDKErrorCode,
  SDKLogger,
  clearRunanywhereModule,
  setRunanywhereModule,
  type AccelerationMode,
  type EmscriptenRunanywhereModule,
} from '@runanywhere/web';

import { PlatformAdapter } from './PlatformAdapter';

const logger = new SDKLogger('LlamaCppBridge');

// ---------------------------------------------------------------------------
// LlamaCppModule — extends the typed core module surface with the few
// LLAMACPP-specific exports the bridge needs (rac_init, ping, sizeof helpers,
// platform adapter setter, backend register entry points).
// ---------------------------------------------------------------------------

export interface LlamaCppModule extends EmscriptenRunanywhereModule {
  // Core init / shutdown
  _rac_init?(configPtr: number): number;
  _rac_shutdown?(): void;
  _rac_set_platform_adapter?(adapterPtr: number): number;
  _rac_error_message?(code: number): number;

  // Smoke check
  _rac_wasm_ping?(): number;

  // Struct size/offset helpers used during init
  _rac_wasm_sizeof_platform_adapter?(): number;
  _rac_wasm_sizeof_config?(): number;
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;

  // Backend registration entry points
  _rac_backend_llamacpp_register?(): number;
  _rac_backend_llamacpp_vlm_register?(): number;

  // Emscripten runtime helpers (loose-typed; not on the core proto module surface)
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
  ccall(
    ident: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;

  // HEAPU8 / HEAP32 / HEAPU32 are inherited (required, readonly) from
  // EmscriptenRunanywhereModule. The Emscripten runtime always exposes them
  // after the module factory resolves.

  // Optional Emscripten FS pieces used by the platform adapter file callbacks.
  FS?: {
    analyzePath(path: string): { exists: boolean };
    readFile(path: string): Uint8Array;
    writeFile(path: string, data: Uint8Array): void;
    unlink(path: string): void;
    mkdir?(path: string): void;
  };
  FS_createPath?(parent: string, path: string, canRead: boolean, canWrite: boolean): void;

  // Generic key index for any other rac_* exports the proto-byte adapters consume.
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Glue-loader factory shape — Emscripten's `MODULARIZE=1`/`EXPORT_ES6=1`
// outputs a `default` async factory that resolves to a typed module.
// ---------------------------------------------------------------------------

interface CreateModuleOptions {
  print?: (text: string) => void;
  printErr?: (text: string) => void;
  locateFile?: (path: string) => string;
}
type CreateModuleFn = (options?: CreateModuleOptions) => Promise<LlamaCppModule>;

// ---------------------------------------------------------------------------
// LlamaCppBridge — singleton WASM loader
// ---------------------------------------------------------------------------

export class LlamaCppBridge {
  private static _instance: LlamaCppBridge | null = null;

  private _module: LlamaCppModule | null = null;
  private _loaded = false;
  private _loading: Promise<void> | null = null;
  private _accelerationMode: AccelerationMode = 'cpu';
  private _platformAdapter: PlatformAdapter | null = null;

  /** Override the default URL to the racommons-llamacpp.js glue file (CPU). */
  wasmUrl: string | null = null;
  /** Override the URL for the WebGPU variant glue file. */
  webgpuWasmUrl: string | null = null;

  static get shared(): LlamaCppBridge {
    if (!LlamaCppBridge._instance) {
      LlamaCppBridge._instance = new LlamaCppBridge();
    }
    return LlamaCppBridge._instance;
  }

  get isLoaded(): boolean {
    return this._loaded && this._module !== null;
  }

  get module(): LlamaCppModule {
    if (!this._module) {
      throw new SDKException(
        SDKErrorCode.WASMNotLoaded,
        'LlamaCpp WASM not loaded. Call LlamaCPP.register() first.',
      );
    }
    return this._module;
  }

  get accelerationMode(): AccelerationMode {
    return this._accelerationMode;
  }

  // -----------------------------------------------------------------------
  // Loading
  // -----------------------------------------------------------------------

  async ensureLoaded(acceleration: 'auto' | 'webgpu' | 'cpu' = 'auto'): Promise<void> {
    if (this._loaded) return;
    if (this._loading) {
      await this._loading;
      return;
    }
    this._loading = this._doLoad(acceleration);
    try {
      await this._loading;
    } finally {
      this._loading = null;
    }
  }

  /**
   * Switch the acceleration mode by tearing down the current WASM module and
   * re-loading the variant for the requested mode.
   */
  async switchToAcceleration(mode: 'webgpu' | 'cpu'): Promise<void> {
    if (this._accelerationMode === mode && this._loaded) return;
    if (this._loading) {
      await this._loading;
      if (this._accelerationMode === mode) return;
    }

    logger.info(`Switching LlamaCpp acceleration mode: ${this._accelerationMode} → ${mode}`);
    this._teardown();

    this._loading = this._doLoad(mode);
    try {
      await this._loading;
    } finally {
      this._loading = null;
    }
  }

  private _teardown(): void {
    if (this._module && this._loaded) {
      try {
        this._module._rac_shutdown?.();
      } catch { /* ignore */ }
    }
    if (this._platformAdapter) {
      try { this._platformAdapter.cleanup(); } catch { /* ignore */ }
      this._platformAdapter = null;
    }
    HTTPAdapter.clearDefaultModule();
    ModelRegistryAdapter.clearDefaultModule();
    clearRunanywhereModule();
    this._module = null;
    this._loaded = false;
    this._loading = null;
    this._accelerationMode = 'cpu';
  }

  private async _doLoad(acceleration: 'auto' | 'webgpu' | 'cpu'): Promise<void> {
    logger.info('Loading LlamaCpp WASM module...');
    try {
      const useWebGPU =
        acceleration === 'webgpu' ||
        (acceleration === 'auto' && (await LlamaCppBridge.detectWebGPUWithJSPI()));
      this._accelerationMode = useWebGPU ? 'webgpu' : 'cpu';

      const moduleUrl = useWebGPU
        ? (this.webgpuWasmUrl
          ?? new URL('../../wasm/racommons-llamacpp-webgpu.js', import.meta.url).href)
        : (this.wasmUrl
          ?? new URL('../../wasm/racommons-llamacpp.js', import.meta.url).href);
      logger.info(`Loading ${useWebGPU ? 'WebGPU' : 'CPU'} variant: ${moduleUrl}`);

      if (useWebGPU) this.webgpuWasmUrl = moduleUrl;
      else this.wasmUrl = moduleUrl;

      // Dynamic import of Emscripten glue JS (vite-friendly).
      const glue = (await import(/* @vite-ignore */ moduleUrl)) as { default: CreateModuleFn };
      const createModule = glue.default;

      // Derive the base URL so the Emscripten glue resolves the companion
      // .wasm binary from the same directory regardless of bundler output.
      const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);

      this._module = await createModule({
        print: (text) => logger.info(text),
        printErr: (text) => logger.error(text),
        locateFile: (path) => baseUrl + path,
      });

      // Smoke check
      const pingFn = this._module._rac_wasm_ping;
      if (typeof pingFn !== 'function') {
        throw new Error('WASM module missing _rac_wasm_ping export');
      }
      const pingResult = pingFn();
      const ping = typeof pingResult === 'object' && pingResult !== null && 'then' in pingResult
        ? await (pingResult as Promise<number>)
        : pingResult;
      if (ping !== 42) {
        throw new Error(`WASM ping failed: expected 42, got ${ping}`);
      }

      // Register platform adapter (browser callbacks for log/file/secure/etc.)
      this._platformAdapter = new PlatformAdapter(this._module);
      this._platformAdapter.register();

      // Initialize RACommons core within this WASM module
      await this._initRACommons(this._platformAdapter.getAdapterPtr());

      // Register the llama.cpp backend (and the VLM variant if available).
      await this._registerBackend();

      // Install the module on every core adapter so proto-byte calls can find
      // it without taking a hard dependency on this backend package.
      setRunanywhereModule(this._module);
      HTTPAdapter.setDefaultModule(this._module);
      ModelRegistryAdapter.setDefaultModule(this._module);

      this._loaded = true;
      logger.info(`LlamaCpp WASM module loaded successfully (${this._accelerationMode})`);
    } catch (error) {
      // WebGPU → CPU fallback in 'auto' mode
      if (this._accelerationMode === 'webgpu' && acceleration === 'auto') {
        const reason = error instanceof Error ? error.message : String(error);
        logger.warning(`WebGPU WASM failed (${reason}), falling back to CPU`);
        this._module = null;
        this._loaded = false;
        this._accelerationMode = 'cpu';
        return this._doLoad('cpu');
      }
      this._module = null;
      this._loaded = false;
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load LlamaCpp WASM: ${message}`);
      throw new SDKException(
        SDKErrorCode.WASMLoadFailed,
        `Failed to load LlamaCpp WASM module: ${message}`,
      );
    }
  }

  private async _initRACommons(adapterPtr: number): Promise<void> {
    const m = this._module!;
    const sizeofConfig = m._rac_wasm_sizeof_config;
    const racInit = m._rac_init;
    if (typeof sizeofConfig !== 'function' || typeof racInit !== 'function') {
      throw new Error('WASM module missing rac_init / rac_wasm_sizeof_config exports');
    }

    const configSize = sizeofConfig();
    const configPtr = m._malloc(configSize);
    try {
      // Zero-init the entire struct
      for (let i = 0; i < configSize; i++) {
        m.setValue(configPtr + i, 0, 'i8');
      }

      // platform_adapter is the first field (offset 0). Use the runtime
      // offset helper if it's exported so we don't bake the layout in.
      const adapterOffset = typeof m._rac_wasm_offsetof_config_platform_adapter === 'function'
        ? m._rac_wasm_offsetof_config_platform_adapter()
        : 0;
      m.setValue(configPtr + adapterOffset, adapterPtr, '*');

      // log_level — INFO (2). Same fallback approach.
      const logLevelOffset = typeof m._rac_wasm_offsetof_config_log_level === 'function'
        ? m._rac_wasm_offsetof_config_log_level()
        : 4; // pointer (4) on wasm32
      m.setValue(configPtr + logLevelOffset, 2, 'i32');

      const result = (await m.ccall(
        'rac_init',
        'number',
        ['number'],
        [configPtr],
        { async: true },
      )) as number;

      if (result !== 0) {
        const errPtr = m._rac_error_message?.(result) ?? 0;
        const errMsg = errPtr ? m.UTF8ToString(errPtr) : `rac_init failed with code ${result}`;
        throw new Error(`rac_init failed in LlamaCpp module: ${errMsg}`);
      }
      logger.info('RACommons initialized within LlamaCpp WASM module');
    } finally {
      m._free(configPtr);
    }
  }

  private async _registerBackend(): Promise<void> {
    const m = this._module!;
    if (typeof m._rac_backend_llamacpp_register === 'function') {
      const result = (await m.ccall(
        'rac_backend_llamacpp_register',
        'number',
        [],
        [],
        { async: true },
      )) as number;
      if (result === 0) {
        logger.info('llama.cpp backend registered');
      } else {
        logger.warning(`llama.cpp backend registration returned: ${result}`);
      }
    } else {
      logger.warning('WASM module does not export _rac_backend_llamacpp_register');
    }

    if (typeof m._rac_backend_llamacpp_vlm_register === 'function') {
      const result = (await m.ccall(
        'rac_backend_llamacpp_vlm_register',
        'number',
        [],
        [],
        { async: true },
      )) as number;
      if (result === 0) {
        logger.info('llama.cpp VLM backend registered');
      }
    }
  }

  // -----------------------------------------------------------------------
  // WebGPU Detection (CPU + JSPI gate — same logic as the previous bridge)
  // -----------------------------------------------------------------------

  private static async detectWebGPUWithJSPI(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !('gpu' in navigator)) return false;
    try {
      const gpu = (navigator as Navigator & { gpu?: { requestAdapter(): Promise<unknown> } }).gpu;
      const adapter = await gpu?.requestAdapter();
      if (!adapter) return false;
      const wasm = WebAssembly as unknown as { promising?: unknown; Suspending?: unknown };
      return typeof WebAssembly !== 'undefined' && 'promising' in wasm && 'Suspending' in wasm;
    } catch {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Cleanup
  // -----------------------------------------------------------------------

  shutdown(): void {
    this._teardown();
    LlamaCppBridge._instance = null;
    logger.info('LlamaCpp bridge shut down');
  }
}
