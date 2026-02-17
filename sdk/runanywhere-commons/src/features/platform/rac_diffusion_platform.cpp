/**
 * @file rac_diffusion_platform.cpp
 * @brief RunAnywhere Commons - Platform Diffusion Implementation
 *
 * C++ implementation of platform diffusion API. This is a thin wrapper that
 * delegates all operations to Swift via registered callbacks.
 */

#include "rac/features/platform/rac_diffusion_platform.h"

#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Platform.Diffusion";

// =============================================================================
// CALLBACK STORAGE
// =============================================================================

namespace {

std::mutex g_callbacks_mutex;
rac_platform_diffusion_callbacks_t g_callbacks = {};
bool g_callbacks_set = false;

}  // namespace

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

extern "C" {

rac_result_t rac_platform_diffusion_set_callbacks(
    const rac_platform_diffusion_callbacks_t* callbacks) {
    if (callbacks == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    g_callbacks = *callbacks;
    g_callbacks_set = true;

    RAC_LOG_INFO(LOG_CAT, "Swift callbacks registered for platform diffusion");
    return RAC_SUCCESS;
}

const rac_platform_diffusion_callbacks_t* rac_platform_diffusion_get_callbacks(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set) {
        return nullptr;
    }
    return &g_callbacks;
}

rac_bool_t rac_platform_diffusion_is_available(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    return g_callbacks_set && g_callbacks.can_handle != nullptr && g_callbacks.create != nullptr
               ? RAC_TRUE
               : RAC_FALSE;
}

// =============================================================================
// SERVICE API
// =============================================================================

rac_result_t rac_diffusion_platform_create(const char* model_path,
                                           const rac_diffusion_platform_config_t* config,
                                           rac_diffusion_platform_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    *out_handle = nullptr;

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.create == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Swift callbacks not registered");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Creating platform diffusion via Swift");

    rac_handle_t handle = g_callbacks.create(model_path, config, g_callbacks.user_data);
    if (handle == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Swift create callback returned null");
        return RAC_ERROR_INTERNAL;
    }

    *out_handle = reinterpret_cast<rac_diffusion_platform_handle_t>(handle);
    RAC_LOG_INFO(LOG_CAT, "Platform diffusion service created");
    return RAC_SUCCESS;
}

void rac_diffusion_platform_destroy(rac_diffusion_platform_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.destroy == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "Cannot destroy: Swift callbacks not registered");
        return;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Destroying platform diffusion via Swift");
    g_callbacks.destroy(handle, g_callbacks.user_data);
}

rac_result_t rac_diffusion_platform_generate(rac_diffusion_platform_handle_t handle,
                                             const rac_diffusion_platform_options_t* options,
                                             rac_diffusion_platform_result_t* out_result) {
    if (handle == nullptr || options == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Initialize output
    memset(out_result, 0, sizeof(*out_result));

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.generate == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Swift callbacks not registered");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Generating image via platform diffusion");
    return g_callbacks.generate(handle, options, out_result, g_callbacks.user_data);
}

rac_result_t rac_diffusion_platform_generate_with_progress(
    rac_diffusion_platform_handle_t handle, const rac_diffusion_platform_options_t* options,
    rac_platform_diffusion_progress_fn progress_callback, void* progress_user_data,
    rac_diffusion_platform_result_t* out_result) {
    if (handle == nullptr || options == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Initialize output
    memset(out_result, 0, sizeof(*out_result));

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set) {
        RAC_LOG_ERROR(LOG_CAT, "Swift callbacks not registered");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Use progress version if available, otherwise fall back to regular generate
    if (g_callbacks.generate_with_progress != nullptr) {
        RAC_LOG_DEBUG(LOG_CAT, "Generating image with progress via platform diffusion");
        return g_callbacks.generate_with_progress(handle, options, progress_callback,
                                                  progress_user_data, out_result,
                                                  g_callbacks.user_data);
    } else if (g_callbacks.generate != nullptr) {
        RAC_LOG_DEBUG(LOG_CAT, "Generating image via platform diffusion (no progress)");
        return g_callbacks.generate(handle, options, out_result, g_callbacks.user_data);
    }

    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t rac_diffusion_platform_cancel(rac_diffusion_platform_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set || g_callbacks.cancel == nullptr) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    RAC_LOG_DEBUG(LOG_CAT, "Cancelling platform diffusion generation");
    return g_callbacks.cancel(handle, g_callbacks.user_data);
}

void rac_diffusion_platform_result_free(rac_diffusion_platform_result_t* result) {
    if (result == nullptr) {
        return;
    }

    if (result->image_data != nullptr) {
        free(result->image_data);
        result->image_data = nullptr;
    }
    result->image_size = 0;
}

}  // extern "C"
