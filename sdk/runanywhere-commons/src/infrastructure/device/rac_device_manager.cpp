/**
 * @file rac_device_manager.cpp
 * @brief Device Registration Manager Implementation
 *
 * All business logic for device registration lives here.
 * Platform-specific operations are delegated to callbacks.
 */

#include "rac/infrastructure/device/rac_device_manager.h"

#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

// =============================================================================
// INTERNAL STATE
// =============================================================================

namespace {

// Thread-safe callback storage
struct DeviceManagerState {
    rac_device_callbacks_t callbacks = {};
    bool callbacks_set = false;
    std::mutex mutex;
};

DeviceManagerState& get_state() {
    static DeviceManagerState state;
    return state;
}

// Forward declaration for logging
void log_info(const char* message);
void log_error(const char* message);
void log_debug(const char* message);

void log_info(const char* message) {
    rac_log(RAC_LOG_INFO, "DeviceManager", message);
}

void log_error(const char* message) {
    rac_log(RAC_LOG_ERROR, "DeviceManager", message);
}

void log_debug(const char* message) {
    rac_log(RAC_LOG_DEBUG, "DeviceManager", message);
}

// Helper to emit device registered event
void emit_device_registered(const char* device_id) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_DEVICE_REGISTERED;
    event.data.device = RAC_ANALYTICS_DEVICE_DEFAULT;
    event.data.device.device_id = device_id;

    rac_analytics_event_emit(RAC_EVENT_DEVICE_REGISTERED, &event);
}

// Helper to emit device registration failed event
void emit_device_registration_failed(rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_DEVICE_REGISTRATION_FAILED;
    event.data.device = RAC_ANALYTICS_DEVICE_DEFAULT;
    event.data.device.error_code = error_code;
    event.data.device.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_DEVICE_REGISTRATION_FAILED, &event);
}

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" {

rac_result_t rac_device_manager_set_callbacks(const rac_device_callbacks_t* callbacks) {
    if (!callbacks) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Validate required callbacks
    if (!callbacks->get_device_info || !callbacks->get_device_id || !callbacks->is_registered ||
        !callbacks->set_registered || !callbacks->http_post) {
        log_error("One or more required callbacks are NULL");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    state.callbacks = *callbacks;
    state.callbacks_set = true;

    log_info("Device manager callbacks configured");
    return RAC_SUCCESS;
}

rac_result_t rac_device_manager_register_if_needed(rac_environment_t env, const char* build_token) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        log_error("Device manager callbacks not set");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Step 1: Check if already registered
    if (state.callbacks.is_registered(state.callbacks.user_data) == RAC_TRUE) {
        log_debug("Device already registered, skipping");
        return RAC_SUCCESS;
    }

    log_info("Starting device registration");

    // Step 2: Get device ID
    const char* device_id = state.callbacks.get_device_id(state.callbacks.user_data);
    if (!device_id || strlen(device_id) == 0) {
        log_error("Failed to get device ID");
        emit_device_registration_failed(RAC_ERROR_INVALID_STATE, "Failed to get device ID");
        return RAC_ERROR_INVALID_STATE;
    }

    // Step 3: Get device info
    rac_device_registration_info_t device_info = {};
    state.callbacks.get_device_info(&device_info, state.callbacks.user_data);

    // Ensure device_id is set in info
    device_info.device_id = device_id;

    // Step 4: Build registration request
    rac_device_registration_request_t request = {};
    request.device_info = device_info;

    // Get SDK version from SDK config if available
    const rac_sdk_config_t* sdk_config = rac_sdk_get_config();
    request.sdk_version = sdk_config ? sdk_config->sdk_version : "unknown";
    request.build_token = (env == RAC_ENV_DEVELOPMENT) ? build_token : nullptr;
    request.last_seen_at_ms = rac_get_current_time_ms();

    // Step 5: Serialize to JSON
    char* json_ptr = nullptr;
    size_t json_len = 0;
    rac_result_t result = rac_device_registration_to_json(&request, env, &json_ptr, &json_len);

    if (result != RAC_SUCCESS || !json_ptr) {
        log_error("Failed to build registration JSON");
        emit_device_registration_failed(result, "Failed to build registration JSON");
        return result;
    }

    // Step 6: Get endpoint
    const char* endpoint = rac_endpoint_device_registration(env);
    if (!endpoint) {
        log_error("Failed to get device registration endpoint");
        rac_free(json_ptr);
        emit_device_registration_failed(RAC_ERROR_INVALID_STATE, "Failed to get endpoint");
        return RAC_ERROR_INVALID_STATE;
    }

    // Step 7: Determine if auth is required (staging/production require auth)
    rac_bool_t requires_auth = (env != RAC_ENV_DEVELOPMENT) ? RAC_TRUE : RAC_FALSE;

    // Step 8: Make HTTP request via callback
    rac_device_http_response_t response = {};
    result = state.callbacks.http_post(endpoint, json_ptr, requires_auth, &response,
                                       state.callbacks.user_data);

    // Free JSON after use
    rac_free(json_ptr);

    // Step 9: Handle response
    if (result != RAC_SUCCESS || response.result != RAC_SUCCESS) {
        std::string error_msg = "Device registration failed";
        if (response.error_message) {
            error_msg = error_msg + ": " + response.error_message;
        }
        log_error(error_msg.c_str());
        emit_device_registration_failed(result != RAC_SUCCESS ? result : response.result,
                                        response.error_message ? response.error_message
                                                               : "HTTP request failed");
        return result != RAC_SUCCESS ? result : response.result;
    }

    // Step 10: Mark as registered
    state.callbacks.set_registered(RAC_TRUE, state.callbacks.user_data);

    // Step 11: Emit success event
    emit_device_registered(device_id);

    log_info("Device registration successful");
    return RAC_SUCCESS;
}

rac_bool_t rac_device_manager_is_registered(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        return RAC_FALSE;
    }

    return state.callbacks.is_registered(state.callbacks.user_data);
}

void rac_device_manager_clear_registration(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        return;
    }

    state.callbacks.set_registered(RAC_FALSE, state.callbacks.user_data);
    log_info("Device registration cleared");
}

const char* rac_device_manager_get_device_id(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        return nullptr;
    }

    return state.callbacks.get_device_id(state.callbacks.user_data);
}

}  // extern "C"
