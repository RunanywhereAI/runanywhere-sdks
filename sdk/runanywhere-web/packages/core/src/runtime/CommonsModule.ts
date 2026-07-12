/**
 * CommonsModule — V2 canonical proto-byte WASM bridge for the
 * `@runanywhere/web` core package.
 *
 * Loads `racommons.{js,wasm}` from `packages/core/wasm/` as a fully
 * independent Emscripten module. The core WASM contains the SDK facade
 * surface (init, environment, auth, model registry, lifecycle, proto
 * events, etc.) — it does NOT contain LLM/VLM or STT/TTS/VAD backends.
 *
 * Backends are owned by sibling packages:
 *  - `@runanywhere/web-llamacpp` — loads its own `racommons-llamacpp.wasm`
 *    via `LlamaCppBridge` (LLM + VLM).
 *  - `@runanywhere/web-onnx` — loads its own `racommons-onnx-sherpa.wasm`
 *    via `SherpaONNXBridge` (STT + TTS + VAD).
 *
 * The TS facade layer routes each call to the appropriate bridge based on
 * the operation type. The core module exposed by this bridge serves the
 * SDK-state side of the facade (the calls in `RunAnywhere.initialize()`
 * and the readers in `RunAnywhere.isAuthenticated`, etc.).
 *
 * This bridge is intentionally MINIMAL — it loads the core WASM, runs
 * `rac_init`, completes native Phase 1, then installs the module via
 * `registerWasmModule(...)` so the proto-byte adapters can reach it.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';
import { ProtoErrorCode, SDKException } from '../Foundation/SDKException.js';
import { redactResourceURL } from '../Foundation/BackendContract.js';
import { PlatformAdapter, type PlatformAdapterModule } from './PlatformAdapter.js';
import { HTTPAdapter } from '../Adapters/HTTPAdapter.js';
import {
  DeviceRegistrationAdapter,
  type DeviceRegistrationConfiguration,
} from '../Adapters/DeviceRegistrationAdapter.js';
import {
  BrowserStorageAnalyzerAdapter,
  type BrowserStorageAnalyzerModule,
} from '../Adapters/StorageAdapter.js';
import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter.js';
import {
  getModuleForCapability,
  registerWasmModule,
  unregisterWasmModule,
  type EmscriptenRunanywhereModule,
} from './EmscriptenModule.js';

// Note: `completeNativePhase1ForModule` is reached through a lazy
// dynamic import to avoid a circular dependency with
// `../Public/RunAnywhere`, which imports CommonsModule for the V2
// initialize flow.

const logger = new SDKLogger('CommonsModule');

// ---------------------------------------------------------------------------
// CoreCommonsModule — extends the typed core module surface with the few
// core WASM exports the bridge needs (rac_init, ping, sizeof/offset helpers).
// ---------------------------------------------------------------------------

export interface CoreCommonsModule extends EmscriptenRunanywhereModule {
  // Core init / shutdown
  _rac_init?(configPtr: number): number;
  _rac_shutdown?(): void;
  _rac_set_platform_adapter?(adapterPtr: number): number;
  _rac_error_message?(code: number): number;

  // Synthetic base directory hook (mirrors LlamaCppBridge — the C++
  // download orchestrator rejects empty base dirs).
  _rac_model_paths_set_base_dir?(basePtr: number): number;

  // Smoke check
  _rac_wasm_ping?(): number;

  // Struct size/offset helpers used during init
  _rac_wasm_sizeof_platform_adapter?(): number;
  _rac_wasm_sizeof_config?(): number;
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;

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
type CreateModuleFn = (options?: CreateModuleOptions) => Promise<CoreCommonsModule>;

// ---------------------------------------------------------------------------
// CommonsModule — singleton WASM loader for the core racommons artifact.
// ---------------------------------------------------------------------------

export class CommonsModule {
  private static _instance: CommonsModule | null = null;

  private _module: CoreCommonsModule | null = null;
  private _loaded = false;
  private _loading: Promise<void> | null = null;
  /** Browser platform adapter installed into this module's `rac_init`
   * config. `rac_init` enforces non-NULL mandatory slots (file/secure/log/
   * now_ms), so a zero stub is not valid — the shared `PlatformAdapter`
   * populates the same MEMFS/localStorage/console callbacks the backend
   * bridges use. Lifetime matches the module. */
  private _platformAdapter: PlatformAdapter | null = null;
  /** Browser callbacks installed into commons' native device manager. */
  private _deviceRegistrationAdapter: DeviceRegistrationAdapter | null = null;
  /** Browser filesystem/quota callbacks and native storage-analyzer handle. */
  private _storageAnalyzerAdapter: BrowserStorageAnalyzerAdapter | null = null;

  /** Override the default URL to the racommons.js glue file. */
  wasmUrl: string | null = null;

  static get shared(): CommonsModule {
    if (!CommonsModule._instance) {
      CommonsModule._instance = new CommonsModule();
    }
    return CommonsModule._instance;
  }

  get isLoaded(): boolean {
    return this._loaded && this._module !== null;
  }

  get module(): CoreCommonsModule {
    if (!this._module) {
      throw new SDKException(
        -ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED,
        'Commons WASM not loaded. Call CommonsModule.shared.ensureLoaded() first.',
      );
    }
    return this._module;
  }

  // -----------------------------------------------------------------------
  // Loading
  // -----------------------------------------------------------------------

  async ensureLoaded(configuration: DeviceRegistrationConfiguration): Promise<void> {
    if (this._loaded) return;
    if (this._loading) {
      await this._loading;
      return;
    }
    this._loading = this._doLoad(configuration);
    try {
      await this._loading;
    } finally {
      this._loading = null;
    }
  }

  private _teardown(): void {
    if (this._storageAnalyzerAdapter) {
      try {
        this._storageAnalyzerAdapter.cleanup();
      } catch (error) {
        logger.warning(
          `BrowserStorageAnalyzerAdapter cleanup threw: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
      this._storageAnalyzerAdapter = null;
    }
    if (this._module) {
      try {
        this._module._rac_shutdown?.();
      } catch (error) {
        logger.warning(
          `rac_shutdown threw: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }
    if (this._deviceRegistrationAdapter) {
      try {
        this._deviceRegistrationAdapter.cleanup();
      } catch (error) {
        logger.warning(
          `DeviceRegistrationAdapter cleanup threw: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
      this._deviceRegistrationAdapter = null;
    }
    if (this._platformAdapter) {
      try {
        this._platformAdapter.cleanup();
      } catch (error) {
        logger.warning(
          `PlatformAdapter cleanup threw: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
      this._platformAdapter = null;
    }
    HTTPAdapter.clearDefaultModule();
    if (this._module) {
      // Drop ONLY this module from the registry adapter — siblings that
      // still hold the catalog stay untouched. `unregisterWasmModule`
      // below also performs this drop, so the explicit call here is just
      // defensive against an out-of-order shutdown sequence.
      ModelRegistryAdapter.unregisterModule(this._module);
      unregisterWasmModule(this._module);
    }
    this._module = null;
    this._loaded = false;
    this._loading = null;
  }

  private async _doLoad(configuration: DeviceRegistrationConfiguration): Promise<void> {
    // If a sibling backend has already registered for 'commons', reuse it —
    // the per-capability registry returns whichever module currently owns
    // the SDK-state surface. Avoids loading the core artifact twice when an
    // app calls `LlamaCPP.register()` (or another backend that claimed
    // 'commons') before `RunAnywhere.initialize()`.
    const existing = getModuleForCapability('commons') as CoreCommonsModule | null;
    if (existing) {
      logger.info('Reusing already-installed RACommons module from sibling backend');
      this._module = existing;
      this._deviceRegistrationAdapter = DeviceRegistrationAdapter.install(
        existing,
        configuration,
      );
      this._storageAnalyzerAdapter = await BrowserStorageAnalyzerAdapter.install(
        existing as unknown as BrowserStorageAnalyzerModule,
      );
      this._loaded = true;
      return;
    }

    logger.info('Loading Commons WASM module...');
    try {
      const moduleUrl = this.wasmUrl
        ?? new URL('../../wasm/racommons.js', import.meta.url).href;
      logger.info(`Loading core variant: ${redactResourceURL(moduleUrl)}`);
      this.wasmUrl = moduleUrl;

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

      // Initialize RACommons core within this WASM module. The core WASM
      // has no platform adapter callbacks — those belong to whichever
      // backend owns the file/secure/log surface. Without a backend the
      // commons module runs with NULL callbacks (stderr logging, file ops
      // return RAC_ERROR_FEATURE_NOT_AVAILABLE).
      await this._initRACommons();
      // Lazy import to avoid a static circular dependency with
      // `../Public/RunAnywhere`.
      const { completeNativePhase1ForModule } = await import('../Public/RunAnywhere.js');
      completeNativePhase1ForModule(this._module);

      // Register against the 'commons' capability so the SDK facade's
      // commons-level calls (init, auth, model registry, lifecycle, events,
      // hardware, downloads) reach this module via
      // `tryRunanywhereModule()` / `getModuleForCapability('commons')`.
      // We deliberately do NOT register modality capabilities — those are
      // owned by sibling backend bridges (LlamaCPP, ONNX). If no backend is
      // registered yet, modality verbs return `backendNotAvailable`, which
      // is the desired UX.
      registerWasmModule(['commons'], this._module);
      HTTPAdapter.setDefaultModule(this._module);
      ModelRegistryAdapter.setDefaultModule(this._module);
      this._deviceRegistrationAdapter = DeviceRegistrationAdapter.install(
        this._module,
        configuration,
      );
      this._storageAnalyzerAdapter = await BrowserStorageAnalyzerAdapter.install(
        this._module as unknown as BrowserStorageAnalyzerModule,
      );

      this._loaded = true;
      logger.info('Commons WASM module loaded successfully');
    } catch (error) {
      this._teardown();
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load Commons WASM: ${message}`);
      throw new SDKException(
        -ProtoErrorCode.ERROR_CODE_WASM_LOAD_FAILED,
        `Failed to load Commons WASM module: ${message}`,
      );
    }
  }

  private async _initRACommons(): Promise<void> {
    const m = this._module!;
    const sizeofConfig = m._rac_wasm_sizeof_config;
    const racInit = m._rac_init;
    if (typeof sizeofConfig !== 'function' || typeof racInit !== 'function') {
      throw new Error('WASM module missing rac_init / rac_wasm_sizeof_config exports');
    }

    // Install the full browser platform adapter (MEMFS file I/O,
    // localStorage secure storage, console log, Date.now, memory info,
    // vendor id). `rac_init` enforces that the mandatory adapter slots are
    // non-NULL, so the previous zero-callback stub is rejected with
    // "Platform adapter missing mandatory slot". Shared implementation with
    // the backend bridges (runtime/PlatformAdapter.ts).
    const adapter = new PlatformAdapter(m as unknown as PlatformAdapterModule);
    adapter.register();
    this._platformAdapter = adapter;
    const adapterPtr = adapter.getAdapterPtr();

    const configSize = sizeofConfig();
    const configPtr = m._malloc(configSize);
    try {
      // Zero-init the entire struct
      for (let i = 0; i < configSize; i++) {
        m.setValue(configPtr + i, 0, 'i8');
      }

      // platform_adapter offset → install the stub.
      if (typeof m._rac_wasm_offsetof_config_platform_adapter !== 'function') {
        throw new Error(
          'WASM module missing _rac_wasm_offsetof_config_platform_adapter export; ' +
          'rebuild racommons.wasm from wasm/src/wasm_exports.cpp.',
        );
      }
      const adapterOffset = m._rac_wasm_offsetof_config_platform_adapter();
      m.setValue(configPtr + adapterOffset, adapterPtr, '*');

      // log_level — INFO (2). Runtime helpers required so we don't silently
      // corrupt struct layout.
      if (typeof m._rac_wasm_offsetof_config_log_level !== 'function') {
        throw new Error(
          'WASM module missing _rac_wasm_offsetof_config_log_level export; ' +
          'rebuild racommons.wasm from wasm/src/wasm_exports.cpp.',
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
        // Release the adapter — rac_init didn't take ownership.
        if (this._platformAdapter) {
          this._platformAdapter.cleanup();
          this._platformAdapter = null;
        }
        const errPtr = m._rac_error_message?.(result) ?? 0;
        const errMsg = errPtr ? m.UTF8ToString(errPtr) : `rac_init failed with code ${result}`;
        throw new Error(`rac_init failed in Commons module: ${errMsg}`);
      }
      logger.info('RACommons initialized within Commons WASM module');

      // Synthetic model-paths base dir (mirrors LlamaCppBridge). The
      // C++ download orchestrator rejects an empty base dir. The
      // proto-byte file callbacks operate on absolute path strings, so
      // the prefix only needs to be non-empty and valid-looking — it does
      // NOT need to map to a real OS directory.
      this._setModelPathsBaseDir('/opfs');
    } finally {
      m._free(configPtr);
    }
  }

  private _setModelPathsBaseDir(base: string): void {
    const m = this._module!;
    const setFn = m._rac_model_paths_set_base_dir;
    if (typeof setFn !== 'function') {
      logger.warning(
        'WASM module missing _rac_model_paths_set_base_dir export; ' +
        'C++ download orchestrator path composition may fail. ' +
        'Rebuild racommons.wasm with the latest wasm/CMakeLists.txt.',
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

  // -----------------------------------------------------------------------
  // Cleanup
  // -----------------------------------------------------------------------

  shutdown(): void {
    this._teardown();
    CommonsModule._instance = null;
    logger.info('Commons bridge shut down');
  }
}
