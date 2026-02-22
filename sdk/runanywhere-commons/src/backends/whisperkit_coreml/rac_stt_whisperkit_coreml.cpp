/**
 * @file rac_stt_whisperkit_coreml.cpp
 * @brief RunAnywhere Commons - WhisperKit CoreML STT Callback Storage
 *
 * Stores and exposes the Swift callbacks that the WhisperKit CoreML backend's
 * vtable delegates to. Thread-safe via mutex.
 */

#include "rac/backends/rac_stt_whisperkit_coreml.h"

#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "WhisperKitCoreML";

// =============================================================================
// CALLBACK STORAGE
// =============================================================================

namespace {

std::mutex g_callbacks_mutex;
rac_whisperkit_coreml_stt_callbacks_t g_callbacks = {};
bool g_callbacks_set = false;

}  // namespace

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

extern "C" {

rac_result_t
rac_whisperkit_coreml_stt_set_callbacks(const rac_whisperkit_coreml_stt_callbacks_t* callbacks) {
    if (callbacks == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    g_callbacks = *callbacks;
    g_callbacks_set = true;

    RAC_LOG_INFO(LOG_CAT, "Swift callbacks registered for WhisperKit CoreML STT");
    return RAC_SUCCESS;
}

const rac_whisperkit_coreml_stt_callbacks_t* rac_whisperkit_coreml_stt_get_callbacks(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set) {
        return nullptr;
    }
    return &g_callbacks;
}

rac_bool_t rac_whisperkit_coreml_stt_is_available(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    return g_callbacks_set && g_callbacks.can_handle != nullptr && g_callbacks.create != nullptr
               ? RAC_TRUE
               : RAC_FALSE;
}

}  // extern "C"
