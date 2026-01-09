/**
 * SecureStorageService.ts
 *
 * Secure storage abstraction for React Native
 *
 * This service provides secure key-value storage that uses:
 * - iOS: Keychain (via native module)
 * - Android: Keystore (via native module)
 *
 * In React Native, actual secure storage is delegated to the native layer.
 * This TS layer provides type-safe APIs and caching.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
 */

import { requireNativeModule } from '../../native';
import { SDKLogger } from '../Logging/Logger/SDKLogger';
import { SecureStorageError, isItemNotFoundError } from './SecureStorageError';
import { SecureStorageKeys, type SecureStorageKey } from './SecureStorageKeys';
import type { SDKInitParams } from '../Initialization';
import type { SDKEnvironment } from '../../types';

/**
 * Secure storage service
 *
 * Provides secure key-value storage matching iOS KeychainManager.
 * All actual storage is delegated to the native layer.
 */
class SecureStorageServiceImpl {
  private readonly logger = new SDKLogger('SecureStorageService');

  // In-memory cache for frequently accessed values
  private cache: Map<string, string> = new Map();

  // Flag to track if native storage is available
  private _isAvailable: boolean | null = null;

  /**
   * Check if secure storage is available
   *
   * Secure storage uses platform-native storage:
   * - iOS: Keychain (always available)
   * - Android: Keystore/EncryptedSharedPreferences (always available)
   */
  async isAvailable(): Promise<boolean> {
    if (this._isAvailable !== null) {
      return this._isAvailable;
    }

    try {
      const native = requireNativeModule();
      // Verify native module is available by checking for secure storage methods
      // The methods are implemented in C++ and use platform callbacks
      this._isAvailable =
        typeof native.secureStorageSet === 'function' &&
        typeof native.secureStorageGet === 'function';
      return this._isAvailable;
    } catch {
      this._isAvailable = false;
      return false;
    }
  }

  // ============================================================
  // Generic Storage Methods
  // ============================================================

  /**
   * Store a string value securely
   *
   * Uses native secure storage:
   * - iOS: Keychain
   * - Android: Keystore/EncryptedSharedPreferences
   *
   * @param value - String value to store
   * @param key - Storage key
   */
  async store(value: string, key: SecureStorageKey | string): Promise<void> {
    try {
      const native = requireNativeModule();

      // Use the new native method
      const success = await native.secureStorageSet(key, value);

      if (!success) {
        throw new Error(`Native secureStorageSet returned false for key: ${key}`);
      }

      // Update cache
      this.cache.set(key, value);
      this.logger.debug(`Stored value for key: ${key}`);
    } catch (error) {
      this.logger.error(`Failed to store value for key: ${key}`, { error });
      throw SecureStorageError.storageError(
        error instanceof Error ? error : undefined
      );
    }
  }

  /**
   * Retrieve a string value from secure storage
   *
   * Uses native secure storage:
   * - iOS: Keychain
   * - Android: Keystore/EncryptedSharedPreferences
   *
   * @param key - Storage key
   * @returns Stored value or null if not found
   */
  async retrieve(key: SecureStorageKey | string): Promise<string | null> {
    // Check cache first
    const cached = this.cache.get(key);
    if (cached !== undefined) {
      return cached;
    }

    try {
      const native = requireNativeModule();

      // Use the new native method
      const value = await native.secureStorageGet(key);

      if (value !== null && value !== undefined) {
        this.cache.set(key, value);
      }
      return value ?? null;
    } catch (error) {
      // Item not found is not an error - just return null
      if (isItemNotFoundError(error)) {
        return null;
      }

      this.logger.error(`Failed to retrieve value for key: ${key}`, { error });
      throw SecureStorageError.retrievalError(
        error instanceof Error ? error : undefined
      );
    }
  }

