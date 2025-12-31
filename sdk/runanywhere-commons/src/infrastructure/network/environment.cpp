/**
 * @file environment.cpp
 * @brief SDK environment configuration implementation
 */

#include <cctype>
#include <cstring>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_environment.h"

// =============================================================================
// Global State
// =============================================================================

static bool g_sdk_initialized = false;
static rac_sdk_config_t g_sdk_config = {};

// Static storage for config strings (to avoid dangling pointers)
static char g_api_key[256] = {0};
static char g_base_url[512] = {0};
static char g_device_id[128] = {0};
static char g_platform[32] = {0};
static char g_sdk_version[32] = {0};

// =============================================================================
// Environment Query Functions
// =============================================================================

bool rac_env_requires_auth(rac_environment_t env) {
    return env != RAC_ENV_DEVELOPMENT;
}

bool rac_env_requires_backend_url(rac_environment_t env) {
    return env != RAC_ENV_DEVELOPMENT;
}

bool rac_env_is_production(rac_environment_t env) {
    return env == RAC_ENV_PRODUCTION;
}

bool rac_env_is_testing(rac_environment_t env) {
    return env == RAC_ENV_DEVELOPMENT || env == RAC_ENV_STAGING;
}

rac_log_level_t rac_env_default_log_level(rac_environment_t env) {
    switch (env) {
        case RAC_ENV_DEVELOPMENT:
            return RAC_LOG_DEBUG;  // From rac_types.h: 1
        case RAC_ENV_STAGING:
            return RAC_LOG_INFO;  // From rac_types.h: 2
        case RAC_ENV_PRODUCTION:
            return RAC_LOG_WARNING;  // From rac_types.h: 3
        default:
            return RAC_LOG_INFO;
    }
}

bool rac_env_should_send_telemetry(rac_environment_t env) {
    return env == RAC_ENV_PRODUCTION;
}

bool rac_env_should_sync_with_backend(rac_environment_t env) {
    return env != RAC_ENV_DEVELOPMENT;
}

const char* rac_env_description(rac_environment_t env) {
    switch (env) {
        case RAC_ENV_DEVELOPMENT:
            return "Development Environment";
        case RAC_ENV_STAGING:
            return "Staging Environment";
        case RAC_ENV_PRODUCTION:
            return "Production Environment";
        default:
            return "Unknown Environment";
    }
}

// =============================================================================
// URL Parsing Helpers
// =============================================================================

// Simple URL scheme extraction
static bool extract_url_scheme(const char* url, char* scheme, size_t scheme_size) {
    if (!url || !scheme || scheme_size == 0)
        return false;

    const char* colon = strchr(url, ':');
    if (!colon)
        return false;

    size_t len = colon - url;
    if (len >= scheme_size)
        return false;

    for (size_t i = 0; i < len; i++) {
        scheme[i] = (char)tolower((unsigned char)url[i]);
    }
    scheme[len] = '\0';
    return true;
}

// Simple URL host extraction (after ://)
static bool extract_url_host(const char* url, char* host, size_t host_size) {
    if (!url || !host || host_size == 0)
        return false;

    const char* start = strstr(url, "://");
    if (!start)
        return false;
    start += 3;  // Skip "://"

    // Find end of host (port, path, or end of string)
    const char* end = start;
    while (*end && *end != ':' && *end != '/' && *end != '?' && *end != '#') {
        end++;
    }

    size_t len = end - start;
    if (len == 0 || len >= host_size)
        return false;

    for (size_t i = 0; i < len; i++) {
        host[i] = (char)tolower((unsigned char)start[i]);
    }
    host[len] = '\0';
    return true;
}

// Check if host is localhost-like
static bool is_localhost_host(const char* host) {
    if (!host)
        return false;
    return strstr(host, "localhost") != nullptr || strstr(host, "127.0.0.1") != nullptr ||
           strstr(host, "example.com") != nullptr || strstr(host, ".local") != nullptr;
}

// =============================================================================
// Validation Functions
// =============================================================================

rac_validation_result_t rac_validate_api_key(const char* api_key, rac_environment_t env) {
    // Development mode doesn't require API key
    if (!rac_env_requires_auth(env)) {
        return RAC_VALIDATION_OK;
    }

    // Staging/Production require API key
    if (!api_key || api_key[0] == '\0') {
        return RAC_VALIDATION_API_KEY_REQUIRED;
    }

    // Basic length check (at least 10 characters)
    if (strlen(api_key) < 10) {
        return RAC_VALIDATION_API_KEY_TOO_SHORT;
    }

    return RAC_VALIDATION_OK;
}

