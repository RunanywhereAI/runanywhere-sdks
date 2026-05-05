/**
 * ONNX - Public facade for `@runanywhere/web-onnx`.
 *
 * V2-canonical: STT/TTS/VAD inference is owned by the RACommons C ABI
 * through the proto-byte adapters in `@runanywhere/web` (STTProtoAdapter,
 * TTSProtoAdapter, VADProtoAdapter). This package's only job is to:
 *
 *   1. Acquire the RACommons WASM module (loaded by a sibling backend
 *      such as `@runanywhere/web-llamacpp`, or loaded directly here when
 *      ONNX is the first backend to register).
 *   2. Call `rac_backend_onnx_register()` to install the sherpa-onnx
 *      vtable in the C++ plugin registry.
 *
 * After `ONNX.register()` resolves, the public verbs in
 * `@runanywhere/web` (proto-byte STT/TTS/VAD facades, voice agent) route
 * through the registered backend automatically — no further JS plumbing.
 *
 * Usage:
 *   ```ts
 *   import { RunAnywhere } from '@runanywhere/web';
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await RunAnywhere.initialize();
 *   await ONNX.register();
 *   ```
 */

import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';

const MODULE_ID = 'onnx';

export interface ONNXRegisterOptions {
  /** Override URL to the RACommons `racommons-llamacpp.js` glue file. */
  wasmUrl?: string;
}

export const ONNX = {
  get moduleId(): string {
    return MODULE_ID;
  },

  get isRegistered(): boolean {
    return SherpaONNXBridge.shared.isBackendRegistered;
  },

  /**
   * Register the ONNX (sherpa-onnx) backend.
   *
   * Loads or attaches to the RACommons WASM module and calls
   * `rac_backend_onnx_register()`. The proto-byte STT/TTS/VAD adapters in
   * `@runanywhere/web` core then route inference through the registered
   * backend.
   */
  async register(options?: ONNXRegisterOptions): Promise<void> {
    const bridge = SherpaONNXBridge.shared;
    if (options?.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    await bridge.ensureLoaded(options);
  },

  /** Unregister the backend. Idempotent. */
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
