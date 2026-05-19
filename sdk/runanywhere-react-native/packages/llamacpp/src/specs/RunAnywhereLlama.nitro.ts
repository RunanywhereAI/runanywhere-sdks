/**
 * RunAnywhereLlama Nitrogen Spec
 *
 * LlamaCPP backend registration hooks.
 *
 * Public lifecycle, generation, structured-output, LoRA, and VLM APIs live in
 * @runanywhere/core and route through commons proto/lifecycle bridges. This
 * backend package only registers native providers.
 *
 * NOTE: After editing this file, run `npx nitro-codegen` (or
 * `yarn llamacpp:nitrogen`) to regenerate the bridge code under
 * `nitrogen/generated/`. Those files are auto-generated and must not be
 * hand-edited; until regeneration they may still reference the removed
 * VLM register/unregister hooks.
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * LlamaCPP native registration interface.
 *
 * The single `registerBackend()` / `unregisterBackend()` pair covers both LLM
 * and VLM modalities — the underlying C++ symbol `rac_backend_llamacpp_register()`
 * was unified and the separate `rac_backend_llamacpp_vlm_register()` symbol no
 * longer exists.
 */
export interface RunAnywhereLlama
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  /**
   * Register the LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() from runanywhere-binaries; this
   * single call covers both LLM and VLM modalities.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerBackend(): Promise<boolean>;

  /**
   * Unregister the LlamaCPP backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterBackend(): Promise<boolean>;

  /**
   * Check if the LlamaCPP backend is registered
   * @returns true if backend is registered
   */
  isBackendRegistered(): Promise<boolean>;
}
