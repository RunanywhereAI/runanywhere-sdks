/**
 * AuthenticationService.ts
 *
 * Service responsible for authentication and token management.
 * Matches iOS Data/Network/Services/AuthenticationService.swift
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/AuthenticationService.swift
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { DeviceIdentityService } from '../../../Foundation/DeviceIdentity/DeviceIdentityService';
import { SecureStorageService } from '../../../Foundation/Security';
import { SDKError, SDKErrorCode } from '../../../Public/Errors/SDKError';
import type { APIClient, AuthenticationProvider } from './APIClient';
import { APIEndpoints } from '../APIEndpoint';
import type { SDKEnvironment } from '../../../types';
import {
  type AuthenticationRequest,
  type AuthenticationResponse,
  type RefreshTokenRequest,
  type RefreshTokenResponse,
  type HealthCheckResponse,
  toInternalAuthResponse,
} from '../Models/AuthModels';

const logger = new SDKLogger('AuthenticationService');

/**
 * Storage keys for persisted auth tokens
 */
const AUTH_KEYS = {
  accessToken: 'com.runanywhere.sdk.accessToken',
  refreshToken: 'com.runanywhere.sdk.refreshToken',
  deviceId: 'com.runanywhere.sdk.deviceId',
  userId: 'com.runanywhere.sdk.userId',
  organizationId: 'com.runanywhere.sdk.organizationId',
  tokenExpiresAt: 'com.runanywhere.sdk.tokenExpiresAt',
} as const;

/**
 * Internal auth state
 */
interface AuthState {
  accessToken: string | null;
  refreshToken: string | null;
  tokenExpiresAt: Date | null;
  deviceId: string | null;
  userId: string | null;
  organizationId: string | null;
}

/**
 * Authentication Service
 *
 * Handles:
 * - Initial authentication with API key
 * - Token refresh when expired
 * - Token persistence in secure storage
 * - Device registration flow
 *
 * Implements AuthenticationProvider for use with APIClient.
 */
export class AuthenticationService implements AuthenticationProvider {
  private readonly apiClient: APIClient;
  private readonly environment: SDKEnvironment;
  private state: AuthState = {
    accessToken: null,
    refreshToken: null,
    tokenExpiresAt: null,
    deviceId: null,
    userId: null,
    organizationId: null,
  };

  private static _instance: AuthenticationService | null = null;

  constructor(apiClient: APIClient, environment: SDKEnvironment) {
    this.apiClient = apiClient;
    this.environment = environment;
  }

  /**
   * Create and configure authentication services for production/staging
   *
   * @param apiClient - The API client to use
   * @param apiKey - The API key for authentication
   * @param environment - The SDK environment
   * @returns Configured AuthenticationService
   */
  static async createAndAuthenticate(
    apiClient: APIClient,
    apiKey: string,
    environment: SDKEnvironment
  ): Promise<AuthenticationService> {
    const authService = new AuthenticationService(apiClient, environment);

    // Wire up auth provider to API client
    apiClient.setAuthenticationProvider(authService);

    // Authenticate with backend
    await authService.authenticate(apiKey);

    return authService;
  }

  // ============================================================================
  // AuthenticationProvider Implementation
  // ============================================================================

  /**
   * Get current access token for API requests
   *
   * Implements AuthenticationProvider interface.
   * Automatically refreshes token if expired.
   */
  async getAccessToken(): Promise<string | null> {
    // Check if token exists and is valid
    if (this.state.accessToken && this.state.tokenExpiresAt) {
      const now = new Date();
      const bufferTime = 60 * 1000; // 1 minute buffer
      if (this.state.tokenExpiresAt.getTime() > now.getTime() + bufferTime) {
        return this.state.accessToken;
      }
    }

    // Try to refresh token if we have a refresh token
    if (this.state.refreshToken) {
      try {
        const newToken = await this.refreshAccessToken();
        return newToken;
      } catch (error) {
        logger.warning('Token refresh failed:', { error });
        return null;
      }
    }

    return null;
  }

  // ============================================================================
  // Public API
  // ============================================================================

  /**
   * Authenticate with the backend and obtain access token
   *
   * @param apiKey - API key for authentication
   * @returns Authentication response
   */
  async authenticate(apiKey: string): Promise<AuthenticationResponse> {
    const deviceId = await DeviceIdentityService.getPersistentDeviceUUID();

    const request: AuthenticationRequest = {
      api_key: apiKey,
      device_id: deviceId,
      platform: 'react-native',
      sdk_version: '0.1.0', // TODO: Get from version file
    };

    logger.debug('Authenticating with backend');

    const endpoint = APIEndpoints.authenticate();
    const authResponse = await this.apiClient.post<
      AuthenticationRequest,
      AuthenticationResponse
    >(endpoint, request);

    // Store tokens and additional info
    const internal = toInternalAuthResponse(authResponse);
    this.state = {
      accessToken: internal.accessToken,
      refreshToken: internal.refreshToken,
      tokenExpiresAt: new Date(Date.now() + internal.expiresIn * 1000),
      deviceId: internal.deviceId,
      userId: internal.userId ?? null,
      organizationId: internal.organizationId,
    };

    // Store in secure storage for persistence
    await this.storeTokensInSecureStorage();

    logger.info('Authentication successful');
    return authResponse;
  }

