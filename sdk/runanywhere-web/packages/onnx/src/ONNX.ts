/**
 * ONNX - Public facade for `@runanywhere/web-onnx`.
 *
 * Loads `racommons-onnx-sherpa.{js,wasm}` (the dedicated ONNX/Sherpa
 * Emscripten module) and registers the ONNX runtime + Sherpa speech
 * vtables with the C++ plugin registry. After `ONNX.register()` resolves,
 * STT/TTS/VAD operations flow entirely through the proto-byte adapters
 * in `@runanywhere/web` core into that WASM module.
 *
 * Usage:
 *   ```ts
 *   import { RunAnywhere } from '@runanywhere/web';
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await RunAnywhere.initialize();
 *   await ONNX.register();
 *   const vad = await RunAnywhere.detectVoiceActivity(silence);
 *   ```
 */

import { SDKLogger } from '@runanywhere/web/internal';
import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';

const MODULE_ID = 'onnx';
const logger = new SDKLogger('ONNX');

export interface ONNXRegisterOptions {
  /** Override URL to the `racommons-onnx-sherpa.js` glue file. */
  wasmUrl?: string;
}

export const ONNX = {
  get moduleId(): string {
    return MODULE_ID;
  },

  /** `true` when the ONNX/Sherpa plugin registration succeeded. */
  get isRegistered(): boolean {
    return SherpaONNXBridge.shared.isBackendRegistered;
  },

  /**
   * Register the ONNX Runtime + Sherpa speech backends.
   *
   * Loads the dedicated `racommons-onnx-sherpa.{js,wasm}` artifact, calls
   * `rac_init()`, registers the ONNX runtime and Sherpa speech vtables,
   * then installs the module on every core proto-byte adapter so
   * STT/TTS/VAD calls in `@runanywhere/web` core route through it.
   */
  async register(options?: ONNXRegisterOptions): Promise<void> {
    const bridge = SherpaONNXBridge.shared;
    if (options?.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    await bridge.ensureLoaded(options);
    logger.info('ONNX/Sherpa backends registered (STT/TTS/VAD vtables installed)');
  },

  /** Unregister the proto-byte plugins and release the WASM module. */
  unregister(): void {
    SherpaONNXBridge.shared.unregister();
  },
};

/** Best-effort registration helper for apps that import the package eagerly. */
export function autoRegister(options?: ONNXRegisterOptions): Promise<void> {
  return ONNX.register(options).catch(() => {
    // Suppress — callers should use `ONNX.register()` directly to inspect failures.
  });
}
