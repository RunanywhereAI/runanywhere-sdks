/**
 * Authentication Service for RunAnywhere React Native SDK
 *
 * Manages authentication state and token management.
 * The actual auth logic lives in the native SDK.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/AuthenticationService.swift
 */

import { requireNativeModule } from '../native';
import { EventBus } from '../Public/Events';
import type { SDKEnvironment } from '../types';

/**
 * Authentication response from the backend
 */
export interface AuthenticationResponse {
  /** Access token for API calls */
  accessToken: string;
  /** Refresh token for obtaining new access tokens */
  refreshToken: string;
  /** Token expiration time in seconds */
  expiresIn: number;
  /** Device ID assigned by backend */
  deviceId: string;
  /** User ID (optional, may be null for org-level auth) */
  userId?: string;
  /** Organization ID */
  organizationId: string;
}

/**
 * Device registration info
 */
export interface DeviceRegistrationInfo {
  /** Device architecture (arm64, x86_64) */
  architecture: string;
  /** Available memory in bytes */
  availableMemory: number;
  /** Battery level (0-1) */
  batteryLevel: number;
  /** Battery state (charging, unplugged, full) */
  batteryState: string;
  /** Chip name (e.g., A17 Pro, Snapdragon 8) */
  chipName: string;
  /** Total CPU core count */
  coreCount: number;
  /** Device model identifier */
  deviceModel: string;
  /** Device name */
  deviceName: string;
  /** Number of efficiency cores */
  efficiencyCores: number;
  /** Form factor (phone, tablet, desktop) */
  formFactor: string;
  /** GPU family */
  gpuFamily: string;
  /** Whether device has Neural Engine */
  hasNeuralEngine: boolean;
  /** Whether low power mode is enabled */
  isLowPowerMode: boolean;
  /** Number of Neural Engine cores */
  neuralEngineCores: number;
  /** OS version */
  osVersion: string;
  /** Number of performance cores */
  performanceCores: number;
  /** Platform (ios, android) */
  platform: string;
  /** Total memory in bytes */
  totalMemory: number;
}

/**
 * Authentication state
 */
export interface AuthenticationState {
  /** Whether the user is authenticated */
  isAuthenticated: boolean;
  /** Whether authentication is in progress */
  isAuthenticating: boolean;
  /** Current user ID */
  userId?: string;
  /** Current organization ID */
  organizationId?: string;
  /** Current device ID */
  deviceId?: string;
  /** Current environment */
  environment?: SDKEnvironment;
}

/**
 * Authentication Service
 *
 * Handles SDK authentication and token management.
 */
class AuthenticationServiceImpl {
  private state: AuthenticationState = {
    isAuthenticated: false,
    isAuthenticating: false,
  };

  /**
   * Authenticate with the backend
   *
   * @param apiKey - The API key for authentication
   * @returns Authentication response
   */
  async authenticate(apiKey: string): Promise<AuthenticationResponse> {
    this.state.isAuthenticating = true;

    try {
      const native = requireNativeModule();
      const success = await native.authenticate(apiKey);

      if (!success) {
        throw new Error('Authentication failed');
      }

      // Get authentication details after successful auth
      const [userId, orgId, deviceId, accessToken] = await Promise.all([
        native.getUserId(),
        native.getOrganizationId(),
        native.getDeviceId(),
        native.getAccessToken(),
      ]);

      this.state = {
        isAuthenticated: true,
        isAuthenticating: false,
        userId: userId ?? undefined,
        organizationId: orgId ?? undefined,
        deviceId: deviceId ?? undefined,
      };

      // Build response from fetched data
      const response: AuthenticationResponse = {
        accessToken: accessToken ?? '',
        refreshToken: '', // Not exposed by native module
        expiresIn: 3600, // Default expiration
        deviceId: deviceId ?? '',
        userId: userId ?? undefined,
        organizationId: orgId ?? '',
      };

      return response;
    } catch (error) {
      this.state.isAuthenticating = false;
      throw error;
    }
  }

