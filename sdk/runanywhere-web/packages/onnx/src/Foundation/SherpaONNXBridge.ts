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
 *  2. Install the shared browser `PlatformAdapter`, call `rac_init()`, and
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
  PlatformAdapter,
  SDKException,
  SDKLogger,
  completeDeferredServicesInitialization,
  completeNativePhase1ForModule,
  missingSpeechBackendExports,
  registerWasmModule,
  speechBackendRequirementMessage,
  unregisterWasmModule,
  redactResourceURL,
} from '@runanywhere/web/backend';
import type {
  EmscriptenRunanywhereModule,
  PlatformAdapterModule,
  WasmCapability,
} from '@runanywhere/web/backend';

const logger = new SDKLogger('SherpaONNXBridge');
const NVIDIA_SEGFORMER_LICENSE_ENV =
  'RAC_ACCEPT_NVIDIA_SEGFORMER_NONCOMMERCIAL_LICENSE';

/**
 * Subset of the Emscripten module surface touched directly by the ONNX bridge.
 * The shared `PlatformAdapter` consumes the rest through
 * `PlatformAdapterModule`.
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
  _rac_wasm_sizeof_config?(): number;
  /** Offsets within `rac_config_t`. Optional — see _initCommons. */
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;
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
   * Shared browser adapter retained for the entire lifetime of this WASM
   * module. RACommons stores its struct pointer during `rac_init`, so the
   * callback table and allocation must remain alive until after
   * `_rac_shutdown` completes.
   */
  private _platformAdapter: PlatformAdapter | null = null;
  /**
   * `true` when this bridge has loaded the dedicated
   * `racommons-onnx-sherpa` WASM and called `_rac_init` on it (i.e.
   * `_doLoad` ran to completion). When ownership is held, `unregister()`
   * mirrors LlamaCppBridge teardown and calls `_rac_shutdown` plus
   * cleans up the shared platform adapter before dropping the module from the
   * capability registry.
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

  /**
   * Set the native provider's fail-closed license acknowledgement inside
   * this Emscripten process. The caller-facing boolean lives on
   * `ONNX.register(...)`; keeping the actual `setenv` here ensures it is
   * applied to the same private WASM instance that owns SegFormer inference.
   */
  acceptNvidiaSegformerNoncommercialLicense(): void {
    const module = this._module;
    if (!module || typeof module.ccall !== 'function') {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'The ONNX WASM module cannot record the SegFormer license acknowledgement.',
      );
    }
    const rc = module.ccall(
      'setenv',
      'number',
      ['string', 'string', 'number'],
      [NVIDIA_SEGFORMER_LICENSE_ENV, '1', 1],
    );
    if (rc !== 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        `Failed to record the SegFormer license acknowledgement (setenv returned ${String(rc)}).`,
      );
    }
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
    this._teardown();
  }

  /** Release backend registrations, native state, and JS callbacks in order. */
  private _teardown(): void {
    const module = this._module;

    if (module && this._sherpaBackendRegistered) {
      try {
        const rc = module._rac_backend_sherpa_unregister?.() ?? 0;
        if (rc !== 0) {
          logger.warning(`rac_backend_sherpa_unregister returned ${rc}`);
        }
      } catch (err) {
        logger.warning(
          `rac_backend_sherpa_unregister threw: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    if (module && this._onnxBackendRegistered) {
      try {
        const rc = module._rac_backend_onnx_unregister?.() ?? 0;
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
    if (module && this._bridgeOwnedInit) {
      try {
        module._rac_shutdown?.();
      } catch (err) {
        logger.warning(
          `rac_shutdown threw: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    // Keep the adapter alive through backend unregister + rac_shutdown because
    // both paths may log or perform platform I/O through its callbacks.
    if (this._platformAdapter) {
      try {
        this._platformAdapter.cleanup();
      } catch (err) {
        logger.warning(
          `PlatformAdapter cleanup threw: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      this._platformAdapter = null;
    }

    if (module) unregisterWasmModule(module);

    this._module = null;
    this._onnxBackendRegistered = false;
    this._sherpaBackendRegistered = false;
    this._bridgeOwnedInit = false;
    this._loaded = false;
    this._loading = null;
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

    try {
      // Use the same fully-populated browser adapter as LlamaCppBridge. The
      // adapter must be retained until teardown because RACommons stores its
      // struct pointer rather than copying the callbacks.
      this._platformAdapter = new PlatformAdapter(
        this._module as unknown as PlatformAdapterModule,
      );
      this._platformAdapter.register();

      // Initialize the commons code linked into this artifact, then register
      // for the speech capabilities ONLY (STT/TTS/VAD/voice-agent). The
      // commons module — installed by `CommonsModule.shared.ensureLoaded()`
      // during `RunAnywhere.initialize()` — owns the 'commons' capability;
      // the per-capability registry keeps siblings (LLM via llamacpp) safe
      // from being overwritten.
      await this._initCommons(this._module, this._platformAdapter.getAdapterPtr());
      this._bridgeOwnedInit = true;
      completeNativePhase1ForModule(this._module);

      // Claim speech + embedding + semantic segmentation + RAG. The dedicated racommons-onnx-sherpa
      // artifact exports `_rac_embeddings_embed_batch_lifecycle_proto` (in the BASE
      // export list — see `RAC_EXPORTED_FUNCTIONS_BASE` in
      // sdk/runanywhere-web/wasm/CMakeLists.txt) and the 6 `_rac_rag_*_proto`
      // symbols (gated by `RAC_BACKEND_RAG=ON`, which is the default — see
      // the `_onnx_exports` block around CMakeLists.txt line 1300). Claiming
      // both capabilities here makes `RAGProtoAdapter.tryDefault()` and the
      // embeddings adapter route to the only Web engine with embedding ops.
      // LlamaCPP intentionally does not claim either slot, so an acceleration
      // reload cannot redirect lifecycle embeddings into the wrong WASM heap.
      const capabilities: WasmCapability[] = [
        'stt',
        'tts',
        'vad',
        'voice-agent',
        'embedding',
        'segmentation',
        'rag',
      ];
      registerWasmModule(capabilities, this._module, ['onnx', 'sherpa']);

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
    } catch (err) {
      // Covers adapter registration, rac_init, capability registration, either
      // backend registration, and deferred-service completion. Teardown keeps
      // the adapter alive until native shutdown has finished.
      this._teardown();
      throw err;
    }
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
        const safeCandidate = redactResourceURL(candidate);
        const rawError = err instanceof Error ? err.message : String(err);
        lastError = rawError.replaceAll(candidate, safeCandidate);
        logger.debug(
          `RACommons ONNX glue not resolvable at ${safeCandidate}: ${lastError}`,
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
    logger.info(
      `Loading RACommons ONNX/Sherpa WASM glue from ${redactResourceURL(moduleUrl)}`,
    );

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

  /** Call `rac_init()` with the shared browser platform adapter. */
  private async _initCommons(module: CommonsModule, adapterPtr: number): Promise<void> {
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
    if (adapterPtr === 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'Shared browser PlatformAdapter returned a null adapter pointer.',
      );
    }

    if (typeof module._rac_wasm_offsetof_config_platform_adapter !== 'function') {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'racommons-onnx-sherpa WASM module is missing _rac_wasm_offsetof_config_platform_adapter export; rebuild racommons-onnx-sherpa.wasm.',
      );
    }
    const adapterOffset = module._rac_wasm_offsetof_config_platform_adapter();
    const configPtr = module._malloc(sizeofConfig);
    if (configPtr === 0) {
      throw SDKException.backendNotAvailable(
        'ONNX.register',
        'Failed to allocate rac_config_t for racommons-onnx-sherpa.',
      );
    }
    try {
      for (let i = 0; i < sizeofConfig; i++) {
        module.setValue(configPtr + i, 0, 'i8');
      }
      module.setValue(configPtr + adapterOffset, adapterPtr, '*');

      // Match LlamaCppBridge's INFO default when the current WASM exports the
      // runtime config offset. Older compatible artifacts can omit it.
      if (typeof module._rac_wasm_offsetof_config_log_level === 'function') {
        const logLevelOffset = module._rac_wasm_offsetof_config_log_level();
        module.setValue(configPtr + logLevelOffset, 2, 'i32');
      }

      const rc = await this._callMaybeAsync(module, 'rac_init', ['number'], [configPtr]);
      if (!this._isRegistrationSuccess(rc)) {
        throw SDKException.backendNotAvailable(
          'ONNX.register',
          `rac_init returned ${rc}.`,
        );
      }
    } finally {
      module._free(configPtr);
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
