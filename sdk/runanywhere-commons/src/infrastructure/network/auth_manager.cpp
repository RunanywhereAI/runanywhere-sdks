/**
 * @file auth_manager.cpp
 * @brief Authentication state management implementation
 */

#include <cstdlib>
#include <cstring>
#include <ctime>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_api_types.h"
#include "rac/infrastructure/network/rac_auth_manager.h"

// =============================================================================
// Global State
// =============================================================================

static rac_auth_state_t g_auth_state = {};
static rac_secure_storage_t g_storage = {};
static bool g_storage_available = false;

// =============================================================================
// Helpers
// =============================================================================

static char* str_dup(const char* src) {
    if (!src)
        return nullptr;
    size_t len = strlen(src);
    char* dst = (char*)malloc(len + 1);
    if (dst) {
        memcpy(dst, src, len + 1);
    }
    return dst;
}

static void free_auth_state_strings() {
    free(g_auth_state.access_token);
    free(g_auth_state.refresh_token);
    free(g_auth_state.device_id);
    free(g_auth_state.user_id);
    free(g_auth_state.organization_id);

    g_auth_state.access_token = nullptr;
    g_auth_state.refresh_token = nullptr;
    g_auth_state.device_id = nullptr;
    g_auth_state.user_id = nullptr;
    g_auth_state.organization_id = nullptr;
}

static int64_t current_time_seconds() {
    return (int64_t)time(nullptr);
}

// =============================================================================
// Initialization
// =============================================================================

void rac_auth_init(const rac_secure_storage_t* storage) {
    rac_auth_reset();

    if (storage && storage->store && storage->retrieve && storage->delete_key) {
        g_storage = *storage;
        g_storage_available = true;
    } else {
        memset(&g_storage, 0, sizeof(g_storage));
        g_storage_available = false;
    }
}

void rac_auth_reset(void) {
    free_auth_state_strings();
    memset(&g_auth_state, 0, sizeof(g_auth_state));
}

// =============================================================================
// Token State
// =============================================================================

bool rac_auth_is_authenticated(void) {
    return g_auth_state.is_authenticated && g_auth_state.access_token != nullptr &&
           g_auth_state.access_token[0] != '\0';
}

bool rac_auth_needs_refresh(void) {
    if (!g_auth_state.refresh_token || g_auth_state.refresh_token[0] == '\0') {
        return false;  // Can't refresh without refresh token
    }

    if (g_auth_state.token_expires_at <= 0) {
        return true;  // Unknown expiry, assume needs refresh
    }

    // Check if token expires within 60 seconds
    int64_t now = current_time_seconds();
    return (g_auth_state.token_expires_at - now) < 60;
}

const char* rac_auth_get_access_token(void) {
    if (!rac_auth_is_authenticated()) {
        return nullptr;
    }
    return g_auth_state.access_token;
}

const char* rac_auth_get_device_id(void) {
    return g_auth_state.device_id;
}

const char* rac_auth_get_user_id(void) {
    return g_auth_state.user_id;
}

const char* rac_auth_get_organization_id(void) {
    return g_auth_state.organization_id;
}

// =============================================================================
// Request Building
// =============================================================================

char* rac_auth_build_authenticate_request(const rac_sdk_config_t* config) {
    if (!config)
        return nullptr;

    rac_auth_request_t request = {};
    request.api_key = config->api_key;
    request.device_id = config->device_id;
    request.platform = config->platform;
    request.sdk_version = config->sdk_version;

    return rac_auth_request_to_json(&request);
}

char* rac_auth_build_refresh_request(void) {
    if (!g_auth_state.refresh_token || !g_auth_state.device_id) {
        return nullptr;
    }

    rac_refresh_request_t request = {};
    request.device_id = g_auth_state.device_id;
    request.refresh_token = g_auth_state.refresh_token;

    return rac_refresh_request_to_json(&request);
}

// =============================================================================
// Response Handling
// =============================================================================

static int update_auth_state_from_response(const rac_auth_response_t* response) {
    if (!response || !response->access_token || !response->refresh_token) {
        return -1;
    }

    // Pre-allocate required strings before modifying state
    char* new_access = str_dup(response->access_token);
    char* new_refresh = str_dup(response->refresh_token);
    if (!new_access || !new_refresh) {
        free(new_access);
        free(new_refresh);
        return -1;
    }

    // Free old strings
    free_auth_state_strings();

    // Assign pre-allocated required values
    g_auth_state.access_token = new_access;
    g_auth_state.refresh_token = new_refresh;

    // Copy optional values (NULL is acceptable)
    g_auth_state.device_id = str_dup(response->device_id);
    g_auth_state.user_id = str_dup(response->user_id);
    g_auth_state.organization_id = str_dup(response->organization_id);

    // Calculate expiry timestamp
    g_auth_state.token_expires_at = current_time_seconds() + response->expires_in;
    g_auth_state.is_authenticated = true;

    return 0;
}

