/**
 * DeviceIdentity.ts
 *
 * Simple utility for device identity management (UUID persistence)
 *
 * Provides persistent UUID that survives app reinstalls by storing in:
 * - iOS: Keychain
 * - Android: Keystore/EncryptedSharedPreferences
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Device/Services/DeviceIdentity.swift
 */

import { requireNativeModule } from '../../native';
import { SDKLogger } from '../Logging/Logger/SDKLogger';

const logger = new SDKLogger('DeviceIdentity');

/**
 * Cached UUID (matches Swift pattern - avoid repeated native calls)
 */
let cachedUUID: string | null = null;

/**
 * DeviceIdentity - Persistent device UUID management
 *
 * Matches Swift's DeviceIdentity enum pattern:
 * - Uses keychain/keystore for persistence (survives reinstalls)
 * - Caches result after first access
 * - Falls back to UUID generation if needed
 */
export const DeviceIdentity = {
  /**
   * Get a persistent device UUID that survives app reinstalls
   *
   * Strategy (matches Swift):
   * 1. Return cached value if available (fast path)
   * 2. Try to get from keychain (native call)
   * 3. If not found, native will generate and store
   *
   * @returns Promise<string> Persistent device UUID
   */
  async getPersistentUUID(): Promise<string> {
    // Fast path: return cached value
    if (cachedUUID) {
      return cachedUUID;
    }

    try {
      const native = requireNativeModule();
      const uuid = await native.getPersistentDeviceUUID();

      if (uuid && uuid.length > 0) {
        cachedUUID = uuid;
        logger.debug('Got persistent device UUID from native');
        return uuid;
      }

      throw new Error('Native returned empty UUID');
    } catch (error) {
      logger.error('Failed to get persistent device UUID', { error });
      throw error;
    }
  },

  /**
   * Get the cached UUID if available (synchronous)
   *
   * @returns Cached UUID or null if not yet loaded
   */
  getCachedUUID(): string | null {
    return cachedUUID;
  },

  /**
   * Clear the cached UUID (for testing)
   */
  clearCache(): void {
    cachedUUID = null;
  },

  /**
   * Validate if a device UUID is properly formatted
   *
   * @param uuid UUID string to validate
   * @returns true if valid UUID format
   */
  validateUUID(uuid: string): boolean {
    // UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx (36 chars)
    return uuid.length === 36 && uuid.includes('-');
  },
};

