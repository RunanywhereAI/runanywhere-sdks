/**
 * DeviceRegistrationService.ts
 *
 * Service for device registration with backend
 * Handles registration for development, staging, and production environments.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Device/Services/DeviceRegistrationService.swift
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { DeviceIdentityService } from '../../../Foundation/DeviceIdentity/DeviceIdentityService';
import { EventPublisher } from '../../Events/EventPublisher';
import {
  createDeviceRegisteredEvent,
  createDeviceRegistrationFailedEvent,
} from '../../Events/CommonEvents';
import type { SDKEnvironment } from '../../../types';
import type { APIClient } from '../../../Data/Network/Services/APIClient';
import { APIEndpoints } from '../../../Data/Network/APIEndpoint';

const logger = new SDKLogger('DeviceRegistration');

/**
 * Key for tracking registration status
 */
const REGISTERED_KEY = 'com.runanywhere.sdk.deviceRegistered';

/**
 * Simple async storage interface (uses React Native AsyncStorage pattern)
 */
interface AsyncStorageInterface {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/**
 * In-memory storage fallback (for testing or when AsyncStorage not available)
 */
const memoryStorage: Record<string, string> = {};
const fallbackStorage: AsyncStorageInterface = {
  async getItem(key: string): Promise<string | null> {
    return memoryStorage[key] ?? null;
  },
  async setItem(key: string, value: string): Promise<void> {
    memoryStorage[key] = value;
  },
  async removeItem(key: string): Promise<void> {
    delete memoryStorage[key];
  },
};

/**
 * Try to get AsyncStorage from React Native
 */
let asyncStorage: AsyncStorageInterface | null = null;
function getStorage(): AsyncStorageInterface {
  if (asyncStorage) {
    return asyncStorage;
  }
  try {
    // Try to dynamically import @react-native-async-storage/async-storage

    const AsyncStorage =
      require('@react-native-async-storage/async-storage').default;
    asyncStorage = AsyncStorage;
    return AsyncStorage;
  } catch {
    // Fall back to memory storage
    logger.debug('AsyncStorage not available, using memory storage');
    return fallbackStorage;
  }
}

/**
 * Device registration request
 * Matches iOS DeviceRegistrationRequest
 */
export interface DeviceRegistrationRequest {
  deviceId: string;
  platform: 'ios' | 'android';
  deviceModel: string;
  osVersion: string;
  appVersion: string;
  sdkVersion: string;
}

/**
 * Device registration response
 * Matches iOS DeviceRegistrationResponse
 */
export interface DeviceRegistrationResponse {
  deviceId: string;
  registered: boolean;
  timestamp: string;
}

/**
 * Device registration service
 *
 * Handles registration for development, staging, and production environments.
 * Uses APIClient for network calls.
 * Device UUID is managed by DeviceIdentityService (Keychain-persisted).
 */
export class DeviceRegistrationService {
  private static _instance: DeviceRegistrationService | null = null;

  /**
   * Shared singleton instance
   */
  static get shared(): DeviceRegistrationService {
    if (!DeviceRegistrationService._instance) {
      DeviceRegistrationService._instance = new DeviceRegistrationService();
    }
    return DeviceRegistrationService._instance;
  }

  /**
   * Get the persistent device ID
   */
  async getDeviceId(): Promise<string> {
    return DeviceIdentityService.getPersistentDeviceUUID();
  }

  /**
   * Get device ID synchronously (may be null if not cached)
   */
  get deviceId(): string | null {
    return DeviceIdentityService.getCachedDeviceUUID();
  }

  /**
   * Register device with backend if not already registered
   *
   * Works for all environments: development, staging, and production.
   * Development mode doesn't require auth, staging/production do.
   *
   * @param apiClient - API client for network calls
   * @param environment - Current SDK environment
   */
  async registerIfNeeded(
    apiClient: APIClient,
    environment: SDKEnvironment
  ): Promise<void> {
    // Skip if already registered
    if (await this.isRegistered()) {
      logger.debug('Device already registered, skipping');
      return;
    }

    const deviceId = await this.getDeviceId();
    logger.info(
      `Registering device: ${deviceId.substring(0, 8)}... [${environment}]`
    );

    try {
      const request = await this.createRegistrationRequest(deviceId);
      const endpoint =
        APIEndpoints.deviceRegistrationForEnvironment(environment);

      // Use APIClient for the request
      const response = await apiClient.post<
        DeviceRegistrationRequest,
        DeviceRegistrationResponse
      >(endpoint, request);

      if (response.registered) {
        await this.markAsRegistered();
        EventPublisher.shared.track(createDeviceRegisteredEvent(deviceId));
        logger.info('Device registration successful');
      }
    } catch (error) {
      // Registration failure is non-critical - log and continue
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      EventPublisher.shared.track(
        createDeviceRegistrationFailedEvent(errorMessage)
      );
      logger.warning(
        `Device registration failed (non-critical): ${errorMessage}`
      );
    }
  }

  /**
   * Check if device is registered
   */
  async isRegistered(): Promise<boolean> {
    const storage = getStorage();
    const value = await storage.getItem(REGISTERED_KEY);
    return value === 'true';
  }

  /**
   * Clear registration status (for testing/reset)
   */
  async clearRegistration(): Promise<void> {
    const storage = getStorage();
    await storage.removeItem(REGISTERED_KEY);
  }

  /**
   * Mark device as registered
   */
  private async markAsRegistered(): Promise<void> {
    const storage = getStorage();
    await storage.setItem(REGISTERED_KEY, 'true');
  }

  /**
   * Create device registration request from current device info
   */
  private async createRegistrationRequest(
    deviceId: string
  ): Promise<DeviceRegistrationRequest> {
    // Try to get device info from native module
    let platform: 'ios' | 'android' = 'ios';
    let deviceModel = 'Unknown';
    let osVersion = 'Unknown';

    try {
      const { requireDeviceInfoModule } = await import('../../../native');
      const deviceInfo = requireDeviceInfoModule();
      platform = ((await deviceInfo.getPlatform?.()) ?? 'ios') as
        | 'ios'
        | 'android';
      deviceModel = (await deviceInfo.getDeviceModel?.()) ?? 'Unknown';
      osVersion = (await deviceInfo.getOSVersion?.()) ?? 'Unknown';
    } catch {
      // Use fallback values if native module not available
      logger.debug('Native device info not available, using fallback values');
    }

    return {
      deviceId,
      platform,
      deviceModel,
      osVersion,
      appVersion: '1.0.0', // TODO: Get from app config
      sdkVersion: '0.1.0', // TODO: Get from SDK version
    };
  }

  /**
   * Reset the service (for testing)
   */
  static reset(): void {
    DeviceRegistrationService._instance = null;
  }
}
