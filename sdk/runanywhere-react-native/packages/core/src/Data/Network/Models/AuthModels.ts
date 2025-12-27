/**
 * AuthModels.ts
 *
 * Request/Response types for authentication endpoints.
 * Matches iOS Data/Network/Models/Auth/* types.
 *
 * Reference:
 * - sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Models/Auth/AuthenticationRequest.swift
 * - sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Models/Auth/AuthenticationResponse.swift
 * - sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Models/Auth/RefreshTokenRequest.swift
 */

/**
 * Authentication request payload
 *
 * Sent to /auth/authenticate endpoint
 */
export interface AuthenticationRequest {
  /** API key for authentication */
  api_key: string;
  /** Device ID (persistent UUID) */
  device_id: string;
  /** Platform identifier (ios, android, react-native) */
  platform: string;
  /** SDK version */
  sdk_version: string;
}

/**
 * Authentication response from backend
 *
 * Received from /auth/authenticate and /auth/refresh endpoints
 */
export interface AuthenticationResponse {
  /** Access token for API calls */
  access_token: string;
  /** Device ID assigned by backend */
  device_id: string;
  /** Token expiration time in seconds */
  expires_in: number;
  /** Organization ID */
  organization_id: string;
  /** Refresh token for obtaining new access tokens */
  refresh_token: string;
  /** Token type (always "bearer") */
  token_type: string;
  /** User ID (optional, may be null for org-level auth) */
  user_id?: string | null;
}

/**
 * Token refresh request payload
 *
 * Sent to /auth/refresh endpoint
 */
export interface RefreshTokenRequest {
  /** Device ID */
  device_id: string;
  /** Refresh token */
  refresh_token: string;
}

/**
 * Token refresh response
 *
 * Same structure as AuthenticationResponse
 */
export type RefreshTokenResponse = AuthenticationResponse;

/**
 * Device registration request payload
 *
 * Sent to /devices/register endpoint
 */
export interface DeviceRegistrationRequest {
  /** Device architecture (arm64, x86_64) */
  architecture: string;
  /** Available memory in bytes */
  available_memory: number;
  /** Battery level (0-1) */
  battery_level: number;
  /** Battery state (charging, unplugged, full) */
  battery_state: string;
  /** Chip name (e.g., A17 Pro, Snapdragon 8) */
  chip_name: string;
  /** Total CPU core count */
  core_count: number;
  /** Device model identifier */
  device_model: string;
  /** Device name */
  device_name: string;
  /** Number of efficiency cores */
  efficiency_cores: number;
  /** Form factor (phone, tablet, desktop) */
  form_factor: string;
  /** GPU family */
  gpu_family: string;
  /** Whether device has Neural Engine */
  has_neural_engine: boolean;
  /** Whether low power mode is enabled */
  is_low_power_mode: boolean;
  /** Number of Neural Engine cores */
  neural_engine_cores: number;
  /** OS version */
  os_version: string;
  /** Number of performance cores */
  performance_cores: number;
  /** Persistent device UUID */
  persistent_device_id: string;
  /** Platform (ios, android, react-native) */
  platform: string;
  /** Total memory in bytes */
  total_memory: number;
}

/**
 * Device registration response
 */
export interface DeviceRegistrationResponse {
  /** Device ID assigned by backend */
  device_id: string;
  /** Registration status */
  status: 'registered' | 'updated';
  /** Registration timestamp */
  registered_at: string;
}

/**
 * Health check response
 */
export interface HealthCheckResponse {
  /** Health status */
  status: 'healthy' | 'unhealthy' | 'degraded';
  /** Server timestamp */
  timestamp: string;
  /** Optional version info */
  version?: string;
}

/**
 * Convert camelCase AuthenticationResponse to internal format
 *
 * Backend uses snake_case, TypeScript uses camelCase
 */
export function toInternalAuthResponse(response: AuthenticationResponse): {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  deviceId: string;
  userId?: string;
  organizationId: string;
} {
  return {
    accessToken: response.access_token,
    refreshToken: response.refresh_token,
    expiresIn: response.expires_in,
    deviceId: response.device_id,
    userId: response.user_id ?? undefined,
    organizationId: response.organization_id,
  };
}

/**
 * Create AuthenticationRequest from internal format
 */
export function createAuthRequest(
  apiKey: string,
  deviceId: string,
  sdkVersion: string = '0.1.0'
): AuthenticationRequest {
  return {
    api_key: apiKey,
    device_id: deviceId,
    platform: 'react-native',
    sdk_version: sdkVersion,
  };
}

/**
 * Create RefreshTokenRequest
 */
export function createRefreshRequest(
  deviceId: string,
  refreshToken: string
): RefreshTokenRequest {
  return {
    device_id: deviceId,
    refresh_token: refreshToken,
  };
}