  /**
   * Perform health check against backend
   */
  async healthCheck(): Promise<HealthCheckResponse> {
    logger.debug('Performing health check');

    const endpoint = APIEndpoints.healthCheck();
    return this.apiClient.get<HealthCheckResponse>(endpoint);
  }

  /**
   * Check if currently authenticated
   */
  isAuthenticated(): boolean {
    return this.state.accessToken !== null;
  }

  /**
   * Clear authentication state
   */
  async clearAuthentication(): Promise<void> {
    this.state = {
      accessToken: null,
      refreshToken: null,
      tokenExpiresAt: null,
      deviceId: null,
      userId: null,
      organizationId: null,
    };

    // Clear from secure storage
    try {
      await Promise.all([
        SecureStorageService.delete(AUTH_KEYS.accessToken),
        SecureStorageService.delete(AUTH_KEYS.refreshToken),
        SecureStorageService.delete(AUTH_KEYS.deviceId),
        SecureStorageService.delete(AUTH_KEYS.userId),
        SecureStorageService.delete(AUTH_KEYS.organizationId),
        SecureStorageService.delete(AUTH_KEYS.tokenExpiresAt),
      ]);
    } catch (error) {
      logger.warning('Error clearing auth tokens from storage:', { error });
    }

    logger.info('Authentication cleared');
  }

  /**
   * Load tokens from secure storage if available
   */
  async loadStoredTokens(): Promise<void> {
    try {
      const [
        accessToken,
        refreshToken,
        deviceId,
        userId,
        organizationId,
        expiresAt,
      ] = await Promise.all([
        SecureStorageService.retrieve(AUTH_KEYS.accessToken),
        SecureStorageService.retrieve(AUTH_KEYS.refreshToken),
        SecureStorageService.retrieve(AUTH_KEYS.deviceId),
        SecureStorageService.retrieve(AUTH_KEYS.userId),
        SecureStorageService.retrieve(AUTH_KEYS.organizationId),
        SecureStorageService.retrieve(AUTH_KEYS.tokenExpiresAt),
      ]);

      this.state = {
        accessToken,
        refreshToken,
        deviceId,
        userId,
        organizationId,
        tokenExpiresAt: expiresAt ? new Date(parseInt(expiresAt, 10)) : null,
      };

      if (accessToken) {
        logger.debug('Loaded stored tokens from secure storage');
      }
    } catch (error) {
      logger.debug('No stored tokens found or error loading:', { error });
    }
  }

  /**
   * Get current device ID
   */
  getDeviceId(): string | null {
    return this.state.deviceId;
  }

  /**
   * Get current user ID
   */
  getUserId(): string | null {
    return this.state.userId;
  }

  /**
   * Get current organization ID
   */
  getOrganizationId(): string | null {
    return this.state.organizationId;
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  private async refreshAccessToken(): Promise<string> {
    if (!this.state.refreshToken) {
      throw new SDKError(
        SDKErrorCode.AuthenticationFailed,
        'No refresh token available'
      );
    }

    if (!this.state.deviceId) {
      throw new SDKError(
        SDKErrorCode.AuthenticationFailed,
        'No device ID available for refresh'
      );
    }

    logger.debug('Refreshing access token');

    const request: RefreshTokenRequest = {
      device_id: this.state.deviceId,
      refresh_token: this.state.refreshToken,
    };

    const endpoint = APIEndpoints.refreshToken();
    const refreshResponse = await this.apiClient.post<
      RefreshTokenRequest,
      RefreshTokenResponse
    >(endpoint, request);

    // Update stored tokens
    const internal = toInternalAuthResponse(refreshResponse);
    this.state = {
      accessToken: internal.accessToken,
      refreshToken: internal.refreshToken,
      tokenExpiresAt: new Date(Date.now() + internal.expiresIn * 1000),
      deviceId: internal.deviceId,
      userId: internal.userId ?? null,
      organizationId: internal.organizationId,
    };

    // Store updated tokens
    await this.storeTokensInSecureStorage();

    logger.info('Token refresh successful');
    return internal.accessToken;
  }

  private async storeTokensInSecureStorage(): Promise<void> {
    try {
      const promises: Promise<void>[] = [];

      if (this.state.accessToken) {
        promises.push(
          SecureStorageService.store(
            AUTH_KEYS.accessToken,
            this.state.accessToken
          )
        );
      }
      if (this.state.refreshToken) {
        promises.push(
          SecureStorageService.store(
            AUTH_KEYS.refreshToken,
            this.state.refreshToken
          )
        );
      }
      if (this.state.deviceId) {
        promises.push(
          SecureStorageService.store(AUTH_KEYS.deviceId, this.state.deviceId)
        );
      }
      if (this.state.userId) {
        promises.push(
          SecureStorageService.store(AUTH_KEYS.userId, this.state.userId)
        );
      }
      if (this.state.organizationId) {
        promises.push(
          SecureStorageService.store(
            AUTH_KEYS.organizationId,
            this.state.organizationId
          )
        );
      }
      if (this.state.tokenExpiresAt) {
        promises.push(
          SecureStorageService.store(
            AUTH_KEYS.tokenExpiresAt,
            this.state.tokenExpiresAt.getTime().toString()
          )
        );
      }

      await Promise.all(promises);
    } catch (error) {
      logger.warning('Error storing tokens in secure storage:', { error });
    }
  }

  /**
   * Reset the singleton (for testing)
   */
  static reset(): void {
    AuthenticationService._instance = null;
  }
}
