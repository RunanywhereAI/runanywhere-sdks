/**
 * Authentication Service for RunAnywhere React Native SDK
 *
 * Manages authentication state, token management, and token refresh.
 * The actual auth logic lives in the native SDK - this TS layer provides:
 * - Token expiration tracking (with 60-second buffer like iOS)
 * - Lazy token refresh (on demand via getAccessToken)
 * - Secure storage of tokens via SecureStorageService
 * - State caching for fast access
 *
 * Also implements AuthenticationProvider interface for APIClient integration.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/AuthenticationService.swift
 */

import { requireNativeModule } from '../native';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { SecureStorageService } from '../Foundation/Security';
import { DeviceIdentityService } from '../Foundation/DeviceIdentity/DeviceIdentityService';
import type { SDKEnvironment } from '../types';
import type { AuthenticationProvider } from '../Data/Network';

/**
 * Token expiration buffer in milliseconds (60 seconds)
 * Matches iOS: expiresAt > Date().addingTimeInterval(60)
 */
const TOKEN_EXPIRATION_BUFFER_MS = 60 * 1000;

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
 * Stored token info with expiration
 */
interface TokenInfo {
  accessToken: string;
  refreshToken: string;
  /** Unix timestamp (ms) when token expires */
  expiresAt: number;
}

/**
 * Authentication Service
 *
 * Handles SDK authentication, token management, and automatic refresh.
 * Implements the same lazy refresh pattern as iOS.
 *
 * Also implements AuthenticationProvider interface for use with APIClient.
 */
class AuthenticationServiceImpl implements AuthenticationProvider {
  private readonly logger = new SDKLogger('AuthenticationService');

  private state: AuthenticationState = {
    isAuthenticated: false,
    isAuthenticating: false,
  };

  /** Cached token info */
  private tokenInfo: TokenInfo | null = null;

  /** Flag to prevent concurrent refresh operations */
  private isRefreshing = false;

  /** Promise for in-flight refresh (for request coalescing) */
  private refreshPromise: Promise<string> | null = null;

