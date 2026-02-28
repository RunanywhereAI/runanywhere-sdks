/**
 * LlamaCPP - Module facade for @runanywhere/web-llamacpp
 *
 * Provides a high-level API matching the React Native SDK's module pattern.
 *
 * Usage:
 *   import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *
 *   await LlamaCPP.register();
 *   LlamaCPP.addModel({ id: 'my-model', name: 'My Model', url: '...' });
 */

import { LlamaCppBridge } from './Foundation/LlamaCppBridge';
import { LlamaCppProvider } from './LlamaCppProvider';

/** Options for `LlamaCPP.register()`. */
export interface LlamaCPPRegisterOptions {
  /** Override URL to the racommons-llamacpp.js glue file (CPU variant). */
  wasmUrl?: string;
  /** Override URL to the racommons-llamacpp-webgpu.js glue file. */
  webgpuWasmUrl?: string;
  /** Hardware acceleration strategy (default: 'auto'). */
  acceleration?: 'auto' | 'webgpu' | 'cpu';
}

/** Module identifier. */
const MODULE_ID = 'llamacpp';

export const LlamaCPP = {
  /** Unique module identifier. */
  get moduleId(): string {
    return MODULE_ID;
  },

  /** Whether the backend is registered. */
  get isRegistered(): boolean {
    return LlamaCppProvider.isRegistered;
  },

  /** Current hardware acceleration mode ('cpu' | 'webgpu'). Available after register(). */
  get accelerationMode(): string {
    return LlamaCppBridge.shared?.accelerationMode ?? 'cpu';
  },

  /**
   * Register the llama.cpp backend.
   * Call after `RunAnywhere.initialize()`.
   *
   * @param options - Optional WASM URL overrides and acceleration preference.
   *                  Use `wasmUrl` / `webgpuWasmUrl` when the default
   *                  `import.meta.url`-based resolution doesn't work (e.g. bundled apps).
   */
  async register(options?: LlamaCPPRegisterOptions): Promise<void> {
    const bridge = LlamaCppBridge.shared;
    if (options?.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    if (options?.webgpuWasmUrl) bridge.webgpuWasmUrl = options.webgpuWasmUrl;
    return LlamaCppProvider.register(options?.acceleration);
  },

  /**
   * Unregister the backend and clean up.
   */
  unregister(): void {
    LlamaCppProvider.unregister();
  },
};

/**
 * Auto-register the llama.cpp backend.
 * Usage:
 *   import { autoRegister } from '@runanywhere/web-llamacpp';
 *   autoRegister();
 */
export function autoRegister(): void {
  LlamaCppProvider.register().catch(() => {
    // Silently handle registration failure during auto-registration
  });
}
