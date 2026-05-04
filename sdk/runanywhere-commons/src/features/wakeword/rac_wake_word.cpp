/**
 * @file rac_wake_word.cpp
 * @brief Wake Word C ABI stub implementations (§9).
 *
 * All functions return RAC_ERROR_FEATURE_NOT_AVAILABLE until the wake-word
 * model pipeline is integrated.  This prevents UnsatisfiedLinkError and
 * undefined-symbol crashes on all SDK frontends.
 */

#include "rac/features/wakeword/rac_wake_word.h"

#include "rac/core/rac_logger.h"

extern "C" {

rac_result_t rac_wake_word_init(const char* /*model_path*/) {
    RAC_LOG_WARNING("WakeWord", "rac_wake_word_init: feature not yet available");
    // TODO(wakeword): load model and initialise detector pipeline.
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t rac_wake_word_process(const float* /*samples*/, size_t /*count*/,
                                   bool* detected_out) {
    RAC_LOG_WARNING("WakeWord", "rac_wake_word_process: feature not yet available");
    if (detected_out) *detected_out = false;
    // TODO(wakeword): run inference and return detection result.
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

void rac_wake_word_destroy(rac_wake_word_handle_t* /*handle*/) {
    // No-op stub; nothing to free.
    // TODO(wakeword): free detector resources when implemented.
}

}  // extern "C"
