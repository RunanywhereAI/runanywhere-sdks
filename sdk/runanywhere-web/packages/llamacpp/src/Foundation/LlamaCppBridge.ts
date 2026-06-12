/**
 * LlamaCppBridge — V2 canonical proto-byte WASM bridge for `@runanywhere/web-llamacpp`.
 *
 * Loads `racommons-llamacpp.wasm` (CPU) or `racommons-llamacpp-webgpu.wasm` (WebGPU)
 * as a fully independent Emscripten module, registers the platform adapter,
 * runs `rac_init`, registers the unified llama.cpp backend (LLM + VLM in a
 * single call), then installs the loaded module on every core proto-byte
 * adapter through `setRunanywhereModule(...)`.
 *
 * This is intentionally MINIMAL — the heavy lifting (LLM/VLM/structured/tool
 * calling/embeddings/diffusion) flows through `@runanywhere/web` core's
 * proto-byte adapters (`LLMProtoAdapter`, `VLMProtoAdapter`, etc.) once the
 * module is installed on the singleton.
 */

import {
  completeNativePhase1ForModule,
  HTTPAdapter,
  // Shared browser rac_platform_adapter_t populator — single implementation
  // for core + every backend bridge (was a per-package copy).
  PlatformAdapter,
  ProtoErrorCode,
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  SDKException,
  SDKLogger,
  registerWasmModule,
  unregisterWasmModule,
  type AccelerationMode,
  type EmscriptenRunanywhereModule,
  type PlatformAdapterModule,
  type WasmCapability,
} from '@runanywhere/web/internal';

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

  // Model paths — set a synthetic base directory so the C++ download
  // orchestrator's `g_base_dir.empty()` check doesn't reject web paths.
  // Returns 0 on success (rac_result_t).
  _rac_model_paths_set_base_dir?(basePtr: number): number;

  // Smoke check
  _rac_wasm_ping?(): number;

  // Struct size/offset helpers used during init
  _rac_wasm_sizeof_platform_adapter?(): number;
  _rac_wasm_sizeof_config?(): number;
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;

  // Backend registration entry point — the unified llama.cpp backend
  // (LLM + VLM) is the SOLE reason this artifact exists, so the export is
  // required. The bridge fails fast if it is missing.
  _rac_backend_llamacpp_register(): number;

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

