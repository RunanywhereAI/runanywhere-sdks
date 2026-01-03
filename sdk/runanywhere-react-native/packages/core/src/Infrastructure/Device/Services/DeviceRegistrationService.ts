/**
 * DeviceRegistrationService.ts
 *
 * Thin wrapper over native device registration.
 * All logic is in native commons.
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('DeviceRegistration');

/**
 * Device Registration Service - Thin wrapper over native
 */
export class DeviceRegistrationService {
  private static _instance: DeviceRegistrationService | null = null;

  static get shared(): DeviceRegistrationService {
    if (!DeviceRegistrationService._instance) {
      DeviceRegistrationService._instance = new DeviceRegistrationService();
    }
    return DeviceRegistrationService._instance;
  }

  /**
   * Get device ID (via native)
   */
  async getDeviceId(): Promise<string> {
    if (!isNativeModuleAvailable()) {
      return 'unknown';
    }

    const native = requireNativeModule();
    const id = await native.getDeviceId();
    return id ?? 'unknown';
  }

  /**
   * Register device if needed (native)
   */
  async registerIfNeeded(): Promise<void> {
    if (!isNativeModuleAvailable()) {
      logger.debug('Native module not available');
      return;
    }

    try {
      const native = requireNativeModule();
      await native.registerDevice();
      logger.info('Device registered via native');
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`Device registration failed: ${msg}`);
    }
  }

  /**
   * Reset singleton (for testing)
   */
  static reset(): void {
    DeviceRegistrationService._instance = null;
  }
}
