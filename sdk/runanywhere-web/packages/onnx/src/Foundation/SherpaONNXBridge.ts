/**
 * SherpaONNXBridge - V2 canonical ONNX backend bridge
 *
 * In the V2 architecture, STT/TTS/VAD inference flows entirely through the
 * RACommons proto-byte C ABI:
 *   `_rac_stt_component_*_proto`, `_rac_tts_component_*_proto`,
 *   `_rac_vad_component_*_proto`.
 *
 * Those exports are produced by the RACommons WASM module
 * (`racommons-llamacpp.wasm`, exposed by the `@runanywhere/web-llamacpp`
 * package). This bridge does NOT load `sherpa-onnx.wasm` directly — that
 * file is a standalone Sherpa-ONNX library used only by the legacy
 * direct-sherpa-JS path which V2 deletes.
 *
 * Responsibilities:
 *  1. Acquire the commons WASM module — either from a sibling backend that
 *     already called `setRunanywhereModule(...)` (preferred) or by loading
 *     `racommons-llamacpp.wasm` itself.
 *  2. If we loaded the module ourselves, call `rac_init()` and install it
 *     via `setRunanywhereModule(...)` so the proto-byte adapters in core
 *     can find it.
 *  3. Call `_rac_backend_onnx_register()` to register the ONNX (sherpa-onnx)
 *     vtable with the C++ plugin registry. After this, all proto-byte
 *     STT/TTS/VAD calls in core route through the registered backend.
 *
 * Backend availability requirement:
 *   The RACommons WASM module MUST be built with `RAC_WASM_ONNX=ON`
 *   (i.e. `npm run build:wasm -- --llamacpp --onnx`) so that
 *   `_rac_backend_onnx_register` is exported and `rac_backend_onnx` is
 *   linked. Without that, `register()` reports a typed
 *   `BackendNotAvailable` error and STT/TTS/VAD calls return null/error.
 */

import {
  SDKException,
  SDKLogger,
  completeDeferredServicesInitialization,
  completeNativePhase1ForModule,
  setRunanywhereModule,
  tryRunanywhereModule,
} from '@runanywhere/web/internal';
import type { EmscriptenRunanywhereModule } from '@runanywhere/web/internal';

const logger = new SDKLogger('SherpaONNXBridge');

/**
 * Subset of the Emscripten module surface we touch when the ONNX package
 * is the one loading the commons WASM (vs. piggy-backing on a module that
 * was already installed by a sibling package).
 */
interface CommonsModule extends EmscriptenRunanywhereModule {
  ccall?: (
    fname: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ) => unknown;
  _rac_wasm_ping?(): number;
  _rac_wasm_sizeof_platform_adapter?(): number;
  _rac_wasm_sizeof_config?(): number;
  _rac_set_platform_adapter?(adapterPtr: number): number;
  _rac_init?(configPtr: number): number;
  _rac_backend_onnx_register?(): number;
  _rac_backend_onnx_unregister?(): number;
}

/**
 * Module factory exposed by the `racommons-llamacpp.js` glue file. Emscripten
 * builds it with `MODULARIZE=1` so the default export is a factory that
 * returns a Promise of the module.
 */
type CommonsModuleFactory = (overrides?: Record<string, unknown>) => Promise<CommonsModule>;

export interface SherpaONNXBridgeLoadOptions {
  /**
   * Override URL to the `racommons-llamacpp.js` glue file. When omitted,
   * the bridge resolves it via `import.meta.url` so bundlers (Vite/webpack)
   * can rewrite the asset path correctly.
   */
  wasmUrl?: string;
}

/**
 * Singleton orchestrator for the ONNX backend. The TS surface is a thin
 * shell — all real STT/TTS/VAD work happens in C++ via the proto-byte
 * adapters in `@runanywhere/web` core.
 */
export class SherpaONNXBridge {
  private static _instance: SherpaONNXBridge | null = null;

  private _module: CommonsModule | null = null;
  private _backendRegistered = false;
  private _loaded = false;
  private _loading: Promise<void> | null = null;

  /** Override URL to `racommons-llamacpp.js`. Set before `register()`. */
  wasmUrl: string | null = null;

  static get shared(): SherpaONNXBridge {
    if (!SherpaONNXBridge._instance) {
      SherpaONNXBridge._instance = new SherpaONNXBridge();
    }
    return SherpaONNXBridge._instance;
  }

  get isLoaded(): boolean {
    return this._loaded;
  }

  get isBackendRegistered(): boolean {
    return this._backendRegistered;
  }

  /** Acquire/load the commons module and register the ONNX backend vtable. */
  async ensureLoaded(options?: SherpaONNXBridgeLoadOptions): Promise<void> {
    if (this._loaded) return;
    if (this._loading) {
      await this._loading;
      return;
    }
    this._loading = this._doLoad(options);
    try {
      await this._loading;
    } finally {
      this._loading = null;
    }
  }

