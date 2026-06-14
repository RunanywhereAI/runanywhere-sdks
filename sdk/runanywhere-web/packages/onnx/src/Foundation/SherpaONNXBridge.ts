/**
 * SherpaONNXBridge - V2 canonical ONNX backend bridge.
 *
 * STT/TTS/VAD inference flows entirely through the RACommons proto-byte
 * C ABI (`_rac_stt_component_*_proto`, `_rac_tts_component_*_proto`,
 * `_rac_vad_component_*_proto`) exported by this bridge's dedicated
 * `racommons-onnx-sherpa.wasm` artifact.
 *
 * Responsibilities:
 *  1. Always load this package's own `racommons-onnx-sherpa.{js,wasm}`
 *     artifact as an independent Emscripten module. The bridge does not
 *     piggy-back on any other package's WASM module — the ONNX and
 *     Sherpa backend registration entry points
 *     (`_rac_backend_onnx_register` / `_rac_backend_sherpa_register`) are
 *     only exported by this artifact, so each ONNX bridge instance owns
 *     its own dedicated module.
 *  2. Call `rac_init()` with a zero-initialised platform-adapter stub and
 *     claim the speech/embedding/RAG capabilities on the per-capability
 *     registry so the core proto-byte adapters can resolve this module.
 *  3. Call `_rac_backend_onnx_register()` and
 *     `_rac_backend_sherpa_register()` to register the ONNX runtime and
 *     Sherpa speech vtables with the C++ plugin registry. After this, all
 *     proto-byte STT/TTS/VAD calls in core route through the registered
 *     backend.
 *
 * Backend availability requirement:
 *   The `racommons-onnx-sherpa.wasm` artifact MUST be built with ONNX
 *   Runtime WASM and Sherpa-ONNX WASM static archives linked, so
 *   `_rac_backend_onnx_register` and `_rac_backend_sherpa_register` are
 *   exported. Without both, `register()` reports a typed
 *   `BackendNotAvailable` error and STT/TTS/VAD calls stay unavailable.
 */

import {
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  SDKException,
  SDKLogger,
  completeDeferredServicesInitialization,
  completeNativePhase1ForModule,
  missingSpeechBackendExports,
  registerWasmModule,
  speechBackendRequirementMessage,
  unregisterWasmModule,
} from '@runanywhere/web/internal';
import type {
  EmscriptenRunanywhereModule,
  WasmCapability,
} from '@runanywhere/web/internal';

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
  /** Offset of `platform_adapter` within `rac_config_t`. Optional — see _initCommons. */
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_set_platform_adapter?(adapterPtr: number): number;
  _rac_init?(configPtr: number): number;
  _rac_shutdown?(): void;
  _rac_backend_onnx_register?(): number;
  _rac_backend_onnx_unregister?(): number;
  _rac_backend_sherpa_register?(): number;
  _rac_backend_sherpa_unregister?(): number;
}

/**
 * Module factory exposed by the `racommons-onnx-sherpa.js` glue file.
 * Emscripten builds it with `MODULARIZE=1` so the default export is a
 * factory that returns a Promise of the module.
 */
type CommonsModuleFactory = (overrides?: Record<string, unknown>) => Promise<CommonsModule>;

export interface SherpaONNXBridgeLoadOptions {
  /**
   * Override URL to the `racommons-onnx-sherpa.js` glue file. When omitted,
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
  private _onnxBackendRegistered = false;
  private _sherpaBackendRegistered = false;
  private _loaded = false;
  private _loading: Promise<void> | null = null;
  /**
   * Pointer to the zero-initialised `rac_platform_adapter_t` stub that
   * satisfies the non-null check in `rac_init`. Allocated in `_initCommons`,
   * freed when this bridge tears down the module install (see
   * `unregister()`). The pointer lifetime MUST outlive the WASM module's
   * `s_platform_adapter` static (which `rac_init` stores), otherwise the
   * C++ side dereferences freed memory on any post-init callback.
   */
  private _stubAdapterPtr = 0;
  /**
   * Function-table index of the log callback installed in the stub adapter.
   * Non-zero only when `_initCommons` successfully registered it; freed in
   * `unregister()` alongside `_stubAdapterPtr`.
   */
  private _stubLogCallbackPtr = 0;
  /**
   * `true` when this bridge has loaded the dedicated
   * `racommons-onnx-sherpa` WASM and called `_rac_init` on it (i.e.
   * `_doLoad` ran to completion). When ownership is held, `unregister()`
   * mirrors LlamaCppBridge teardown and calls `_rac_shutdown` plus
   * frees the stub platform-adapter allocation before dropping the
   * module from the capability registry.
   */
  private _bridgeOwnedInit = false;

  /** Override URL to `racommons-onnx-sherpa.js`. Set before `register()`. */
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
    return this._onnxBackendRegistered && this._sherpaBackendRegistered;
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

