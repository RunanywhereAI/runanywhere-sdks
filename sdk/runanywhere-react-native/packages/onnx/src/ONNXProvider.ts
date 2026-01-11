/**
 * @runanywhere/onnx - ONNX Provider
 *
 * ONNX Runtime module registration for React Native SDK.
 * Thin wrapper that triggers C++ backend registration for STT/TTS/VAD.
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNX.swift
 */

import { requireNativeONNXModule, isNativeONNXModuleAvailable } from './native/NativeRunAnywhereONNX';

// Simple logger for this package
const DEBUG = typeof __DEV__ !== 'undefined' ? __DEV__ : false;
const log = {
  info: (msg: string) => DEBUG && console.log(`[ONNXProvider] ${msg}`),
  debug: (msg: string) => DEBUG && console.log(`[ONNXProvider] ${msg}`),
  warning: (msg: string) => console.warn(`[ONNXProvider] ${msg}`),
};

/**
 * ONNX Module
 *
 * Provides STT (Speech-to-Text), TTS (Text-to-Speech), and VAD capabilities
 * using ONNX Runtime / Sherpa-ONNX.
 * The actual services are provided by the C++ backend.
 *
 * ## Registration
 *
 * ```typescript
 * import { ONNXProvider } from '@runanywhere/onnx';
 *
 * // Register the backend
 * await ONNXProvider.register();
 * ```
 */
export class ONNXProvider {
  static readonly moduleId = 'onnx';
  static readonly moduleName = 'ONNX Runtime';
  static readonly version = '1.23.2';

  private static isRegistered = false;

  /**
   * Register ONNX backend with the C++ service registry.
   * Calls rac_backend_onnx_register() to register all ONNX
   * service providers (STT, TTS, VAD) with the C++ commons layer.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns Promise<boolean> true if registered successfully
   */
  static async register(): Promise<boolean> {
    if (this.isRegistered) {
      log.debug('ONNX already registered, returning');
      return true;
    }

    if (!isNativeONNXModuleAvailable()) {
      log.warning('ONNX native module not available');
      return false;
    }

    log.info('Registering ONNX backend with C++ registry...');

    try {
      const native = requireNativeONNXModule();
      // Call the native registration method from the ONNX module
      const success = await native.registerBackend();
      if (success) {
        this.isRegistered = true;
        log.info('✅ ONNX backend registered successfully (STT + TTS + VAD)');
      }
      return success;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      log.warning(`ONNX registration failed: ${msg}`);
      return false;
    }
  }

  /**
   * Unregister the ONNX backend from C++ registry.
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!this.isRegistered) {
      return true;
    }

    if (!isNativeONNXModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeONNXModule();
      const success = await native.unregisterBackend();
      if (success) {
        this.isRegistered = false;
        log.info('ONNX backend unregistered');
      }
      return success;
    } catch (error) {
      return false;
    }
  }

  /**
   * Check if ONNX can handle STT models
   */
  static canHandleSTT(modelId: string | null | undefined): boolean {
    if (!modelId) return false;
    const lowercased = modelId.toLowerCase();
    return (
      lowercased.includes('whisper') ||
      lowercased.includes('zipformer') ||
      lowercased.includes('paraformer')
    );
  }

  /**
   * Check if ONNX can handle TTS models
   */
  static canHandleTTS(modelId: string | null | undefined): boolean {
    if (!modelId) return false;
    const lowercased = modelId.toLowerCase();
    return lowercased.includes('piper') || lowercased.includes('vits');
  }

  /**
   * Check if ONNX can handle VAD (always true for Silero VAD)
   */
  static canHandleVAD(_modelId: string | null | undefined): boolean {
    return true; // ONNX Silero VAD is the default
  }

  /**
   * Check if ONNX can handle a given model (STT/TTS/VAD)
   */
  static canHandle(modelId: string | null | undefined): boolean {
    if (!modelId) {
      return false;
    }
    const lowercased = modelId.toLowerCase();

    // STT: Whisper models (ONNX format)
    if (lowercased.includes('whisper') && !lowercased.includes('whisperkit')) {
      return true;
    }

    // STT/TTS/VAD: Sherpa-ONNX models
    if (lowercased.includes('sherpa-onnx') || lowercased.includes('sherpa_onnx')) {
      return true;
    }

    // TTS: Piper models
    if (lowercased.includes('piper')) {
      return true;
    }

    // VAD: Silero VAD
    if (lowercased.includes('silero') && lowercased.includes('vad')) {
      return true;
    }

    return false;
  }
}

/**
 * Auto-register when module is imported
 */
export function autoRegister(): void {
  ONNXProvider.register().catch(() => {
    // Silently handle registration failure during auto-registration
  });
}