interface WebGPUAdapterLike {
  features?: {
    has(name: string): boolean;
  };
}

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
        -ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED,
        'LlamaCpp WASM not loaded. Call LlamaCPP.register() first.',
      );
    }
    return this._module;
  }

  get accelerationMode(): AccelerationMode {
    return this._accelerationMode;
  }

  /**
   * Whether the unified llama.cpp backend is registered. The C++ layer was
   * unified so a single `rac_backend_llamacpp_register()` call wires both
   * the LLM and VLM modalities — VLM is always available alongside LLM
   * when the backend registration succeeds.
   */
  get isVLMRegistered(): boolean {
    return this._loaded;
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
    // Drop this module from the capability registry — leaves the commons
    // module (and any sibling backend, e.g. ONNX) untouched. Per-capability
    // semantics: only capability slots that point at THIS module are
    // released.
    if (this._module) {
      unregisterWasmModule(this._module);
    }
    this._module = null;
    this._loaded = false;
    this._loading = null;
    this._accelerationMode = 'cpu';
  }

  private async _doLoad(acceleration: 'auto' | 'webgpu' | 'cpu'): Promise<void> {
    logger.info('Loading LlamaCpp WASM module...');
    try {
      const webgpuAvailable = acceleration !== 'cpu'
        ? await LlamaCppBridge.detectWebGPUWithJSPI()
        : false;
      if (acceleration === 'webgpu' && !webgpuAvailable) {
        logger.warning(
          'WebGPU acceleration was requested, but this browser adapter is missing required WebGPU/JSPI/shader-f16 support. Falling back to CPU.',
        );
      }
      const useWebGPU = acceleration !== 'cpu' && webgpuAvailable;
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
        printErr: (text) => logger.info(text),
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
      this._platformAdapter = new PlatformAdapter(
        this._module as unknown as PlatformAdapterModule,
      );
      this._platformAdapter.register();

      // Initialize RACommons core within this WASM module.
      // Set _loaded=true immediately after _rac_init succeeds so that _teardown()
      // will correctly call _rac_shutdown if an error is thrown later (e.g., during
      // backend registration or registerWasmModule). _teardown() gates the shutdown
      // call on `this._module && this._loaded`, so this flag doubles as the
      // "rac_init was called" marker.
      await this._initRACommons(this._platformAdapter.getAdapterPtr());
      this._loaded = true;
      completeNativePhase1ForModule(this._module);

      // Register the unified llama.cpp backend (LLM + VLM in one call).
      await this._registerBackend();

      // Register against the capabilities this artifact actually serves.
      // The llama.cpp module also has the commons C++ code linked in (every
      // backend WASM does), but the SDK facade routes commons-level calls
      // (init, model registry, lifecycle, events) to the dedicated core
      // WASM via `registerWasmModule(['commons'], …)` — so we deliberately
      // do NOT claim 'commons' here. That keeps `RunAnywhere.initialize()`
      // and sibling-backend lookups stable across LlamaCPP.register() +
      // ONNX.register() in either order.
      const capabilities: WasmCapability[] = [
        'llm',
        'vlm',
        'embedding',
        'rag',
        'diffusion',
        'structured-output',
        'tool-calling',
        'lora',
      ];
      registerWasmModule(capabilities, this._module, ['llamacpp']);
      // HTTP transport — commons-level adapter. Install if no other
      // backend has bound it yet. ModelLifecycleAdapter + ModelRegistryAdapter
      // are bound by `registerWasmModule` because model load requires the
      // plugin registry that lives in this module (commons has no plugins).
      if (!HTTPAdapter.tryDefault()) {
        HTTPAdapter.setDefaultModule(this._module);
      }

      logger.info(`LlamaCpp WASM module loaded successfully (${this._accelerationMode})`);
    } catch (error) {
      // WebGPU → CPU fallback in 'auto' mode.
      // _teardown() handles _rac_shutdown (gated on _loaded, which is true only
      // if _rac_init completed), platformAdapter.cleanup() (removes addFunction'd
      // callbacks and frees the malloc'd rac_platform_adapter_t), and
      // unregisterWasmModule (releases any claimed capability slots). This makes
      // the resource release explicit and bounded rather than relying on GC.
      if (this._accelerationMode === 'webgpu' && acceleration === 'auto') {
        const reason = error instanceof Error ? error.message : String(error);
        logger.warning(`WebGPU WASM failed (${reason}), falling back to CPU`);
        this._teardown();
        return this._doLoad('cpu');
      }
      this._teardown();
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load LlamaCpp WASM: ${message}`);
      throw new SDKException(
        -ProtoErrorCode.ERROR_CODE_WASM_LOAD_FAILED,
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

      // platform_adapter offset — MUST come from the runtime helper; we do
      // not hard-code struct layouts. A missing export means the WASM build
      // is out of date; fail fast.
      if (typeof m._rac_wasm_offsetof_config_platform_adapter !== 'function') {
        throw new Error(
          'WASM module missing _rac_wasm_offsetof_config_platform_adapter export; ' +
          'rebuild racommons-llamacpp.wasm from wasm/src/wasm_exports.cpp.',
        );
      }
      const adapterOffset = m._rac_wasm_offsetof_config_platform_adapter();
      m.setValue(configPtr + adapterOffset, adapterPtr, '*');

      // log_level — INFO (2). Same runtime-helper contract.
      if (typeof m._rac_wasm_offsetof_config_log_level !== 'function') {
        throw new Error(
          'WASM module missing _rac_wasm_offsetof_config_log_level export; ' +
          'rebuild racommons-llamacpp.wasm from wasm/src/wasm_exports.cpp.',
        );
      }
      const logLevelOffset = m._rac_wasm_offsetof_config_log_level();
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

      // Web has no native filesystem root, but the C++ download
      // orchestrator rejects an empty base dir (g_base_dir.empty() causes
      // rac_model_paths_get_model_folder to fail with RAC_ERROR_NOT_FOUND).
      //
      // Install a synthetic prefix so path composition succeeds. The
      // PlatformAdapter's file_* callbacks operate on Emscripten's MEMFS using
      // whatever absolute path string is passed to them, so the prefix value
      // only needs to be non-empty and valid-looking — it does NOT need to map
      // to a real OS directory.
      this._setModelPathsBaseDir('/opfs');
    } finally {
      m._free(configPtr);
    }
  }

  /**
   * Install a synthetic model-paths base directory on the WASM-side
   * `g_base_dir` static. Missing export is treated as non-fatal — older WASM
   * builds without the export simply cannot support the C++ orchestrator
   * download path, but other proto APIs still function.
   */
  private _setModelPathsBaseDir(base: string): void {
    const m = this._module!;
    const setFn = m._rac_model_paths_set_base_dir;
    if (typeof setFn !== 'function') {
      logger.warning(
        'WASM module missing _rac_model_paths_set_base_dir export; ' +
        'C++ download orchestrator path composition may fail. ' +
        'Rebuild racommons-llamacpp.wasm with the latest wasm/CMakeLists.txt.',
      );
      return;
    }

    const len = m.lengthBytesUTF8(base) + 1;
    const ptr = m._malloc(len);
    try {
      m.stringToUTF8(base, ptr, len);
      const rc = setFn(ptr);
      if (rc !== 0) {
        logger.warning(`rac_model_paths_set_base_dir('${base}') returned ${rc}`);
      } else {
        logger.info(`Model paths base dir set to synthetic prefix '${base}'`);
      }
    } finally {
      m._free(ptr);
    }
  }

  /**
   * Register the unified llama.cpp backend. The C++ layer was unified so a
   * single `rac_backend_llamacpp_register()` call wires both the LLM and
   * VLM modalities — VLM is always available alongside LLM once registration
   * succeeds. A missing export or a non-success / non-already-registered
   * return code aborts module installation so callers never see
   * `LlamaCPP.isRegistered === true` against a stale or partially linked
   * WASM artifact.
   */
  private async _registerBackend(): Promise<void> {
    const m = this._module!;

    if (typeof m._rac_backend_llamacpp_register !== 'function') {
      throw new SDKException(
        -ProtoErrorCode.ERROR_CODE_WASM_LOAD_FAILED,
        'WASM module does not export _rac_backend_llamacpp_register; ' +
        'the racommons-llamacpp.wasm artifact is missing the llama.cpp ' +
        'backend. Rebuild it from sdk/runanywhere-web/wasm/CMakeLists.txt.',
      );
    }

    const llmResult = (await m.ccall(
      'rac_backend_llamacpp_register',
      'number',
      [],
      [],
      { async: true },
    )) as number;
    if (llmResult !== 0 && llmResult !== RAC_ERROR_MODULE_ALREADY_REGISTERED) {
      throw new SDKException(
        -ProtoErrorCode.ERROR_CODE_WASM_LOAD_FAILED,
        `llama.cpp backend registration failed: rac_backend_llamacpp_register returned ${llmResult}.`,
      );
    }
    logger.info(
      llmResult === RAC_ERROR_MODULE_ALREADY_REGISTERED
        ? 'llama.cpp backend already registered (treated as success; LLM + VLM)'
        : 'llama.cpp backend registered (LLM + VLM)',
    );
  }

  // -----------------------------------------------------------------------
  // WebGPU Detection (CPU + JSPI gate — same logic as the previous bridge)
  // -----------------------------------------------------------------------

  private static async detectWebGPUWithJSPI(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !('gpu' in navigator)) return false;
    try {
      const gpu = (navigator as Navigator & {
        gpu?: { requestAdapter(): Promise<WebGPUAdapterLike | null> };
      }).gpu;
      const adapter = await gpu?.requestAdapter();
      if (!adapter) return false;
      if (!adapter.features?.has('shader-f16')) return false;
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
