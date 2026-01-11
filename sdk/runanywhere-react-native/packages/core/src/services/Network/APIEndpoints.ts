/**
 * APIEndpoints.ts
 *
 * API endpoint constants.
 *
 * Production endpoints use /api/v1/* prefix (Railway)
 * Development endpoints use Supabase REST API paths
 *
 * Reference: sdk/runanywhere-commons/include/rac/infrastructure/network/rac_endpoints.h
 */

/**
 * API endpoint paths
 */
export const APIEndpoints = {
  // ============================================================================
  // Authentication
  // ============================================================================

  /** SDK authentication endpoint - POST with API key to get access token */
  AUTHENTICATE: '/api/v1/auth/sdk/authenticate',

  /** Token refresh endpoint - POST with refresh token */
  REFRESH_TOKEN: '/api/v1/auth/sdk/refresh',

  // ============================================================================
  // Device Registration
  // ============================================================================

  /** Device registration (production) */
  DEVICE_REGISTER: '/api/v1/devices/register',

  /** Device registration (development - Supabase) */
  DEV_DEVICE_REGISTER: '/rest/v1/sdk_devices',

  // ============================================================================
  // Models
  // ============================================================================

  /** Get available models */
  MODELS_LIST: '/api/v1/models',

  /** Get model details (append /{modelId}) */
  MODEL_INFO: '/api/v1/models',

  /** Model assignments */
  MODEL_ASSIGNMENTS: '/api/v1/model-assignments',

  /** Model assignments (development - Supabase) */
  DEV_MODEL_ASSIGNMENTS: '/rest/v1/sdk_model_assignments',

  // ============================================================================
  // Telemetry
  // Matches C++: RAC_ENDPOINT_TELEMETRY, RAC_ENDPOINT_DEV_TELEMETRY
  // ============================================================================

  /** Send telemetry events (production) */
  TELEMETRY: '/api/v1/sdk/telemetry',

  /** Send telemetry events (development - Supabase) */
  DEV_TELEMETRY: '/rest/v1/telemetry_events',

  // ============================================================================
  // Usage
  // ============================================================================

  /** Report usage metrics */
  USAGE: '/api/v1/usage',

  /** Get usage summary */
  USAGE_SUMMARY: '/api/v1/usage/summary',
} as const;

/**
 * Type for endpoint keys
 */
export type APIEndpointKey = keyof typeof APIEndpoints;

/**
 * Type for endpoint values
 */
export type APIEndpointValue = (typeof APIEndpoints)[APIEndpointKey];

export default APIEndpoints;
