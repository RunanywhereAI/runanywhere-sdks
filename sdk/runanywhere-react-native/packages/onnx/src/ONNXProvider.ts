/**
 * @runanywhere/onnx - ONNX Provider
 *
 * Internal ONNX Runtime module registration for React Native SDK.
 * Thin wrapper that triggers C++ backend registration for STT/TTS/VAD.
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNX.swift
 */

import { requireNativeONNXModule, isNativeONNXModuleAvailable } from './native/NativeRunAnywhereONNX';
import { SDKLogger } from '@runanywhere/core/internal';

// Use SDKLogger with ONNX.Provider category
const logger = new SDKLogger('ONNX.Provider');

/**
 * Internal ONNX provider implementation.
 *
 * Registers ONNX STT/TTS/VAD providers. Core owns public model lifecycle and
 * inference surfaces.
 *
 * @internal
 */
export class ONNXProvider {
  static readonly moduleId = 'onnx';
  static readonly moduleName = 'ONNX Runtime';
  static readonly version = '1.23.2';

  private static registered = false;

  /**
   * Register ONNX backend with the C++ service registry.
   * Calls rac_backend_onnx_register() to register all ONNX
   * service providers (STT, TTS, VAD) with the C++ commons layer.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns Promise<boolean> true if registered successfully
   */
  static async register(): Promise<boolean> {
    if (this.registered) {
      logger.debug('ONNX already registered, returning');
      return true;
    }

    if (!isNativeONNXModuleAvailable()) {
      logger.warning('ONNX native module not available');
      return false;
    }

    logger.info('Registering ONNX backend with C++ registry...');

    try {
      const native = requireNativeONNXModule();
      // Call the native registration method from the ONNX module
      const success = await native.registerBackend();
      if (success) {
        this.registered = true;
        logger.info('ONNX backend registered successfully (STT + TTS + VAD)');
      }
      return success;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`ONNX registration failed: ${msg}`);
      return false;
    }
  }

  /**
   * Unregister the ONNX backend from C++ registry.
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!this.registered) {
      return true;
    }

    if (!isNativeONNXModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeONNXModule();
      const success = await native.unregisterBackend();
      if (success) {
        this.registered = false;
        logger.info('ONNX backend unregistered');
      }
      return success;
    } catch (error) {
      return false;
    }
  }

  /**
   * Check native registration state. Falls back to JS state if the native
   * object cannot be created.
   */
  static async isRegistered(): Promise<boolean> {
    if (!isNativeONNXModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeONNXModule();
      const registered = await native.isBackendRegistered();
      this.registered = registered;
      return registered;
    } catch {
      return this.registered;
    }
  }
}
