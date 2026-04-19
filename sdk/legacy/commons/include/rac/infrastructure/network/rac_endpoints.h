/**
 * @file rac_endpoints.h
 * @brief API endpoint definitions
 *
 * Defines all API endpoint paths as constants.
 * This is the canonical source of truth - platform SDKs should not duplicate these.
 */

#ifndef RAC_ENDPOINTS_H
#define RAC_ENDPOINTS_H

#include "rac/infrastructure/network/rac_environment.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Authentication & Health Endpoints
// =============================================================================

#define RAC_ENDPOINT_AUTHENTICATE "/api/v1/auth/sdk/authenticate"
#define RAC_ENDPOINT_REFRESH "/api/v1/auth/sdk/refresh"
#define RAC_ENDPOINT_HEALTH "/v1/health"

// =============================================================================
// Device Management - Production/Staging
// =============================================================================

#define RAC_ENDPOINT_DEVICE_REGISTER "/api/v1/devices/register"
#define RAC_ENDPOINT_TELEMETRY "/api/v1/sdk/telemetry"

// =============================================================================
// Device Management - Development (Supabase REST API)
// =============================================================================

#define RAC_ENDPOINT_DEV_DEVICE_REGISTER "/rest/v1/sdk_devices"
#define RAC_ENDPOINT_DEV_TELEMETRY "/rest/v1/telemetry_events"

// =============================================================================
// Model Management
// =============================================================================

#define RAC_ENDPOINT_MODELS_AVAILABLE "/api/v1/models/available"

// =============================================================================
// Environment-Based Endpoint Selection
// =============================================================================

/**
 * @brief Get device registration endpoint for environment
 * @param env The environment
 * @return Endpoint path string
 */
const char* rac_endpoint_device_registration(rac_environment_t env);

/**
 * @brief Get telemetry endpoint for environment
 * @param env The environment
 * @return Endpoint path string
 */
const char* rac_endpoint_telemetry(rac_environment_t env);

/**
 * @brief Get model assignments endpoint
 * @return Endpoint path string
 */
const char* rac_endpoint_model_assignments(void);

// =============================================================================
// Full URL Building
// =============================================================================

/**
 * @brief Build full URL from base URL and endpoint
 * @param base_url The base URL (e.g., "https://api.runanywhere.ai")
 * @param endpoint The endpoint path (e.g., "/api/v1/health")
 * @param out_buffer Buffer to write full URL
 * @param buffer_size Size of buffer
 * @return Length of written string, or -1 on error
 */
int rac_build_url(const char* base_url, const char* endpoint, char* out_buffer, size_t buffer_size);

#ifdef __cplusplus
}
#endif

#endif  // RAC_ENDPOINTS_H