  /**
   * Delete a value from secure storage
   *
   * Uses native secure storage:
   * - iOS: Keychain
   * - Android: Keystore/EncryptedSharedPreferences
   *
   * @param key - Storage key
   */
  async delete(key: SecureStorageKey | string): Promise<void> {
    try {
      const native = requireNativeModule();

      // Use the new native method
      await native.secureStorageDelete(key);

      // Remove from cache
      this.cache.delete(key);
      this.logger.debug(`Deleted value for key: ${key}`);
    } catch (error) {
      // Ignore "not found" errors on delete
      if (!isItemNotFoundError(error)) {
        this.logger.error(`Failed to delete value for key: ${key}`, { error });
        throw SecureStorageError.deletionError(
          error instanceof Error ? error : undefined
        );
      }
    }
  }

  /**
   * Check if a key exists in secure storage
   *
   * Uses native secure storage:
   * - iOS: Keychain
   * - Android: Keystore/EncryptedSharedPreferences
   *
   * @param key - Storage key
   * @returns True if key exists
   */
  async exists(key: SecureStorageKey | string): Promise<boolean> {
    // Check cache first
    if (this.cache.has(key)) {
      return true;
    }

    try {
      const native = requireNativeModule();

      // Use the new native method
      return await native.secureStorageExists(key);
    } catch {
      return false;
    }
  }

  // ============================================================
  // SDK Parameters Storage (matching iOS KeychainManager)
  // ============================================================

  /**
   * Store SDK initialization parameters
   *
   * @param params - SDK init params
   */
  async storeSDKParams(params: SDKInitParams): Promise<void> {
    const promises: Promise<void>[] = [];

    if (params.apiKey) {
      promises.push(this.store(params.apiKey, SecureStorageKeys.apiKey));
    }
    if (params.baseURL) {
      promises.push(this.store(params.baseURL, SecureStorageKeys.baseURL));
    }
    promises.push(this.store(params.environment, SecureStorageKeys.environment));

    await Promise.all(promises);
    this.logger.info('SDK parameters stored securely');
  }

  /**
   * Retrieve stored SDK parameters
   *
   * @returns Stored SDK params or null if not found
   */
  async retrieveSDKParams(): Promise<SDKInitParams | null> {
    const [apiKey, baseURL, environment] = await Promise.all([
      this.retrieve(SecureStorageKeys.apiKey),
      this.retrieve(SecureStorageKeys.baseURL),
      this.retrieve(SecureStorageKeys.environment),
    ]);

    if (!apiKey || !baseURL || !environment) {
      this.logger.debug('No stored SDK parameters found');
      return null;
    }

    this.logger.debug('Retrieved SDK parameters from secure storage');
    return {
      apiKey,
      baseURL,
      environment: environment as SDKEnvironment,
    };
  }

  /**
   * Clear stored SDK parameters
   */
  async clearSDKParams(): Promise<void> {
    await Promise.all([
      this.delete(SecureStorageKeys.apiKey),
      this.delete(SecureStorageKeys.baseURL),
      this.delete(SecureStorageKeys.environment),
    ]);
    this.logger.info('SDK parameters cleared from secure storage');
  }

  // ============================================================
  // Device Identity Storage
  // ============================================================

  /**
   * Store device UUID
   *
   * @param uuid - Device UUID
   */
  async storeDeviceUUID(uuid: string): Promise<void> {
    await this.store(uuid, SecureStorageKeys.deviceUUID);
    this.logger.debug('Device UUID stored');
  }

  /**
   * Retrieve device UUID
   *
   * @returns Stored device UUID or null
   */
  async retrieveDeviceUUID(): Promise<string | null> {
    return this.retrieve(SecureStorageKeys.deviceUUID);
  }

  // ============================================================
  // Authentication Token Storage
  // ============================================================