  /** Unregister the ONNX backend vtable. Idempotent. */
  unregister(): void {
    if (!this._module || !this._backendRegistered) {
      this._loaded = false;
      return;
    }
    try {
      const rc = this._module._rac_backend_onnx_unregister?.() ?? 0;
      if (rc !== 0) {
        logger.warning(`rac_backend_onnx_unregister returned ${rc}`);
      }
    } catch (err) {
      logger.warning(
        `rac_backend_onnx_unregister threw: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    this._backendRegistered = false;
    this._loaded = false;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  private async _doLoad(options?: SherpaONNXBridgeLoadOptions): Promise<void> {
    logger.info('Loading ONNX backend (proto-byte commons C ABI)...');

    // Phase 1: Acquire the commons WASM module.
    const installed = tryRunanywhereModule() as CommonsModule | null;
    if (installed) {
      logger.info('Using already-installed RACommons module from sibling backend');
      this._module = installed;
    } else {
      this._module = await this._loadCommonsModule(options);

      // initialize commons + install the module in the singleton so the
      // proto-byte adapters in core can reach it.
      await this._initCommons(this._module);
      completeNativePhase1ForModule(this._module);
      setRunanywhereModule(this._module);
    }

    // Phase 2: Register the ONNX backend vtable.
    if (typeof this._module._rac_backend_onnx_register !== 'function') {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'The loaded RACommons WASM module does not export `rac_backend_onnx_register`. ' +
          'Rebuild the WASM with `npm run build:wasm -- --llamacpp --onnx` ' +
          'to include the sherpa-onnx STT/TTS/VAD backend.',
      );
    }

    const rc = await this._callMaybeAsync(this._module, 'rac_backend_onnx_register');
    if (rc !== 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        `rac_backend_onnx_register returned ${rc}.`,
      );
    }
    this._backendRegistered = true;
    this._loaded = true;
    await completeDeferredServicesInitialization();
    logger.info('ONNX backend registered (STT/TTS/VAD vtable installed)');
  }

  private async _loadCommonsModule(
    options?: SherpaONNXBridgeLoadOptions,
  ): Promise<CommonsModule> {
    const moduleUrl =
      options?.wasmUrl ??
      this.wasmUrl ??
      new URL('../../../llamacpp/wasm/racommons-llamacpp.js', import.meta.url).href;

    this.wasmUrl = moduleUrl;
    logger.info(`Loading RACommons WASM glue from ${moduleUrl}`);

    const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);

    let factory: CommonsModuleFactory;
    try {
      const imported = (await import(/* @vite-ignore */ moduleUrl)) as {
        default: CommonsModuleFactory;
      };
      factory = imported.default;
    } catch (err) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        `Failed to import RACommons glue at ${moduleUrl}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }

    let module: CommonsModule;
    try {
      module = await factory({
        print: (text: string) => logger.info(text),
        printErr: (text: string) => logger.error(text),
        locateFile: (path: string) => baseUrl + path,
      });
    } catch (err) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        `Failed to instantiate RACommons WASM: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }

    if (typeof module._rac_wasm_ping === 'function') {
      const ping = module._rac_wasm_ping();
      if (ping !== 42) {
        throw SDKException.backendNotAvailable(
          'ONNX.register',
          `RACommons WASM ping check failed (expected 42, got ${ping})`,
        );
      }
    }

    return module;
  }

  /**
   * Call `rac_init()` with a zero-initialised `rac_config_t`. We rely on the
   * defaults — no platform adapter is registered from the ONNX package
   * because those callbacks belong to whichever backend owns the module.
   * Sibling backends (LlamaCPP) install richer adapters; until they re-land
   * the ONNX-only path leaves all platform callbacks NULL, which the C++
   * core handles gracefully (logging falls back to stderr, file ops fail
   * with `RAC_ERROR_FEATURE_NOT_AVAILABLE`).
   */
  private async _initCommons(module: CommonsModule): Promise<void> {
    if (typeof module._rac_init !== 'function' || typeof module._malloc !== 'function') {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'RACommons WASM module is missing _rac_init or _malloc.',
      );
    }

    const sizeofConfig = module._rac_wasm_sizeof_config?.() ?? 0;
    const configPtr = sizeofConfig > 0 ? module._malloc(sizeofConfig) : 0;
    try {
      if (configPtr && module.HEAPU8) {
        module.HEAPU8.fill(0, configPtr, configPtr + sizeofConfig);
      }
      const rc = await this._callMaybeAsync(module, 'rac_init', ['number'], [configPtr]);
      if (rc !== 0) {
        throw SDKException.backendNotAvailable(
          'ONNX.register',
          `rac_init returned ${rc}.`,
        );
      }
    } finally {
      if (configPtr) module._free(configPtr);
    }
    logger.info('RACommons initialized (rac_init returned 0)');
  }

  /**
   * Invoke an exported C function via `ccall`, awaiting a Promise when the
   * module was built with ASYNCIFY/JSPI.
   */
  private async _callMaybeAsync(
    module: CommonsModule,
    name: string,
    argTypes: string[] = [],
    args: unknown[] = [],
  ): Promise<number> {
    const ccall = module.ccall;
    if (typeof ccall !== 'function') {
      const fn = (module as unknown as Record<string, unknown>)[`_${name}`] as
        | ((...rest: number[]) => number)
        | undefined;
      if (typeof fn !== 'function') {
        throw SDKException.backendNotAvailable(
          'ONNX.register',
          `RACommons WASM module is missing _${name}.`,
        );
      }
      return fn(...(args as number[])) ?? 0;
    }
    const result = ccall(name, 'number', argTypes, args, { async: true });
    if (result instanceof Promise) {
      return (await result) as number;
    }
    return (result as number) ?? 0;
  }
}
