/**
 * ONNX - Module facade for @runanywhere/web-onnx
 *
 * Provides a high-level API matching the React Native SDK's module pattern.
 *
 * Usage:
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await ONNX.register();
 */

import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';
import { ONNXProvider } from './ONNXProvider';

/** Options for `ONNX.register()`. */
export interface ONNXRegisterOptions {
  /** Override URL to the sherpa-onnx-glue.js glue file. */
  wasmUrl?: string;
  /**
   * Override base URL for sherpa-onnx helper files (sherpa-onnx-asr.js, -tts.js, -vad.js).
   * Must end with a trailing `/`.
   */
  helperBaseUrl?: string;
}

const MODULE_ID = 'onnx';

export const ONNX = {
  get moduleId(): string {
    return MODULE_ID;
  },

  get isRegistered(): boolean {
    return ONNXProvider.isRegistered;
  },

  /**
   * Register the sherpa-onnx backend.
   * Call after `RunAnywhere.initialize()`.
   *
   * @param options - Optional WASM URL overrides.
   *                  Use `wasmUrl` / `helperBaseUrl` when the default
   *                  `import.meta.url`-based resolution doesn't work (e.g. bundled apps).
   */
  async register(options?: ONNXRegisterOptions): Promise<void> {
    const bridge = SherpaONNXBridge.shared;
    if (options?.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    if (options?.helperBaseUrl) bridge.helperBaseUrl = options.helperBaseUrl;
    return ONNXProvider.register();
  },

  unregister(): void {
    ONNXProvider.unregister();
  },
};

export function autoRegister(): void {
  ONNXProvider.register().catch(() => {
    // Silently handle registration failure during auto-registration
  });
}