  /**
   * Get the current access token
   *
   * Will automatically refresh if expired.
   *
   * @returns Current access token
   */
  async getAccessToken(): Promise<string> {
    const native = requireNativeModule();
    const token = await native.getAccessToken();
    return token ?? '';
  }

  /**
   * Refresh the access token
   *
   * @returns New access token
   */
  async refreshAccessToken(): Promise<string> {
    const native = requireNativeModule();
    const token = await native.refreshAccessToken();
    return token ?? '';
  }

  /**
   * Check if authenticated
   */
  isAuthenticated(): boolean {
    return this.state.isAuthenticated;
  }

  /**
   * Check authentication status from native SDK
   */
  async checkAuthenticationStatus(): Promise<boolean> {
    const native = requireNativeModule();
    const isAuth = await native.isAuthenticated();
    this.state.isAuthenticated = isAuth;
    return isAuth;
  }

  /**
   * Clear authentication state
   */
  async clearAuthentication(): Promise<void> {
    const native = requireNativeModule();
    await native.clearAuthentication();

    this.state = {
      isAuthenticated: false,
      isAuthenticating: false,
    };
  }

  /**
   * Load stored tokens from secure storage
   */
  async loadStoredTokens(): Promise<void> {
    const native = requireNativeModule();
    await native.loadStoredTokens();

    // Update state after loading
    const [userId, orgId, deviceId] = await Promise.all([
      native.getUserId(),
      native.getOrganizationId(),
      native.getDeviceId(),
    ]);

    if (userId || orgId) {
      this.state.isAuthenticated = true;
      this.state.userId = userId ?? undefined;
      this.state.organizationId = orgId ?? undefined;
      this.state.deviceId = deviceId ?? undefined;
    }
  }

  /**
   * Get current user ID
   */
  async getUserId(): Promise<string | undefined> {
    if (this.state.userId) {
      return this.state.userId;
    }

    const native = requireNativeModule();
    const userId = await native.getUserId();
    this.state.userId = userId ?? undefined;
    return userId ?? undefined;
  }

  /**
   * Get current organization ID
   */
  async getOrganizationId(): Promise<string | undefined> {
    if (this.state.organizationId) {
      return this.state.organizationId;
    }

    const native = requireNativeModule();
    const orgId = await native.getOrganizationId();
    this.state.organizationId = orgId ?? undefined;
    return orgId ?? undefined;
  }

  /**
   * Get current device ID
   */
  async getDeviceId(): Promise<string | undefined> {
    if (this.state.deviceId) {
      return this.state.deviceId;
    }

    const native = requireNativeModule();
    const deviceId = await native.getDeviceId();
    this.state.deviceId = deviceId ?? undefined;
    return deviceId ?? undefined;
  }

  /**
   * Register device with backend
   *
   * Collects device information and registers with the backend.
   *
   * @returns Device registration response
   */
  async registerDevice(): Promise<{ deviceId: string }> {
    const native = requireNativeModule();
    // Native module expects deviceInfo JSON and returns boolean
    const deviceInfoJson = JSON.stringify({});
    const success = await native.registerDevice(deviceInfoJson);

    if (!success) {
      throw new Error('Device registration failed');
    }

    // Get device ID after registration
    const deviceId = await native.getDeviceId();
    return { deviceId: deviceId ?? '' };
  }

  /**
   * Perform health check
   *
   * @returns Health check response
   */
  async healthCheck(): Promise<{ status: string; timestamp: string }> {
    const native = requireNativeModule();
    const success = await native.healthCheck();
    return {
      status: success ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Get current authentication state
   */
  getState(): AuthenticationState {
    return { ...this.state };
  }

  /**
   * Reset the authentication service
   */
  reset(): void {
    this.state = {
      isAuthenticated: false,
      isAuthenticating: false,
    };
  }
}

/**
 * Singleton instance of the Authentication Service
 */
export const AuthenticationService = new AuthenticationServiceImpl();

export default AuthenticationService;
