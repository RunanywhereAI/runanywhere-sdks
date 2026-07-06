/**
 * @file environment.cpp
 * @brief SDK environment configuration implementation
 */

#include <cctype>
#include <cstring>
#include <mutex>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_environment.h"

// =============================================================================
// Global State
// =============================================================================

static bool g_sdk_initialized = false;
static rac_sdk_config_t g_sdk_config = {};
static std::mutex g_sdk_state_mutex;

// Static storage for config strings (to avoid dangling pointers)
static char g_api_key[256] = {0};
static char g_base_url[512] = {0};
static char g_device_id[128] = {0};
static char g_platform[32] = {0};
static char g_sdk_version[32] = {0};
static char g_sdk_binding[64] = {0};
static char g_app_identifier[256] = {0};
static char g_app_name[256] = {0};
static char g_app_version[64] = {0};
static char g_app_build[64] = {0};
static char g_locale[64] = {0};
static char g_timezone[128] = {0};
static rac_client_info_t g_client_info = {};

struct ClientInfoSnapshotStorage {
    char sdk_binding[sizeof(g_sdk_binding)] = {0};
    char app_identifier[sizeof(g_app_identifier)] = {0};
    char app_name[sizeof(g_app_name)] = {0};
    char app_version[sizeof(g_app_version)] = {0};
    char app_build[sizeof(g_app_build)] = {0};
    char locale[sizeof(g_locale)] = {0};
    char timezone[sizeof(g_timezone)] = {0};
    rac_client_info_t info = {};
};

struct SdkConfigSnapshotStorage {
    char api_key[sizeof(g_api_key)] = {0};
    char base_url[sizeof(g_base_url)] = {0};
    char device_id[sizeof(g_device_id)] = {0};
    char platform[sizeof(g_platform)] = {0};
    char sdk_version[sizeof(g_sdk_version)] = {0};
    ClientInfoSnapshotStorage client_info;
    rac_sdk_config_t config = {};
};

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
    // Telemetry is sent in every environment — development flushes immediately to
    // the local backend, staging and production batch + send with auth. This must
    // agree with the actual send gate (rac_env_requires_auth, also !=DEVELOPMENT);
    // returning production-only here previously contradicted that and mislabeled
    // staging as "no telemetry" even though staging does send.
    return env != RAC_ENV_DEVELOPMENT;
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