  /**
   * Store authentication tokens
   *
   * @param accessToken - Access token
   * @param refreshToken - Refresh token
   * @param expiresAt - Token expiration timestamp (Unix ms)
   */
  async storeAuthTokens(
    accessToken: string,
    refreshToken: string,
    expiresAt: number
  ): Promise<void> {
    await Promise.all([
      this.store(accessToken, SecureStorageKeys.accessToken),
      this.store(refreshToken, SecureStorageKeys.refreshToken),
      this.store(expiresAt.toString(), SecureStorageKeys.tokenExpiresAt),
    ]);
    this.logger.debug('Auth tokens stored');
  }

  /**
   * Retrieve stored auth tokens
   *
   * @returns Stored tokens or null if not found
   */
  async retrieveAuthTokens(): Promise<{
    accessToken: string;
    refreshToken: string;
    expiresAt: number;
  } | null> {
    const [accessToken, refreshToken, expiresAtStr] = await Promise.all([
      this.retrieve(SecureStorageKeys.accessToken),
      this.retrieve(SecureStorageKeys.refreshToken),
      this.retrieve(SecureStorageKeys.tokenExpiresAt),
    ]);

    if (!accessToken || !refreshToken) {
      return null;
    }

    const expiresAt = expiresAtStr ? parseInt(expiresAtStr, 10) : 0;
    return { accessToken, refreshToken, expiresAt };
  }

  /**
   * Clear stored auth tokens
   */
  async clearAuthTokens(): Promise<void> {
    await Promise.all([
      this.delete(SecureStorageKeys.accessToken),
      this.delete(SecureStorageKeys.refreshToken),
      this.delete(SecureStorageKeys.tokenExpiresAt),
    ]);
    this.logger.debug('Auth tokens cleared');
  }

  // ============================================================
  // Identity Storage
  // ============================================================

  /**
   * Store identity information
   *
   * @param deviceId - Device ID from backend
   * @param userId - User ID (optional)
   * @param organizationId - Organization ID
   */
  async storeIdentity(
    deviceId: string,
    organizationId: string,
    userId?: string
  ): Promise<void> {
    const promises = [
      this.store(deviceId, SecureStorageKeys.deviceId),
      this.store(organizationId, SecureStorageKeys.organizationId),
    ];

    if (userId) {
      promises.push(this.store(userId, SecureStorageKeys.userId));
    }

    await Promise.all(promises);
    this.logger.debug('Identity info stored');
  }

  /**
   * Retrieve stored identity
   *
   * @returns Stored identity or null
   */
  async retrieveIdentity(): Promise<{
    deviceId: string;
    userId?: string;
    organizationId: string;
  } | null> {
    const [deviceId, userId, organizationId] = await Promise.all([
      this.retrieve(SecureStorageKeys.deviceId),
      this.retrieve(SecureStorageKeys.userId),
      this.retrieve(SecureStorageKeys.organizationId),
    ]);

    if (!deviceId || !organizationId) {
      return null;
    }

    return {
      deviceId,
      userId: userId ?? undefined,
      organizationId,
    };
  }

  /**
   * Clear all stored identity info
   */
  async clearIdentity(): Promise<void> {
    await Promise.all([
      this.delete(SecureStorageKeys.deviceId),
      this.delete(SecureStorageKeys.userId),
      this.delete(SecureStorageKeys.organizationId),
    ]);
    this.logger.debug('Identity info cleared');
  }

  // ============================================================
  // Utility
  // ============================================================

  /**
   * Clear all cached values
   */
  clearCache(): void {
    this.cache.clear();
  }

  /**
   * Clear all stored data (for logout/reset)
   */
  async clearAll(): Promise<void> {
    await Promise.all([
      this.clearSDKParams(),
      this.clearAuthTokens(),
      this.clearIdentity(),
      this.delete(SecureStorageKeys.deviceUUID),
    ]);
    this.clearCache();
    this.logger.info('All secure storage cleared');
  }
}

/**
 * Singleton instance
 */
export const SecureStorageService = new SecureStorageServiceImpl();
