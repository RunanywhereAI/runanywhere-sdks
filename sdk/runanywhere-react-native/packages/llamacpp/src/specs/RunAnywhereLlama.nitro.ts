/**
 * RunAnywhereLlama Nitrogen Spec
 *
 * LlamaCPP backend registration hooks.
 *
 * Public lifecycle, generation, structured-output, LoRA, and VLM APIs live in
 * @runanywhere/core and route through commons proto/lifecycle bridges. This
 * backend package only registers native providers.
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * LlamaCPP native registration interface.
 */
export interface RunAnywhereLlama
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  /**
   * Register the LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() from runanywhere-binaries.
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

  // ============================================================================
  // VLM Backend Registration
  // Core owns VLM lifecycle/process/cancel through proto-byte APIs.
  // Backend packages only register/unregister native providers.
  // ============================================================================

  /**
   * Register the LlamaCPP VLM backend with C++ registry.
   * Calls rac_backend_llamacpp_vlm_register() - separate from LLM registration.
   */
  registerVLMBackend(): Promise<boolean>;

  /**
   * Unregister the LlamaCPP VLM backend from C++ registry.
   */
  unregisterVLMBackend(): Promise<boolean>;

  /**
   * Check if the LlamaCPP VLM backend is registered.
   */
  isVLMBackendRegistered(): Promise<boolean>;
}
