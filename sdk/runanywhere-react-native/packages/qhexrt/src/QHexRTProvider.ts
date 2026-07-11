/**
 * @runanywhere/qhexrt - QHexRT Provider
 *
 * Internal QHexRT (Qualcomm Hexagon NPU) module registration for the React
 * Native SDK. Thin wrapper that triggers C++ backend registration behind the
 * QHexRT facade and exposes the pre-flight NPU probe.
 */

import {
  getNativeQHexRTModule,
  isNativeQHexRTModuleAvailable,
} from './native/NativeRunAnywhereQHexRT';
import { SDKLogger } from '@runanywhere/core/internal';

// SDKLogger instance for this module
const log = new SDKLogger('NPU.QHexRTProvider');

/**
 * Internal QHexRT provider implementation.
 *
 * Registers the QHexRT backend provider; the single C++ registration call
 * covers LLM, VLM, STT, and TTS modalities. Core owns public model lifecycle
 * and inference surfaces.
 *
 * @internal
 */
export class QHexRTProvider {
  static readonly moduleId = 'qhexrt';
  static readonly moduleName = 'QHexRT';
  // Keep in sync with package.json "version" (same convention as the other
  // backend providers — there is no runtime package.json read in RN bundles).
  static readonly version = '0.19.15';

  private static registered = false;

  /**
   * Register QHexRT backend with the C++ service registry.
   * Calls rac_backend_qhexrt_register() to register the QHexRT service
   * providers with the C++ commons layer; the single call covers all
   * modalities. Safe to call multiple times - subsequent calls are no-ops.
   * @returns Promise<boolean> true if registered successfully
   */
  static async register(): Promise<boolean> {
    if (this.registered) {
      log.debug('QHexRT already registered, returning');
      return true;
    }

    if (!isNativeQHexRTModuleAvailable()) {
      log.warning('QHexRT native module not available');
      return false;
    }

    log.debug('Registering QHexRT backend with C++ registry');

    try {
      const native = getNativeQHexRTModule();
      const success = await native.registerBackend();
      if (success) {
        this.registered = true;
        log.info('QHexRT backend registered successfully (covers LLM, VLM, STT, TTS)');
      }
      return success;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      log.warning(`QHexRT registration failed: ${msg}`);
      return false;
    }
  }

  /**
   * Unregister the QHexRT backend from the C++ registry.
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!this.registered) {
      return true;
    }

    if (!isNativeQHexRTModuleAvailable()) {
      return false;
    }

    const native = getNativeQHexRTModule();

    try {
      const success = await native.unregisterBackend();
      if (success) {
        this.registered = false;
        log.debug('QHexRT backend unregistered');
      }
      return success;
    } catch (error) {
      log.error(`QHexRT unregistration failed: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  /**
   * Check native registration state. Falls back to JS state if the native
   * object cannot be created.
   */
  static async isRegistered(): Promise<boolean> {
    if (!isNativeQHexRTModuleAvailable()) {
      return false;
    }

    try {
      const native = getNativeQHexRTModule();
      const registered = await native.isBackendRegistered();
      this.registered = registered;
      return registered;
    } catch {
      return this.registered;
    }
  }

  /**
   * Probe the device's Hexagon NPU capability (pre-flight, no QNN load).
   * @returns the raw serialized `runanywhere.v1.NpuCapability` proto bytes
   *          from the native probe (empty when the probe symbol is missing),
   *          or null when the native module is unavailable / the probe throws.
   */
  static async probeNpuRaw(): Promise<ArrayBuffer | null> {
    if (!isNativeQHexRTModuleAvailable()) {
      log.warning('QHexRT native module not available; cannot probe NPU');
      return null;
    }
    try {
      const native = getNativeQHexRTModule();
      return await native.probeNpuProto();
    } catch (error) {
      log.warning(`QHexRT NPU probe failed: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }
}