// In DEV mode the SDK targets an operator-
// side DNS alias (e.g. dev.runanywhere.local). When the alias is not
// configured locally the OS resolver burns its full default timeout
// before the request can fail, blocking SDK init for ~30 s per cold
// launch. Returning a short timeout here lets platform HTTP layers
// (URLSession / Dart HttpClient / Kotlin HttpURLConnection) fail fast
// in DEV without hurting production reliability.
int32_t rac_env_default_http_timeout_ms(rac_environment_t env) {
    switch (env) {
        case RAC_ENV_DEVELOPMENT:
            return 3000;  // 3s — fail fast on unreachable dev DNS
        case RAC_ENV_STAGING:
        case RAC_ENV_PRODUCTION:
        default:
            return 30000;  // 30s — generous default for real backends
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
    while (*end != '\0' && *end != ':' && *end != '/' && *end != '?' && *end != '#') {
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

static void point_client_info_at_storage(rac_client_info_t* info,
                                         ClientInfoSnapshotStorage* storage) {
    info->sdk_binding = storage->sdk_binding;
    info->app_identifier = storage->app_identifier;
    info->app_name = storage->app_name;
    info->app_version = storage->app_version;
    info->app_build = storage->app_build;
    info->locale = storage->locale;
    info->timezone = storage->timezone;
}

static void snapshot_client_info(ClientInfoSnapshotStorage* snapshot,
                                 const rac_client_info_t* client_info) {
    safe_strcpy(snapshot->sdk_binding, sizeof(snapshot->sdk_binding),
                client_info ? client_info->sdk_binding : nullptr);
    safe_strcpy(snapshot->app_identifier, sizeof(snapshot->app_identifier),
                client_info ? client_info->app_identifier : nullptr);
    safe_strcpy(snapshot->app_name, sizeof(snapshot->app_name),
                client_info ? client_info->app_name : nullptr);
    safe_strcpy(snapshot->app_version, sizeof(snapshot->app_version),
                client_info ? client_info->app_version : nullptr);
    safe_strcpy(snapshot->app_build, sizeof(snapshot->app_build),
                client_info ? client_info->app_build : nullptr);
    safe_strcpy(snapshot->locale, sizeof(snapshot->locale),
                client_info ? client_info->locale : nullptr);
    safe_strcpy(snapshot->timezone, sizeof(snapshot->timezone),
                client_info ? client_info->timezone : nullptr);
    point_client_info_at_storage(&snapshot->info, snapshot);
}

static void copy_client_info(const rac_client_info_t* client_info) {
    safe_strcpy(g_sdk_binding, sizeof(g_sdk_binding),
                client_info ? client_info->sdk_binding : nullptr);
    safe_strcpy(g_app_identifier, sizeof(g_app_identifier),
                client_info ? client_info->app_identifier : nullptr);
    safe_strcpy(g_app_name, sizeof(g_app_name), client_info ? client_info->app_name : nullptr);
    safe_strcpy(g_app_version, sizeof(g_app_version),
                client_info ? client_info->app_version : nullptr);
    safe_strcpy(g_app_build, sizeof(g_app_build), client_info ? client_info->app_build : nullptr);
    safe_strcpy(g_locale, sizeof(g_locale), client_info ? client_info->locale : nullptr);
    safe_strcpy(g_timezone, sizeof(g_timezone), client_info ? client_info->timezone : nullptr);

    g_client_info.sdk_binding = g_sdk_binding;
    g_client_info.app_identifier = g_app_identifier;
    g_client_info.app_name = g_app_name;
    g_client_info.app_version = g_app_version;
    g_client_info.app_build = g_app_build;
    g_client_info.locale = g_locale;
    g_client_info.timezone = g_timezone;
}

static bool client_info_has_value(const rac_client_info_t* client_info) {
    if (!client_info) {
        return false;
    }
    return (client_info->sdk_binding && client_info->sdk_binding[0] != '\0') ||
           (client_info->app_identifier && client_info->app_identifier[0] != '\0') ||
           (client_info->app_name && client_info->app_name[0] != '\0') ||
           (client_info->app_version && client_info->app_version[0] != '\0') ||
           (client_info->app_build && client_info->app_build[0] != '\0') ||
           (client_info->locale && client_info->locale[0] != '\0') ||
           (client_info->timezone && client_info->timezone[0] != '\0');
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

    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);

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

    if (client_info_has_value(&config->client_info)) {
        copy_client_info(&config->client_info);
    }
    g_sdk_config.client_info = g_client_info;

    g_sdk_initialized = true;
    return RAC_VALIDATION_OK;
}

const rac_sdk_config_t* rac_sdk_get_config(void) {
    thread_local SdkConfigSnapshotStorage snapshot;

    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);
    if (!g_sdk_initialized) {
        return nullptr;
    }

    snapshot.config = {};
    snapshot.config.environment = g_sdk_config.environment;

    safe_strcpy(snapshot.api_key, sizeof(snapshot.api_key), g_sdk_config.api_key);
    snapshot.config.api_key = snapshot.api_key;

    safe_strcpy(snapshot.base_url, sizeof(snapshot.base_url), g_sdk_config.base_url);
    snapshot.config.base_url = snapshot.base_url;

    safe_strcpy(snapshot.device_id, sizeof(snapshot.device_id), g_sdk_config.device_id);
    snapshot.config.device_id = snapshot.device_id;

    safe_strcpy(snapshot.platform, sizeof(snapshot.platform), g_sdk_config.platform);
    snapshot.config.platform = snapshot.platform;

    safe_strcpy(snapshot.sdk_version, sizeof(snapshot.sdk_version), g_sdk_config.sdk_version);
    snapshot.config.sdk_version = snapshot.sdk_version;

    snapshot_client_info(&snapshot.client_info, &g_client_info);
    snapshot.config.client_info = snapshot.client_info.info;

    return &snapshot.config;
}

void rac_sdk_set_client_info(const rac_client_info_t* client_info) {
    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);
    copy_client_info(client_info);
    if (g_sdk_initialized) {
        g_sdk_config.client_info = g_client_info;
    }
}

const rac_client_info_t* rac_sdk_get_client_info(void) {
    thread_local ClientInfoSnapshotStorage snapshot;

    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);
    snapshot_client_info(&snapshot, &g_client_info);
    return &snapshot.info;
}

rac_environment_t rac_sdk_get_environment(void) {
    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);
    if (!g_sdk_initialized) {
        return RAC_ENV_DEVELOPMENT;
    }
    return g_sdk_config.environment;
}

bool rac_sdk_is_initialized(void) {
    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);
    return g_sdk_initialized;
}

void rac_sdk_reset(void) {
    std::lock_guard<std::mutex> lock(g_sdk_state_mutex);
    g_sdk_initialized = false;
    memset(&g_sdk_config, 0, sizeof(g_sdk_config));
    memset(g_api_key, 0, sizeof(g_api_key));
    memset(g_base_url, 0, sizeof(g_base_url));
    memset(g_device_id, 0, sizeof(g_device_id));
    memset(g_platform, 0, sizeof(g_platform));
    memset(g_sdk_version, 0, sizeof(g_sdk_version));
    memset(g_sdk_binding, 0, sizeof(g_sdk_binding));
    memset(g_app_identifier, 0, sizeof(g_app_identifier));
    memset(g_app_name, 0, sizeof(g_app_name));
    memset(g_app_version, 0, sizeof(g_app_version));
    memset(g_app_build, 0, sizeof(g_app_build));
    memset(g_locale, 0, sizeof(g_locale));
    memset(g_timezone, 0, sizeof(g_timezone));
    memset(&g_client_info, 0, sizeof(g_client_info));
}
