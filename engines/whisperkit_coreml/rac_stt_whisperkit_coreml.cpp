/**
 * @file rac_stt_whisperkit_coreml.cpp
 * @brief RunAnywhere Commons - WhisperKit CoreML STT Callback Storage
 *
 * Stores and exposes the Swift callbacks that the WhisperKit CoreML backend's
 * vtable delegates to. Thread-safe via mutex.
 */

#include "rac/backends/rac_stt_whisperkit_coreml.h"
#include "whisperkit_callbacks_internal.h"

#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char *LOG_CAT = "WhisperKitCoreML";

// =============================================================================
// CALLBACK STORAGE
// =============================================================================

namespace {

std::mutex g_callbacks_mutex;
rac_whisperkit_coreml_stt_callbacks_t g_callbacks = {};
bool g_callbacks_set = false;

// Cached destroy + user_data captured at first set_callbacks(). Preserved
// even if set_callbacks is later invoked with a zeroed struct so that
// destroy paths can still tear down a Swift backend impl that outlived the
// active callback registration (engines-other-006).
rac_whisperkit_coreml_stt_destroy_fn g_destroy_cached = nullptr;
void *g_destroy_user_data_cached = nullptr;

} // namespace

namespace runanywhere::engines::whisperkit_coreml {

// engines-other-007: take a value snapshot under the registration lock so
// engine-internal callers don't dereference the global struct after another
// thread may have written it. Returns true iff a valid snapshot was produced.
bool snapshot_callbacks(rac_whisperkit_coreml_stt_callbacks_t *out) {
  if (!out) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  if (!g_callbacks_set) {
    return false;
  }
  *out = g_callbacks;
  return true;
}

bool snapshot_cached_destroy(rac_whisperkit_coreml_stt_destroy_fn *out_fn,
                             void **out_user_data) {
  if (!out_fn || !out_user_data) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  if (g_destroy_cached == nullptr) {
    return false;
  }
  *out_fn = g_destroy_cached;
  *out_user_data = g_destroy_user_data_cached;
  return true;
}

} // namespace runanywhere::engines::whisperkit_coreml

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

extern "C" {

rac_result_t rac_whisperkit_coreml_stt_set_callbacks(
    const rac_whisperkit_coreml_stt_callbacks_t *callbacks) {
  if (callbacks == nullptr) {
    return RAC_ERROR_INVALID_PARAMETER;
  }

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  g_callbacks = *callbacks;
  g_callbacks_set = true;
  if (callbacks->destroy != nullptr) {
    g_destroy_cached = callbacks->destroy;
    g_destroy_user_data_cached = callbacks->user_data;
  }

  RAC_LOG_INFO(LOG_CAT, "Swift callbacks registered for WhisperKit CoreML STT");
  return RAC_SUCCESS;
}

const rac_whisperkit_coreml_stt_callbacks_t *
rac_whisperkit_coreml_stt_get_callbacks(void) {
  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  if (!g_callbacks_set) {
    return nullptr;
  }
  return &g_callbacks;
}

rac_bool_t rac_whisperkit_coreml_stt_is_available(void) {
  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  return g_callbacks_set && g_callbacks.can_handle != nullptr &&
                 g_callbacks.create != nullptr &&
                 g_callbacks.transcribe != nullptr
             ? RAC_TRUE
             : RAC_FALSE;
}

} // extern "C"
