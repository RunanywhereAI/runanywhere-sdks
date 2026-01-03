/**
 * @file rac_environment.h
 * @brief SDK environment configuration
 *
 * Defines environment types (development, staging, production) and their
 * associated settings like authentication requirements, log levels, etc.
 * This is the canonical source of truth - platform SDKs create thin wrappers.
 */

#ifndef RAC_ENVIRONMENT_H
#define RAC_ENVIRONMENT_H

#include <stdbool.h>
#include <stdint.h>

#include "rac/core/rac_types.h"  // For rac_log_level_t

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Environment Types
// =============================================================================

/**
 * @brief SDK environment mode
 *
 * - DEVELOPMENT: Local/testing mode, no auth required, uses Supabase
 * - STAGING: Testing with real services, requires API key + URL
 * - PRODUCTION: Live environment, requires API key + HTTPS URL
 */
typedef enum {
    RAC_ENV_DEVELOPMENT = 0,
    RAC_ENV_STAGING = 1,
    RAC_ENV_PRODUCTION = 2
} rac_environment_t;

// Note: rac_log_level_t is defined in rac_types.h
// We use the existing definition for consistency

// =============================================================================
// SDK Configuration
// =============================================================================

/**
 * @brief SDK initialization configuration
 *
 * Contains all parameters needed to initialize the SDK.
 * Platform SDKs populate this from their native config types.
 */
typedef struct {
    rac_environment_t environment;
    const char* api_key;      // Required for staging/production
    const char* base_url;     // Required for staging/production
    const char* device_id;    // Set by platform (Keychain UUID, etc.)
    const char* platform;     // "ios", "android", "flutter", etc.
    const char* sdk_version;  // SDK version string
} rac_sdk_config_t;

/**
 * @brief Development network configuration
 *
 * Contains Supabase credentials for development mode.
 * These are built into the SDK binary.
 */
typedef struct {
    const char* base_url;     // Supabase project URL
    const char* api_key;      // Supabase anon key
    const char* build_token;  // SDK build token for validation
} rac_dev_config_t;

// =============================================================================
// Environment Query Functions
// =============================================================================

/**
 * @brief Check if environment requires API authentication
 * @param env The environment to check
 * @return true for staging/production, false for development
 */
bool rac_env_requires_auth(rac_environment_t env);

/**
 * @brief Check if environment requires a backend URL
 * @param env The environment to check
 * @return true for staging/production, false for development
 */
bool rac_env_requires_backend_url(rac_environment_t env);

/**
 * @brief Check if environment is production
 * @param env The environment to check
 * @return true only for production
 */
bool rac_env_is_production(rac_environment_t env);

/**
 * @brief Check if environment is a testing environment
 * @param env The environment to check
 * @return true for development and staging
 */
bool rac_env_is_testing(rac_environment_t env);

/**
 * @brief Get the default log level for an environment
 * @param env The environment
 * @return DEBUG for development, INFO for staging, WARNING for production
 */
rac_log_level_t rac_env_default_log_level(rac_environment_t env);

/**
 * @brief Check if telemetry should be sent for this environment
 * @param env The environment
 * @return true only for production
 */
bool rac_env_should_send_telemetry(rac_environment_t env);

/**
 * @brief Check if environment should sync with backend
 * @param env The environment
 * @return true for staging/production, false for development
 */
bool rac_env_should_sync_with_backend(rac_environment_t env);

/**
 * @brief Get human-readable environment description
 * @param env The environment
 * @return String like "Development Environment"
 */
const char* rac_env_description(rac_environment_t env);

// =============================================================================
// Validation Functions
// =============================================================================

/**
 * @brief Validation result codes
 */
typedef enum {
    RAC_VALIDATION_OK = 0,
    RAC_VALIDATION_API_KEY_REQUIRED,
    RAC_VALIDATION_API_KEY_TOO_SHORT,
    RAC_VALIDATION_URL_REQUIRED,
    RAC_VALIDATION_URL_INVALID_SCHEME,
    RAC_VALIDATION_URL_HTTPS_REQUIRED,
    RAC_VALIDATION_URL_INVALID_HOST,
    RAC_VALIDATION_URL_LOCALHOST_NOT_ALLOWED,
    RAC_VALIDATION_PRODUCTION_DEBUG_BUILD
} rac_validation_result_t;

/**
 * @brief Validate API key for the given environment
 * @param api_key The API key to validate (can be NULL)
 * @param env The target environment
 * @return RAC_VALIDATION_OK if valid, error code otherwise
 */
rac_validation_result_t rac_validate_api_key(const char* api_key, rac_environment_t env);

/**
 * @brief Validate base URL for the given environment
 * @param url The URL to validate (can be NULL)
 * @param env The target environment
 * @return RAC_VALIDATION_OK if valid, error code otherwise
 */
rac_validation_result_t rac_validate_base_url(const char* url, rac_environment_t env);

/**
 * @brief Validate complete SDK configuration
 * @param config The configuration to validate
 * @return RAC_VALIDATION_OK if valid, first error code otherwise
 */
rac_validation_result_t rac_validate_config(const rac_sdk_config_t* config);

/**
 * @brief Get error message for validation result
 * @param result The validation result code
 * @return Human-readable error message
 */
const char* rac_validation_error_message(rac_validation_result_t result);

// =============================================================================
// Global SDK State
// =============================================================================

/**
 * @brief Initialize SDK with configuration
 * @param config The SDK configuration
 * @return RAC_VALIDATION_OK on success, error code on validation failure
 */
rac_validation_result_t rac_sdk_init(const rac_sdk_config_t* config);

/**
 * @brief Get current SDK configuration
 * @return Pointer to current config, or NULL if not initialized
 */
const rac_sdk_config_t* rac_sdk_get_config(void);

/**
 * @brief Get current environment
 * @return Current environment, or RAC_ENV_DEVELOPMENT if not initialized
 */
rac_environment_t rac_sdk_get_environment(void);

/**
 * @brief Check if SDK is initialized
 * @return true if rac_sdk_init has been called successfully
 */
bool rac_sdk_is_initialized(void);

/**
 * @brief Reset SDK state (for testing)
 */
void rac_sdk_reset(void);

#ifdef __cplusplus
}
#endif

#endif  // RAC_ENVIRONMENT_H