rac_validation_result_t rac_validate_base_url(const char* url, rac_environment_t env) {
    // Development mode doesn't require URL
    if (!rac_env_requires_backend_url(env)) {
        return RAC_VALIDATION_OK;
    }

    // Staging/Production require URL
    if (!url || url[0] == '\0') {
        return RAC_VALIDATION_URL_REQUIRED;
    }

    // Extract and validate scheme
    char scheme[16] = {0};
    if (!extract_url_scheme(url, scheme, sizeof(scheme))) {
        return RAC_VALIDATION_URL_INVALID_SCHEME;
    }

    // Production requires HTTPS
    if (env == RAC_ENV_PRODUCTION) {
        if (strcmp(scheme, "https") != 0) {
            return RAC_VALIDATION_URL_HTTPS_REQUIRED;
        }
    } else if (env == RAC_ENV_STAGING) {
        // Staging allows HTTP or HTTPS
        if (strcmp(scheme, "https") != 0 && strcmp(scheme, "http") != 0) {
            return RAC_VALIDATION_URL_INVALID_SCHEME;
        }
    }

    // Extract and validate host
    char host[256] = {0};
    if (!extract_url_host(url, host, sizeof(host))) {
        return RAC_VALIDATION_URL_INVALID_HOST;
    }

    if (host[0] == '\0') {
        return RAC_VALIDATION_URL_INVALID_HOST;
    }

    // Production cannot use localhost/example URLs
    if (env == RAC_ENV_PRODUCTION && is_localhost_host(host)) {
        return RAC_VALIDATION_URL_LOCALHOST_NOT_ALLOWED;
    }

    return RAC_VALIDATION_OK;
}

rac_validation_result_t rac_validate_config(const rac_sdk_config_t* config) {
    if (!config) {
        return RAC_VALIDATION_API_KEY_REQUIRED;
    }

    rac_validation_result_t result;

    // Validate API key
    result = rac_validate_api_key(config->api_key, config->environment);
    if (result != RAC_VALIDATION_OK) {
        return result;
    }

    // Validate URL
    result = rac_validate_base_url(config->base_url, config->environment);
    if (result != RAC_VALIDATION_OK) {
        return result;
    }

    return RAC_VALIDATION_OK;
}

const char* rac_validation_error_message(rac_validation_result_t result) {
    switch (result) {
        case RAC_VALIDATION_OK:
            return "Validation successful";
        case RAC_VALIDATION_API_KEY_REQUIRED:
            return "API key is required for this environment";
        case RAC_VALIDATION_API_KEY_TOO_SHORT:
            return "API key appears to be invalid (too short)";
        case RAC_VALIDATION_URL_REQUIRED:
            return "Base URL is required for this environment";
        case RAC_VALIDATION_URL_INVALID_SCHEME:
            return "Base URL must have a valid scheme (http or https)";
        case RAC_VALIDATION_URL_HTTPS_REQUIRED:
            return "Production environment requires HTTPS";
        case RAC_VALIDATION_URL_INVALID_HOST:
            return "Base URL must have a valid host";
        case RAC_VALIDATION_URL_LOCALHOST_NOT_ALLOWED:
            return "Production environment cannot use localhost or example URLs";
        case RAC_VALIDATION_PRODUCTION_DEBUG_BUILD:
            return "Production environment cannot be used in DEBUG builds";
        default:
            return "Unknown validation error";
    }
}

// =============================================================================
// Global SDK State Functions
// =============================================================================

// Helper to safely copy string
static void safe_strcpy(char* dest, size_t dest_size, const char* src) {
    if (!dest || dest_size == 0)
        return;
    if (!src) {
        dest[0] = '\0';
        return;
    }
    size_t len = strlen(src);
    if (len >= dest_size) {
        len = dest_size - 1;
    }
    memcpy(dest, src, len);
    dest[len] = '\0';
}

rac_validation_result_t rac_sdk_init(const rac_sdk_config_t* config) {
    if (!config) {
        return RAC_VALIDATION_API_KEY_REQUIRED;
    }

    // Validate configuration
    rac_validation_result_t result = rac_validate_config(config);
    if (result != RAC_VALIDATION_OK) {
        return result;
    }

    // Store configuration with deep copy of strings
    g_sdk_config.environment = config->environment;

    safe_strcpy(g_api_key, sizeof(g_api_key), config->api_key);
    g_sdk_config.api_key = g_api_key;

    safe_strcpy(g_base_url, sizeof(g_base_url), config->base_url);
    g_sdk_config.base_url = g_base_url;

    safe_strcpy(g_device_id, sizeof(g_device_id), config->device_id);
    g_sdk_config.device_id = g_device_id;

    safe_strcpy(g_platform, sizeof(g_platform), config->platform);
    g_sdk_config.platform = g_platform;

    safe_strcpy(g_sdk_version, sizeof(g_sdk_version), config->sdk_version);
    g_sdk_config.sdk_version = g_sdk_version;

    g_sdk_initialized = true;
    return RAC_VALIDATION_OK;
}

const rac_sdk_config_t* rac_sdk_get_config(void) {
    if (!g_sdk_initialized) {
        return nullptr;
    }
    return &g_sdk_config;
}

rac_environment_t rac_sdk_get_environment(void) {
    if (!g_sdk_initialized) {
        return RAC_ENV_DEVELOPMENT;
    }
    return g_sdk_config.environment;
}

bool rac_sdk_is_initialized(void) {
    return g_sdk_initialized;
}

void rac_sdk_reset(void) {
    g_sdk_initialized = false;
    memset(&g_sdk_config, 0, sizeof(g_sdk_config));
    memset(g_api_key, 0, sizeof(g_api_key));
    memset(g_base_url, 0, sizeof(g_base_url));
    memset(g_device_id, 0, sizeof(g_device_id));
    memset(g_platform, 0, sizeof(g_platform));
    memset(g_sdk_version, 0, sizeof(g_sdk_version));
}
