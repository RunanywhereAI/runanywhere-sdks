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

import { LlamaCppProvider } from './LlamaCppProvider';

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

  /**
   * Register the llama.cpp backend.
   * Call after `RunAnywhere.initialize()`.
   */
  async register(): Promise<void> {
    return LlamaCppProvider.register();
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
 * Import for fire-and-forget registration:
 *   import '@runanywhere/web-llamacpp/autoRegister';
 */
export function autoRegister(): void {
  LlamaCppProvider.register().catch(() => {
    // Silently handle registration failure during auto-registration
  });
}