  /**
   * Authenticate with the backend
   *
   * @param apiKey - The API key for authentication
   * @returns Authentication response
   */
  async authenticate(apiKey: string): Promise<AuthenticationResponse> {
    this.state.isAuthenticating = true;
    this.logger.info('Starting authentication');

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

      // Build response
      const expiresIn = 3600; // Default 1 hour, native may provide actual value
      const response: AuthenticationResponse = {
        accessToken: accessToken ?? '',
        refreshToken: '', // Native handles refresh tokens
        expiresIn,
        deviceId: deviceId ?? '',
        userId: userId ?? undefined,
        organizationId: orgId ?? '',
      };

      // Store tokens locally with expiration
      const expiresAt = Date.now() + expiresIn * 1000;
      this.tokenInfo = {
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        expiresAt,
      };

      // Update state
      this.state = {
        isAuthenticated: true,
        isAuthenticating: false,
        userId: userId ?? undefined,
        organizationId: orgId ?? undefined,
        deviceId: deviceId ?? undefined,
      };

      // Store tokens and identity in secure storage
      await this.persistAuthData(response, expiresAt);

      this.logger.info('Authentication successful');
      return response;
    } catch (error) {
      this.state.isAuthenticating = false;
      this.logger.error('Authentication failed', error);
      throw error;
    }
  }

  /**
   * Get the current access token
   *
   * Automatically refreshes if token is expired or about to expire.
   * Uses 60-second buffer matching iOS behavior.
   *
   * @returns Current valid access token
   */
  async getAccessToken(): Promise<string> {
    // Check if we have a valid cached token
    if (this.tokenInfo && this.isTokenValid()) {
      return this.tokenInfo.accessToken;
    }

    // Token is expired or missing - need to refresh
    this.logger.debug('Token expired or missing, attempting refresh');

    // Try to refresh
    try {
      const token = await this.refreshAccessToken();
      return token;
    } catch (error) {
      // If refresh fails, try native as fallback
      this.logger.warning('Token refresh failed, trying native fallback');
      const native = requireNativeModule();
      const token = await native.getAccessToken();
      return token ?? '';
    }
  }

  /**
   * Check if the current token is valid
   *
   * Uses 60-second expiration buffer matching iOS.
   */
  private isTokenValid(): boolean {
    if (!this.tokenInfo) {
      return false;
    }

    const now = Date.now();
    const bufferTime = now + TOKEN_EXPIRATION_BUFFER_MS;
    return this.tokenInfo.expiresAt > bufferTime;
  }

  /**
   * Refresh the access token
   *
   * Implements request coalescing - concurrent refresh requests
   * will share the same underlying network request.
   *
   * @returns New access token
   */
  async refreshAccessToken(): Promise<string> {
    // If already refreshing, return the existing promise (coalescing)
    if (this.isRefreshing && this.refreshPromise) {
      this.logger.debug('Joining existing refresh request');
      return this.refreshPromise;
    }

    this.isRefreshing = true;
    this.refreshPromise = this.performRefresh();

    try {
      return await this.refreshPromise;
    } finally {
      this.isRefreshing = false;
      this.refreshPromise = null;
    }
  }

  /**
   * Actually perform the token refresh
   */
  private async performRefresh(): Promise<string> {
    this.logger.info('Refreshing access token');

    try {
      const native = requireNativeModule();
      const token = await native.refreshAccessToken();

      if (!token) {
        throw new Error('Token refresh returned empty token');
      }

      // Update cached token info
      // Native handles the actual refresh, we just update our cache
      const expiresIn = 3600; // Default, native may provide actual
      const expiresAt = Date.now() + expiresIn * 1000;

      this.tokenInfo = {
        accessToken: token,
        refreshToken: this.tokenInfo?.refreshToken ?? '',
        expiresAt,
      };

      // Persist updated tokens
      if (this.tokenInfo) {
        await SecureStorageService.storeAuthTokens(
          this.tokenInfo.accessToken,
          this.tokenInfo.refreshToken,
          this.tokenInfo.expiresAt
        );
      }

      this.logger.info('Token refresh successful');
      return token;
    } catch (error) {
      this.logger.error('Token refresh failed', error);
      throw error;
    }
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
    this.logger.info('Clearing authentication');

    const native = requireNativeModule();
    await native.clearAuthentication();

    // Clear local state
    this.tokenInfo = null;
    this.state = {
      isAuthenticated: false,
      isAuthenticating: false,
    };

    // Clear secure storage
    await Promise.all([
      SecureStorageService.clearAuthTokens(),
      SecureStorageService.clearIdentity(),
    ]);

    this.logger.info('Authentication cleared');
  }

  /**
   * Load stored tokens from secure storage
   *
   * Called on SDK startup to restore authentication state.
   */
  async loadStoredTokens(): Promise<void> {
    this.logger.debug('Loading stored tokens');

    try {
      // Load from native first (it may have more up-to-date tokens)
      const native = requireNativeModule();
      await native.loadStoredTokens();

      // Load from our secure storage
      const [tokens, identity] = await Promise.all([
        SecureStorageService.retrieveAuthTokens(),
        SecureStorageService.retrieveIdentity(),
      ]);

      if (tokens) {
        this.tokenInfo = tokens;
        this.logger.debug('Loaded tokens from storage');
      }

      // Get identity info
      const [userId, orgId, deviceId] = await Promise.all([
        native.getUserId(),
        native.getOrganizationId(),
        native.getDeviceId(),
      ]);

      if (userId || orgId) {
        this.state.isAuthenticated = true;
        this.state.userId = userId ?? identity?.userId;
        this.state.organizationId = orgId ?? identity?.organizationId;
        this.state.deviceId = deviceId ?? identity?.deviceId;
        this.logger.info('Restored authentication state');
      }
    } catch (error) {
      this.logger.warning('Failed to load stored tokens');
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
   * Get persistent device UUID
   *
   * This UUID is stored locally and survives app reinstalls.
   * Different from deviceId which is assigned by the backend.
   */
  async getPersistentDeviceUUID(): Promise<string> {
    return DeviceIdentityService.getPersistentDeviceUUID();
  }

  /**
   * Register device with backend
   *
   * Collects device information and registers with the backend.
   *
   * @returns Device registration response
   */
  async registerDevice(): Promise<{ deviceId: string }> {
    this.logger.info('Registering device');

    const native = requireNativeModule();

    // Get persistent device UUID - stored for reference
    const _persistentUUID = await this.getPersistentDeviceUUID();

    // Native module collects device info internally
    const success = await native.registerDevice();

    if (!success) {
      throw new Error('Device registration failed');
    }

    // Get device ID after registration
    const deviceId = await native.getDeviceId();
    this.state.deviceId = deviceId ?? undefined;

    this.logger.info('Device registration successful');
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
   * Get token expiration time
   *
   * @returns Unix timestamp (ms) when token expires, or null if no token
   */
  getTokenExpiresAt(): number | null {
    return this.tokenInfo?.expiresAt ?? null;
  }

  /**
   * Get time until token expires
   *
   * @returns Milliseconds until expiration, or null if no token
   */
  getTimeUntilExpiration(): number | null {
    if (!this.tokenInfo) {
      return null;
    }
    return Math.max(0, this.tokenInfo.expiresAt - Date.now());
  }

  /**
   * Reset the authentication service
   */
  reset(): void {
    this.tokenInfo = null;
    this.isRefreshing = false;
    this.refreshPromise = null;
    this.state = {
      isAuthenticated: false,
      isAuthenticating: false,
    };
    this.logger.debug('Authentication service reset');
  }

  /**
   * Persist auth data to secure storage
   */
  private async persistAuthData(
    response: AuthenticationResponse,
    expiresAt: number
  ): Promise<void> {
    try {
      await Promise.all([
        // Store tokens
        SecureStorageService.storeAuthTokens(
          response.accessToken,
          response.refreshToken,
          expiresAt
        ),
        // Store identity
        SecureStorageService.storeIdentity(
          response.deviceId,
          response.organizationId,
          response.userId
        ),
      ]);
    } catch (error) {
      this.logger.warning('Failed to persist auth data');
      // Don't throw - auth was successful, storage failure is non-fatal
    }
  }
}

/**
 * Singleton instance of the Authentication Service
 */
export const AuthenticationService = new AuthenticationServiceImpl();

export default AuthenticationService;
