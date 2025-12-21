/**
 * DeviceIdentityService.ts
 *
 * Device identity management - persistent device UUID storage
 *
 * This service manages a persistent device UUID that survives app reinstalls
 * by using secure storage (Keychain on iOS, Keystore on Android).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Device/Services/DeviceIdentity.swift
 */

import { SecureStorageService, SecureStorageKeys } from '../Security';
import { SDKLogger } from '../Logging/Logger/SDKLogger';

/**
 * Cached device UUID (once loaded, remains in memory)
 */
let cachedDeviceUUID: string | null = null;

/**
 * Device identity management
 *
 * Provides a persistent device UUID that survives app reinstalls.
 * Strategy (matching iOS):
 * 1. Try to retrieve from secure storage (Keychain/Keystore)
 * 2. If not found, generate a new UUID and store it
 */
export class DeviceIdentityService {
  private static readonly logger = new SDKLogger('DeviceIdentityService');

  /**
   * Get the persistent device UUID
   *
   * This UUID is stored in secure storage and survives app reinstalls.
   * If no UUID exists, a new one is generated and stored.
   *
   * @returns Promise resolving to the persistent device UUID
   */
  static async getPersistentDeviceUUID(): Promise<string> {
    // Return cached value if available
    if (cachedDeviceUUID) {
      return cachedDeviceUUID;
    }

    // Try to retrieve from secure storage
    const stored = await DeviceIdentityService.getStoredDeviceId();
    if (stored) {
      cachedDeviceUUID = stored;
      DeviceIdentityService.logger.debug('Retrieved device UUID from storage');
      return stored;
    }

    // Generate new UUID and store it
    const newUUID = DeviceIdentityService.generateUUID();
    await DeviceIdentityService.storeDeviceId(newUUID);
    cachedDeviceUUID = newUUID;
    DeviceIdentityService.logger.info('Generated and stored new device UUID');
    return newUUID;
  }

  /**
   * Get stored device ID from secure storage
   *
   * @returns Stored device ID or null if not found
   */
  static async getStoredDeviceId(): Promise<string | null> {
    try {
      return await SecureStorageService.retrieveDeviceUUID();
    } catch {
      DeviceIdentityService.logger.warning(
        'Failed to retrieve device ID from storage'
      );
      return null;
    }
  }

  /**
   * Store device ID in secure storage
   *
   * @param deviceId - Device ID to store
   */
  static async storeDeviceId(deviceId: string): Promise<void> {
    try {
      await SecureStorageService.storeDeviceUUID(deviceId);
      cachedDeviceUUID = deviceId;
    } catch (error) {
      DeviceIdentityService.logger.error('Failed to store device ID', { error });
      throw error;
    }
  }

  /**
   * Clear stored device ID
   *
   * WARNING: This will cause a new device ID to be generated on next access.
   */
  static async clearStoredDeviceId(): Promise<void> {
    try {
      await SecureStorageService.delete(SecureStorageKeys.deviceUUID);
      cachedDeviceUUID = null;
      DeviceIdentityService.logger.info('Device ID cleared from storage');
    } catch (error) {
      DeviceIdentityService.logger.error('Failed to clear device ID', { error });
      throw error;
    }
  }

  /**
   * Validate UUID format
   *
   * @param uuid - String to validate
   * @returns True if valid UUID format
   */
  static validateUUID(uuid: string): boolean {
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(uuid);
  }

  /**
   * Generate a UUID v4
   *
   * @returns New UUID string
   */
  private static generateUUID(): string {
    /* eslint-disable no-bitwise -- Bitwise ops required for UUID generation per RFC 4122 */
    // RFC 4122 compliant UUID v4
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
    /* eslint-enable no-bitwise */
  }

  /**
   * Get cached device UUID (sync access, may be null if not yet loaded)
   *
   * @returns Cached UUID or null
   */
  static getCachedDeviceUUID(): string | null {
    return cachedDeviceUUID;
  }

  /**
   * Reset the service (clears cache, for testing)
   */
  static reset(): void {
    cachedDeviceUUID = null;
  }
}
