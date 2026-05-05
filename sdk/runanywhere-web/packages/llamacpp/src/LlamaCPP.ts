/**
 * LlamaCPP — public facade for the `@runanywhere/web-llamacpp` backend.
 *
 * V2 canonical: this package is a SHELL. It only loads the WASM module,
 * registers the platform adapter, calls `rac_init`, registers the
 * llama.cpp + llama.cpp-VLM backends, then installs the module on every
 * core proto-byte adapter via `setRunanywhereModule(...)`.
 *
 * After `LlamaCPP.register()` resolves, `RunAnywhere.generate(...)`,
 * `RunAnywhere.generateStream(...)`, tool calling, structured output,
 * embeddings, and diffusion all flow through `@runanywhere/web` core's
 * proto-byte adapters (`LLMProtoAdapter`, `EmbeddingsProtoAdapter`,
 * `DiffusionProtoAdapter`, `StructuredOutputProtoAdapter`,
 * `VLMProtoAdapter`, etc.) without any further per-package wiring.
 *
 * Usage:
 *
 *     import { RunAnywhere } from '@runanywhere/web';
 *     import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *
 *     await RunAnywhere.initialize({ environment: 'development' });
 *     await LlamaCPP.register({ acceleration: 'auto' });
 *
 *     const stream = await RunAnywhere.generateStream('Hello!', {
 *       maxTokens: 256,
 *     });
 *     for await (const token of stream.stream) {
 *       process.stdout.write(token);
 *     }
 *     const result = await stream.result;
 */

import {
  setAccelerationSwitcher,
  setActiveAccelerationMode,
  SDKLogger,
} from '@runanywhere/web';
import { LlamaCppBridge } from './Foundation/LlamaCppBridge';

const logger = new SDKLogger('LlamaCPP');

const MODULE_ID = 'llamacpp';

let _isRegistered = false;
let _registeringPromise: Promise<void> | null = null;

export interface LlamaCPPRegisterOptions {
  /** Hardware acceleration strategy. Defaults to `'auto'` (WebGPU if available, otherwise CPU). */
  acceleration?: 'auto' | 'webgpu' | 'cpu';
  /** Override the URL to the racommons-llamacpp.js glue file (CPU). */
  wasmUrl?: string;
  /** Override the URL to the racommons-llamacpp-webgpu.js glue file. */
  webgpuWasmUrl?: string;
}

export const LlamaCPP = {
  /** Unique module identifier. */
  get moduleId(): string {
    return MODULE_ID;
  },

  /** Whether the backend is registered. */
  get isRegistered(): boolean {
    return _isRegistered;
  },

  /** Active hardware acceleration mode (cpu | webgpu). Available after `register()`. */
  get accelerationMode(): 'cpu' | 'webgpu' {
    return LlamaCppBridge.shared.accelerationMode;
  },

  /**
   * Register the llama.cpp backend with the RunAnywhere SDK.
   *
   * Must be called after `RunAnywhere.initialize(...)`.
   *
   * 1. Loads the appropriate WASM variant (CPU or WebGPU).
   * 2. Verifies via `_rac_wasm_ping()` smoke check.
   * 3. Registers the 11-callback `rac_platform_adapter_t` browser vtable.
   * 4. Calls `rac_init()` (async, may suspend through ASYNCIFY).
   * 5. Calls `rac_backend_llamacpp_register()` and (when present)
   *    `rac_backend_llamacpp_vlm_register()`.
   * 6. Installs the module on `setRunanywhereModule()` so every core
   *    proto-byte adapter (LLM/VLM/embeddings/diffusion/structured/tool/
   *    model-registry/lifecycle/download/hardware/storage/SDKEvent/HTTP)
   *    can find it.
   * 7. Wires `RunAnywhere.runtime.setAcceleration(mode)` to the bridge's
   *    acceleration switcher.
   *
   * Idempotent — concurrent callers share the same in-flight promise.
   */
  async register(options: LlamaCPPRegisterOptions = {}): Promise<void> {
    if (_isRegistered) {
      logger.debug('LlamaCpp backend already registered, skipping');
      return;
    }
    if (_registeringPromise) {
      logger.debug('LlamaCpp registration in progress, awaiting...');
      return _registeringPromise;
    }

    _registeringPromise = (async () => {
      try {
        const bridge = LlamaCppBridge.shared;
        if (options.wasmUrl) bridge.wasmUrl = options.wasmUrl;
        if (options.webgpuWasmUrl) bridge.webgpuWasmUrl = options.webgpuWasmUrl;

        // Wire `RunAnywhere.runtime.setAcceleration(mode)` into the bridge.
        // Cleared on `unregister()`. Mirrors the previous public surface so
        // the core's `RuntimeConfig.setAcceleration` actually works.
        setAccelerationSwitcher(async (mode) => {
          await bridge.switchToAcceleration(mode);
          setActiveAccelerationMode(bridge.accelerationMode);
        });

        await bridge.ensureLoaded(options.acceleration ?? 'auto');

        // Publish the active mode so `RunAnywhere.runtime.active` reflects
        // what the bridge actually picked (auto → webgpu/cpu resolution).
        setActiveAccelerationMode(bridge.accelerationMode);

        _isRegistered = true;
        logger.info(`LlamaCpp backend registered (${bridge.accelerationMode})`);
      } finally {
        _registeringPromise = null;
      }
    })();

    return _registeringPromise;
  },

  /**
   * Unregister the backend and release its WASM module.
   */
  unregister(): void {
    if (!_isRegistered) return;
    setAccelerationSwitcher(null);
    setActiveAccelerationMode(null);
    LlamaCppBridge.shared.shutdown();
    _isRegistered = false;
    logger.info('LlamaCpp backend unregistered');
  },
};

/**
 * Auto-register the llama.cpp backend.
 *
 * Convenience helper for app boot scripts that don't care about catching
 * the registration error (e.g. when Vite tries to load the WASM but the
 * file isn't present yet during a dev cold start).
 */
export function autoRegister(): void {
  LlamaCPP.register().catch((err) => {
    logger.warning(
      `LlamaCpp auto-registration failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  });
}