int rac_auth_handle_authenticate_response(const char* json) {
    if (!json)
        return -1;

    rac_auth_response_t response = {};
    if (rac_auth_response_from_json(json, &response) != 0) {
        return -1;
    }

    int result = update_auth_state_from_response(&response);

    // Save to secure storage if available and successful
    if (result == 0) {
        rac_auth_save_tokens();
    }

    rac_auth_response_free(&response);
    return result;
}

int rac_auth_handle_refresh_response(const char* json) {
    // Same handling as authenticate - response format is identical
    return rac_auth_handle_authenticate_response(json);
}

// =============================================================================
// Token Management
// =============================================================================

int rac_auth_get_valid_token(const char** out_token, bool* out_needs_refresh) {
    if (!out_token || !out_needs_refresh)
        return -1;

    *out_token = nullptr;
    *out_needs_refresh = false;

    // Not authenticated at all
    if (!rac_auth_is_authenticated()) {
        return -1;
    }

    // Check if refresh is needed
    if (rac_auth_needs_refresh()) {
        *out_needs_refresh = true;
        return 1;  // Caller should refresh
    }

    // Token is valid
    *out_token = g_auth_state.access_token;
    return 0;
}

void rac_auth_clear(void) {
    // Clear in-memory state
    rac_auth_reset();

    // Clear secure storage
    if (g_storage_available) {
        g_storage.delete_key(RAC_KEY_ACCESS_TOKEN, g_storage.context);
        g_storage.delete_key(RAC_KEY_REFRESH_TOKEN, g_storage.context);
        g_storage.delete_key(RAC_KEY_DEVICE_ID, g_storage.context);
        g_storage.delete_key(RAC_KEY_USER_ID, g_storage.context);
        g_storage.delete_key(RAC_KEY_ORGANIZATION_ID, g_storage.context);
    }
}

// =============================================================================
// Persistence
// =============================================================================

int rac_auth_load_stored_tokens(void) {
    if (!g_storage_available) {
        return -1;
    }

    char buffer[2048];

    // Load access token
    if (g_storage.retrieve(RAC_KEY_ACCESS_TOKEN, buffer, sizeof(buffer), g_storage.context) > 0) {
        free(g_auth_state.access_token);
        g_auth_state.access_token = str_dup(buffer);
    } else {
        return -1;  // No stored token
    }

    // Load refresh token
    if (g_storage.retrieve(RAC_KEY_REFRESH_TOKEN, buffer, sizeof(buffer), g_storage.context) > 0) {
        free(g_auth_state.refresh_token);
        g_auth_state.refresh_token = str_dup(buffer);
    }

    // Load device ID
    if (g_storage.retrieve(RAC_KEY_DEVICE_ID, buffer, sizeof(buffer), g_storage.context) > 0) {
        free(g_auth_state.device_id);
        g_auth_state.device_id = str_dup(buffer);
    }

    // Load user ID (optional)
    if (g_storage.retrieve(RAC_KEY_USER_ID, buffer, sizeof(buffer), g_storage.context) > 0) {
        free(g_auth_state.user_id);
        g_auth_state.user_id = str_dup(buffer);
    }

    // Load organization ID
    if (g_storage.retrieve(RAC_KEY_ORGANIZATION_ID, buffer, sizeof(buffer), g_storage.context) >
        0) {
        free(g_auth_state.organization_id);
        g_auth_state.organization_id = str_dup(buffer);
    }

    // Mark as authenticated if we have tokens
    if (g_auth_state.access_token && g_auth_state.access_token[0] != '\0') {
        g_auth_state.is_authenticated = true;
        // Token expiry is unknown when loading, so it will trigger refresh on first use
        g_auth_state.token_expires_at = 0;
    }

    // Clear sensitive data from stack buffer
    memset(buffer, 0, sizeof(buffer));

    return 0;
}

int rac_auth_save_tokens(void) {
    if (!g_storage_available) {
        return 0;  // Not an error, just no-op
    }

    int result = 0;

    if (g_auth_state.access_token) {
        if (g_storage.store(RAC_KEY_ACCESS_TOKEN, g_auth_state.access_token, g_storage.context) !=
            0) {
            result = -1;
        }
    }

    if (g_auth_state.refresh_token) {
        if (g_storage.store(RAC_KEY_REFRESH_TOKEN, g_auth_state.refresh_token, g_storage.context) !=
            0) {
            result = -1;
        }
    }

    if (g_auth_state.device_id) {
        if (g_storage.store(RAC_KEY_DEVICE_ID, g_auth_state.device_id, g_storage.context) != 0) {
            result = -1;
        }
    }

    if (g_auth_state.user_id) {
        if (g_storage.store(RAC_KEY_USER_ID, g_auth_state.user_id, g_storage.context) != 0) {
            result = -1;
        }
    }

    if (g_auth_state.organization_id) {
        if (g_storage.store(RAC_KEY_ORGANIZATION_ID, g_auth_state.organization_id,
                            g_storage.context) != 0) {
            result = -1;
        }
    }

    return result;
}
