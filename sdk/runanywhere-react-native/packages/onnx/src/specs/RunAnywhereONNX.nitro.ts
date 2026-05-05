/**
 * RunAnywhereONNX Nitrogen Spec
 *
 * ONNX backend registration hooks.
 *
 * Public STT, TTS, VAD, and voice-agent APIs live in @runanywhere/core and
 * route through backend-agnostic commons proto/lifecycle bridges. This backend
 * package only registers native providers.
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * ONNX native registration interface.
 */
export interface RunAnywhereONNX
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  /**
   * Register the ONNX backend with the C++ service registry.
   * Registers STT, TTS, and VAD providers.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerBackend(): Promise<boolean>;

  /**
   * Unregister the ONNX backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterBackend(): Promise<boolean>;

  /**
   * Check if the ONNX backend is registered
   * @returns true if backend is registered
   */
  isBackendRegistered(): Promise<boolean>;
}
