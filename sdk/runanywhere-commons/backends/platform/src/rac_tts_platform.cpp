/**
 * @file rac_tts_platform.cpp
 * @brief RunAnywhere Commons - Platform TTS Implementation
 *
 * C++ implementation of platform TTS API. This is a thin wrapper that
 * delegates all operations to Swift via registered callbacks.
 */

#include "rac_tts_platform.h"

#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Platform.TTS";

// =============================================================================
// CALLBACK STORAGE
// =============================================================================

namespace {

std::mutex g_callbacks_mutex;
rac_platform_tts_callbacks_t g_callbacks = {};
bool g_callbacks_set = false;

}  // namespace

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

extern "C" {

rac_result_t rac_platform_tts_set_callbacks(const rac_platform_tts_callbacks_t* callbacks) {
    if (callbacks == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    g_callbacks = *callbacks;
    g_callbacks_set = true;

    RAC_LOG_INFO(LOG_CAT, "Swift callbacks registered for platform TTS");
    return RAC_SUCCESS;
}

const rac_platform_tts_callbacks_t* rac_platform_tts_get_callbacks(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set) {
        return nullptr;
    }
    return &g_callbacks;
}

rac_bool_t rac_platform_tts_is_available(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    return g_callbacks_set && g_callbacks.can_handle != nullptr && g_callbacks.create != nullptr
               ? RAC_TRUE
               : RAC_FALSE;
}

// =============================================================================
// SERVICE API
// =============================================================================

rac_result_t rac_tts_platform_create(const rac_tts_platform_config_t* config,
                                     rac_tts_platform_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    *out_handle = nullptr;

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.create == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Swift callbacks not registered");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Creating platform TTS via Swift");

    rac_handle_t handle = g_callbacks.create(config, g_callbacks.user_data);
    if (handle == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Swift create callback returned null");
        return RAC_ERROR_INTERNAL;
    }

    *out_handle = reinterpret_cast<rac_tts_platform_handle_t>(handle);
    RAC_LOG_INFO(LOG_CAT, "Platform TTS service created");
    return RAC_SUCCESS;
}

void rac_tts_platform_destroy(rac_tts_platform_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.destroy == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "Cannot destroy: Swift callbacks not registered");
        return;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Destroying platform TTS via Swift");
    g_callbacks.destroy(handle, g_callbacks.user_data);
}

rac_result_t rac_tts_platform_synthesize(rac_tts_platform_handle_t handle, const char* text,
                                         const rac_tts_platform_options_t* options) {
    if (handle == nullptr || text == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.synthesize == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Swift callbacks not registered");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Synthesizing via platform TTS");
    return g_callbacks.synthesize(handle, text, options, g_callbacks.user_data);
}

void rac_tts_platform_stop(rac_tts_platform_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.stop == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "Cannot stop: Swift callbacks not registered");
        return;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Stopping platform TTS via Swift");
    g_callbacks.stop(handle, g_callbacks.user_data);
}

}  // extern "C"