  /**
   * Unregister the ONNX/Sherpa backend vtables. Idempotent.
   *
   * Mirrors LlamaCppBridge teardown: drops the module from the
   * capability registry (releasing only the slots it owned —
   * STT/TTS/VAD/voice-agent), leaving siblings (commons, llamacpp) intact.
   * If this bridge held the module install, calls `_rac_shutdown` to
   * unwind C++ state too.
   */
  unregister(): void {
    if (!this._module || (!this._onnxBackendRegistered && !this._sherpaBackendRegistered)) {
      this._loaded = false;
      if (this._bridgeOwnedInit && this._module) {
        try {
          this._module._rac_shutdown?.();
        } catch (err) {
          logger.warning(
            `rac_shutdown threw: ${err instanceof Error ? err.message : String(err)}`,
          );
        }
        if (this._stubAdapterPtr) {
          this._module._free(this._stubAdapterPtr);
          this._stubAdapterPtr = 0;
        }
        if (this._stubLogCallbackPtr) {
          this._module.removeFunction(this._stubLogCallbackPtr);
          this._stubLogCallbackPtr = 0;
        }
        unregisterWasmModule(this._module);
        this._module = null;
        this._bridgeOwnedInit = false;
      }
      return;
    }
    if (this._sherpaBackendRegistered) {
      try {
        const rc = this._module._rac_backend_sherpa_unregister?.() ?? 0;
        if (rc !== 0) {
          logger.warning(`rac_backend_sherpa_unregister returned ${rc}`);
        }
      } catch (err) {
        logger.warning(
          `rac_backend_sherpa_unregister threw: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    if (this._onnxBackendRegistered) {
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
    }
    this._sherpaBackendRegistered = false;
    this._onnxBackendRegistered = false;
    this._loaded = false;

    if (this._bridgeOwnedInit) {
      try {
        this._module._rac_shutdown?.();
      } catch (err) {
        logger.warning(
          `rac_shutdown threw: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      if (this._stubAdapterPtr) {
        this._module._free(this._stubAdapterPtr);
        this._stubAdapterPtr = 0;
      }
      if (this._stubLogCallbackPtr) {
        this._module.removeFunction(this._stubLogCallbackPtr);
        this._stubLogCallbackPtr = 0;
      }
      unregisterWasmModule(this._module);
      this._module = null;
      this._bridgeOwnedInit = false;
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  private async _doLoad(options?: SherpaONNXBridgeLoadOptions): Promise<void> {
    logger.info('Loading ONNX/Sherpa backend (dedicated racommons-onnx-sherpa WASM)...');

    // Phase 1: Always load the dedicated ONNX+Sherpa WASM. Each per-package
    // WASM is a self-contained Emscripten module — the llamacpp WASM
    // (potentially already installed by a sibling LlamaCPP.register()) does
    // not export `_rac_backend_onnx_register` or `_rac_backend_sherpa_register`,
    // so we cannot reuse a sibling module. Each bridge owns its own module.
    this._module = await this._loadCommonsModule(options);

    // Initialize the commons code linked into this artifact, then register
    // for the speech capabilities ONLY (STT/TTS/VAD/voice-agent). The
    // commons module — installed by `CommonsModule.shared.ensureLoaded()`
    // during `RunAnywhere.initialize()` — owns the 'commons' capability;
    // the per-capability registry keeps siblings (LLM via llamacpp) safe
    // from being overwritten.
    try {
      await this._initCommons(this._module);
    } catch (err) {
      // _initCommons threw before _bridgeOwnedInit was set — free the stub
      // allocation and drop the module so a subsequent register() starts clean.
      if (this._stubAdapterPtr) {
        this._module._free(this._stubAdapterPtr);
        this._stubAdapterPtr = 0;
      }
      if (this._stubLogCallbackPtr) {
        this._module.removeFunction(this._stubLogCallbackPtr);
        this._stubLogCallbackPtr = 0;
      }
      this._module = null;
      throw err;
    }
    completeNativePhase1ForModule(this._module);
    // Claim speech + embedding + RAG. The dedicated racommons-onnx-sherpa
    // artifact exports `_rac_embeddings_embed_batch_proto` (in the BASE
    // export list — see `RAC_EXPORTED_FUNCTIONS_BASE` in
    // sdk/runanywhere-web/wasm/CMakeLists.txt) and the 6 `_rac_rag_*_proto`
    // symbols (gated by `RAC_BACKEND_RAG=ON`, which is the default — see
    // the `_onnx_exports` block around CMakeLists.txt line 1300). Claiming
    // both capabilities here makes `RAGProtoAdapter.tryDefault()` and the
    // embeddings adapter route to this module when the LlamaCpp bridge is
    // not registered (or when the caller wants ONNX-backed embeddings).
    // Registration order is last-writer-wins per capability, so apps that
    // also register LlamaCPP will still get the llama.cpp engine for RAG
    // unless ONNX is the more recent register call — match the platform
    // convention by listing both here and letting registration order
    // resolve the tie.
    const capabilities: WasmCapability[] = [
      'stt',
      'tts',
      'vad',
      'voice-agent',
      'embedding',
      'rag',
    ];
    registerWasmModule(capabilities, this._module, ['onnx', 'sherpa']);
    this._bridgeOwnedInit = true;

    // Phase 2: Register the ONNX + Sherpa backend vtables. Generic speech
    // component/proto exports are not enough for real STT/TTS/VAD inference.
    const missing = missingSpeechBackendExports(this._module);
    if (missing.length > 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        speechBackendRequirementMessage(missing),
      );
    }

    const rc = await this._callMaybeAsync(this._module, 'rac_backend_onnx_register');
    if (!this._isRegistrationSuccess(rc)) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        `rac_backend_onnx_register returned ${rc}.`,
      );
    }
    this._onnxBackendRegistered = true;

    const sherpaRc = await this._callMaybeAsync(this._module, 'rac_backend_sherpa_register');
    if (!this._isRegistrationSuccess(sherpaRc)) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        `rac_backend_sherpa_register returned ${sherpaRc}.`,
      );
    }
    this._sherpaBackendRegistered = true;
    this._loaded = true;
    await completeDeferredServicesInitialization();
    logger.info('ONNX + Sherpa backends registered (STT/TTS/VAD vtables installed)');
  }

  /**
   * Build the ordered list of candidate URLs from which to import the
   * `racommons-onnx-sherpa.js` Emscripten glue. The dedicated ONNX/Sherpa
   * artifact lives in this package's own `wasm/` folder, so we do not
   * need to probe sibling-package paths.
   */
  private _collectCommonsModuleCandidates(
    options?: SherpaONNXBridgeLoadOptions,
  ): string[] {
    const candidates: string[] = [];
    const explicit = options?.wasmUrl ?? this.wasmUrl;
    if (explicit) candidates.push(explicit);

    if (candidates.length === 0) {
      // Package-relative path — works in both monorepo dev (TS source
      // import.meta.url) and published-package layout (compiled dist/).
      try {
        candidates.push(
          new URL('../../wasm/racommons-onnx-sherpa.js', import.meta.url).href,
        );
      } catch {
        // import.meta.url not a base URL (rare) — skip.
      }
    }

    return candidates;
  }

  private async _loadCommonsModule(
    options?: SherpaONNXBridgeLoadOptions,
  ): Promise<CommonsModule> {
    const candidates = this._collectCommonsModuleCandidates(options);

    let moduleUrl: string | undefined;
    let factory: CommonsModuleFactory | undefined;
    let lastError: string = 'no candidate URLs were resolvable';
    for (const candidate of candidates) {
      try {
        const imported = (await import(/* @vite-ignore */ candidate)) as {
          default: CommonsModuleFactory;
        };
        factory = imported.default;
        moduleUrl = candidate;
        break;
      } catch (err) {
        lastError = err instanceof Error ? err.message : String(err);
        logger.debug(
          `RACommons ONNX glue not resolvable at ${candidate}: ${lastError}`,
        );
      }
    }

    if (!factory || !moduleUrl) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'Failed to import racommons-onnx-sherpa glue. ' +
        'Ensure `@runanywhere/web-onnx` is installed with its `wasm/` directory ' +
        'staged (run `npm run build:wasm -- --onnx` from sdk/runanywhere-web), ' +
        'or pass `{ wasmUrl }` to `ONNX.register()`. Last error: ' + lastError,
      );
    }

    this.wasmUrl = moduleUrl;
    logger.info(`Loading RACommons ONNX/Sherpa WASM glue from ${moduleUrl}`);

    const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);

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
        `Failed to instantiate racommons-onnx-sherpa WASM: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }

    if (typeof module._rac_wasm_ping === 'function') {
      const ping = module._rac_wasm_ping();
      if (ping !== 42) {
        throw SDKException.backendNotAvailable(
          'ONNX.register',
          `racommons-onnx-sherpa WASM ping check failed (expected 42, got ${ping})`,
        );
      }
    }

    return module;
  }

  /**
   * Call `rac_init()` with a `rac_config_t` whose `platform_adapter` field
   * points at a stub `rac_platform_adapter_t` populated with a log callback.
   * The log callback routes rac_log output to the browser console so that
   * backend-init failures (RAC_LOG_ERROR) are visible without requiring the
   * LlamaCpp module to also be loaded. All other adapter fields remain NULL —
   * the ONNX/Sherpa proto-byte surface does not exercise file/secure/now_ms
   * callbacks during STT/TTS/VAD inference, and the C++ side null-checks each
   * field before calling it.
   */
  private async _initCommons(module: CommonsModule): Promise<void> {
    if (typeof module._rac_init !== 'function' || typeof module._malloc !== 'function') {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'racommons-onnx-sherpa WASM module is missing _rac_init or _malloc.',
      );
    }

    const sizeofConfig = module._rac_wasm_sizeof_config?.() ?? 0;
    if (sizeofConfig === 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'racommons-onnx-sherpa WASM module is missing _rac_wasm_sizeof_config.',
      );
    }
    const adapterSize = module._rac_wasm_sizeof_platform_adapter?.() ?? 0;
    if (adapterSize === 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'racommons-onnx-sherpa WASM module is missing _rac_wasm_sizeof_platform_adapter.',
      );
    }
    const adapterPtr = module._malloc(adapterSize);
    if (adapterPtr && module.HEAPU8) {
      module.HEAPU8.fill(0, adapterPtr, adapterPtr + adapterSize);
    }
    // ABI guard fields (MUST be set even on the stub): rac_init rejects an
    // adapter whose abi_version/struct_size don't match the commons build.
    // 1 == RAC_PLATFORM_ADAPTER_ABI_VERSION (rac_platform_adapter.h:38).
    // Guarded on the offset exports so a pre-guard prebuilt WASM (which has
    // neither the exports nor the check) keeps working.
    const adapterOffsetOf = (name: string): number | null => {
      const fn = (module as unknown as Record<string, unknown>)[
        `_rac_wasm_offsetof_platform_adapter_${name}`
      ];
      return typeof fn === 'function' ? (fn as () => number)() : null;
    };
    const abiVersionOffset = adapterOffsetOf('abi_version');
    const structSizeOffset = adapterOffsetOf('struct_size');
    if (adapterPtr && module.HEAPU32 && abiVersionOffset !== null && structSizeOffset !== null) {
      module.HEAPU32[(adapterPtr + abiVersionOffset) >>> 2] = 1;
      module.HEAPU32[(adapterPtr + structSizeOffset) >>> 2] = adapterSize;
    }
    // Install log callback so rac_log output (including backend-init errors)
    // reaches the browser console. Offset comes from the runtime helper —
    // never hard-coded. void (*)(rac_log_level_t, const char*, const char*, void*)
    const logOffsetFn = (module as unknown as Record<string, unknown>)['_rac_wasm_offsetof_platform_adapter_log'];
    if (typeof logOffsetFn === 'function') {
      const logOffset = (logOffsetFn as () => number)();
      const logPtr = module.addFunction(
        (level: number, categoryPtr: number, messagePtr: number, _userData: number) => {
          const category = module.UTF8ToString(categoryPtr);
          const message = module.UTF8ToString(messagePtr);
          const prefix = `[RAC-ONNX:${category}]`;
          switch (level) {
            case 0: case 1: console.debug(prefix, message); break;
            case 2: console.info(prefix, message); break;
            case 3: console.warn(prefix, message); break;
            case 4: case 5: console.error(prefix, message); break;
            default: console.log(prefix, message);
          }
        },
        'viiii',
      );
      this._stubLogCallbackPtr = logPtr;
      module.HEAPU32[(adapterPtr + logOffset) >>> 2] = logPtr;
    }
    this._stubAdapterPtr = adapterPtr;

    if (typeof module._rac_wasm_offsetof_config_platform_adapter !== 'function') {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'racommons-onnx-sherpa WASM module is missing _rac_wasm_offsetof_config_platform_adapter export; rebuild racommons-onnx-sherpa.wasm.',
      );
    }
    const adapterOffset = module._rac_wasm_offsetof_config_platform_adapter();
    const configPtr = module._malloc(sizeofConfig);
    try {
      if (configPtr && module.HEAPU8) {
        module.HEAPU8.fill(0, configPtr, configPtr + sizeofConfig);
      }
      module.HEAPU32[(configPtr + adapterOffset) >>> 2] = adapterPtr;
      const rc = await this._callMaybeAsync(module, 'rac_init', ['number'], [configPtr]);
      if (!this._isRegistrationSuccess(rc)) {
        if (this._stubAdapterPtr) {
          module._free(this._stubAdapterPtr);
          this._stubAdapterPtr = 0;
        }
        if (this._stubLogCallbackPtr) {
          module.removeFunction(this._stubLogCallbackPtr);
          this._stubLogCallbackPtr = 0;
        }
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

  private _isRegistrationSuccess(rc: number): boolean {
    return rc === 0 || rc === RAC_ERROR_MODULE_ALREADY_REGISTERED;
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
          `racommons-onnx-sherpa WASM module is missing _${name}.`,
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
