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
      const response = await native.authenticate(apiKey);

      this.state = {
        isAuthenticated: true,
        isAuthenticating: false,
        userId: response.userId,
        organizationId: response.organizationId,
        deviceId: response.deviceId,
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
    return native.getAccessToken();
  }

  /**
   * Refresh the access token
   *
   * @returns New access token
   */
  async refreshAccessToken(): Promise<string> {
    const native = requireNativeModule();
    return native.refreshAccessToken();
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
      this.state.userId = userId;
      this.state.organizationId = orgId;
      this.state.deviceId = deviceId;
    }
  }

  /**
   * Get current user ID
   */
  async getUserId(): Promise<string | null> {
    if (this.state.userId) {
      return this.state.userId;
    }

    const native = requireNativeModule();
    const userId = await native.getUserId();
    this.state.userId = userId;
    return userId;
  }

  /**
   * Get current organization ID
   */
  async getOrganizationId(): Promise<string | null> {
    if (this.state.organizationId) {
      return this.state.organizationId;
    }

    const native = requireNativeModule();
    const orgId = await native.getOrganizationId();
    this.state.organizationId = orgId;
    return orgId;
  }

  /**
   * Get current device ID
   */
  async getDeviceId(): Promise<string | null> {
    if (this.state.deviceId) {
      return this.state.deviceId;
    }

    const native = requireNativeModule();
    const deviceId = await native.getDeviceId();
    this.state.deviceId = deviceId;
    return deviceId;
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
    return native.registerDevice();
  }

  /**
   * Perform health check
   *
   * @returns Health check response
   */
  async healthCheck(): Promise<{ status: string; timestamp: string }> {
    const native = requireNativeModule();
    return native.healthCheck();
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
