/**
 * APIEndpoint.ts
 *
 * Defines all API endpoints used by the RunAnywhere SDK.
 * Matches iOS implementation for consistency.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/APIEndpoint.swift
 */

import type { SDKEnvironment } from '../../types';

/**
 * API endpoint types matching iOS APIEndpoint enum
 */
export type APIEndpointType =
  // Authentication & Health
  | 'authenticate'
  | 'refreshToken'
  | 'healthCheck'
  // Device Management - Production/Staging
  | 'deviceRegistration'
  | 'analytics'
  // Device Management - Development
  | 'devDeviceRegistration'
  | 'devAnalytics'
  // Model Management
  | 'modelAssignments'
  // Core endpoints
  | 'telemetry'
  | 'models'
  | 'deviceInfo'
  | 'generationHistory'
  | 'userPreferences';

/**
 * API endpoint definition
 */
export interface APIEndpointDefinition {
  /** Endpoint path (without base URL) */
  readonly path: string;
  /** HTTP method */
  readonly method: 'GET' | 'POST' | 'PUT' | 'DELETE';
}

/**
 * Create an endpoint for authentication
 */
export function authenticateEndpoint(): APIEndpointDefinition {
  return {
    path: '/auth/authenticate',
    method: 'POST',
  };
}

/**
 * Create an endpoint for token refresh
 */
export function refreshTokenEndpoint(): APIEndpointDefinition {
  return {
    path: '/auth/refresh',
    method: 'POST',
  };
}

/**
 * Create an endpoint for health check
 */
export function healthCheckEndpoint(): APIEndpointDefinition {
  return {
    path: '/health',
    method: 'GET',
  };
}

/**
 * Create an endpoint for device registration (production/staging)
 */
export function deviceRegistrationEndpoint(): APIEndpointDefinition {
  return {
    path: '/devices/register',
    method: 'POST',
  };
}

/**
 * Create an endpoint for analytics (production/staging)
 */
export function analyticsEndpoint(): APIEndpointDefinition {
  return {
    path: '/analytics/events',
    method: 'POST',
  };
}

/**
 * Create an endpoint for device registration (development)
 */
export function devDeviceRegistrationEndpoint(): APIEndpointDefinition {
  return {
    path: '/rest/v1/devices',
    method: 'POST',
  };
}

/**
 * Create an endpoint for analytics (development)
 */
export function devAnalyticsEndpoint(): APIEndpointDefinition {
  return {
    path: '/rest/v1/analytics',
    method: 'POST',
  };
}

/**
 * Create an endpoint for model assignments
 */
export function modelAssignmentsEndpoint(
  deviceType: string,
  platform: string
): APIEndpointDefinition {
  return {
    path: `/models/assignments?device_type=${encodeURIComponent(deviceType)}&platform=${encodeURIComponent(platform)}`,
    method: 'GET',
  };
}

/**
 * Create an endpoint for telemetry
 */
export function telemetryEndpoint(): APIEndpointDefinition {
  return {
    path: '/telemetry',
    method: 'POST',
  };
}

/**
 * Create an endpoint for models list
 */
export function modelsEndpoint(): APIEndpointDefinition {
  return {
    path: '/models',
    method: 'GET',
  };
}

/**
 * Create an endpoint for device info
 */
export function deviceInfoEndpoint(): APIEndpointDefinition {
  return {
    path: '/devices/info',
    method: 'GET',
  };
}

/**
 * Create an endpoint for generation history
 */
export function generationHistoryEndpoint(): APIEndpointDefinition {
  return {
    path: '/history/generations',
    method: 'GET',
  };
}

/**
 * Create an endpoint for user preferences
 */
export function userPreferencesEndpoint(): APIEndpointDefinition {
  return {
    path: '/users/preferences',
    method: 'GET',
  };
}

/**
 * Get the appropriate device registration endpoint for an environment
 *
 * Matches iOS: APIEndpoint.deviceRegistrationEndpoint(for:)
 */
export function deviceRegistrationEndpointForEnvironment(
  environment: SDKEnvironment
): APIEndpointDefinition {
  if (environment === 'development') {
    return devDeviceRegistrationEndpoint();
  }
  return deviceRegistrationEndpoint();
}

/**
 * Get the appropriate analytics endpoint for an environment
 *
 * Matches iOS: APIEndpoint.analyticsEndpoint(for:)
 */
export function analyticsEndpointForEnvironment(
  environment: SDKEnvironment
): APIEndpointDefinition {
  if (environment === 'development') {
    return devAnalyticsEndpoint();
  }
  return analyticsEndpoint();
}

/**
 * All API endpoints grouped by category
 *
 * Usage:
 *   const endpoint = APIEndpoints.authenticate();
 *   apiClient.post(endpoint, payload);
 */
export const APIEndpoints = {
  // Authentication & Health
  authenticate: authenticateEndpoint,
  refreshToken: refreshTokenEndpoint,
  healthCheck: healthCheckEndpoint,

  // Device Management
  deviceRegistration: deviceRegistrationEndpoint,
  analytics: analyticsEndpoint,
  devDeviceRegistration: devDeviceRegistrationEndpoint,
  devAnalytics: devAnalyticsEndpoint,

  // Environment-aware endpoints
  deviceRegistrationForEnvironment: deviceRegistrationEndpointForEnvironment,
  analyticsForEnvironment: analyticsEndpointForEnvironment,

  // Model Management
  modelAssignments: modelAssignmentsEndpoint,

  // Core endpoints
  telemetry: telemetryEndpoint,
  models: modelsEndpoint,
  deviceInfo: deviceInfoEndpoint,
  generationHistory: generationHistoryEndpoint,
  userPreferences: userPreferencesEndpoint,
} as const;
