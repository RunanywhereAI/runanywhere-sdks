/**
 * @file rac_stt_whispercpp.cpp
 * @brief RunAnywhere Commons - WhisperCPP STT Implementation
 *
 * Wraps runanywhere-core's WhisperCPP STT backend.
 */

#include "rac_stt_whispercpp.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

// Forward declarations for runanywhere-core C API
extern "C" {

typedef void* ra_whisper_handle;

typedef struct ra_whisper_config {
    int num_threads;
    int use_gpu;
    const char* language;
    int translate;
} ra_whisper_config_t;

int ra_whisper_create(const char* model_path, const ra_whisper_config_t* config,
                      ra_whisper_handle* out_handle);
void ra_whisper_destroy(ra_whisper_handle handle);
int ra_whisper_transcribe(ra_whisper_handle handle, const float* samples, size_t num_samples,
                          char** out_text);
int ra_whisper_is_ready(ra_whisper_handle handle);
char* ra_whisper_get_language(ra_whisper_handle handle);
void ra_whisper_free_string(char* str);

}  // extern "C"

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

namespace {

ra_whisper_config_t to_core_config(const rac_stt_whispercpp_config_t* rac_config) {
    ra_whisper_config_t config = {};
    config.num_threads = 0;
    config.use_gpu = 1;
    config.language = nullptr;
    config.translate = 0;

    if (rac_config != nullptr) {
        config.num_threads = rac_config->num_threads;
        config.use_gpu = rac_config->use_gpu ? 1 : 0;
        config.language = rac_config->language;
        config.translate = rac_config->translate ? 1 : 0;
    }

    return config;
}

rac_result_t from_core_result(int code) {
    if (code >= 0) {
        return RAC_SUCCESS;
    }

    switch (code) {
        case -1:
            return RAC_ERROR_BACKEND_INIT_FAILED;
        case -2:
            return RAC_ERROR_MODEL_LOAD_FAILED;
        case -3:
            return RAC_ERROR_INFERENCE_FAILED;
        case -4:
            return RAC_ERROR_INVALID_HANDLE;
        case -5:
            return RAC_ERROR_CANCELLED;
        default:
            return RAC_ERROR_INTERNAL;
    }
}

}  // namespace

// =============================================================================
// WHISPERCPP STT API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_stt_whispercpp_create(const char* model_path,
                                       const rac_stt_whispercpp_config_t* config,
                                       rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    ra_whisper_config_t core_config = to_core_config(config);
    ra_whisper_handle core_handle = nullptr;

    int result = ra_whisper_create(model_path, &core_config, &core_handle);
    if (result != 0) {
        rac_error_set_details("Failed to create WhisperCPP backend");
        return from_core_result(result);
    }

    *out_handle = static_cast<rac_handle_t>(core_handle);

    rac_event_track("stt.backend.created", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"whispercpp"})");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_whispercpp_transcribe(rac_handle_t handle, const float* audio_samples,
                                           size_t num_samples, const rac_stt_options_t* options,
                                           rac_stt_result_t* out_result) {
    if (handle == nullptr || audio_samples == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    (void)options;  // Options passed via config at creation time

    auto core_handle = static_cast<ra_whisper_handle>(handle);
    char* text = nullptr;

    int result = ra_whisper_transcribe(core_handle, audio_samples, num_samples, &text);
    if (result != 0) {
        rac_error_set_details("WhisperCPP transcription failed");
        return from_core_result(result);
    }

    // Fill result
    out_result->text = text;  // Caller must free with rac_free
    out_result->detected_language = nullptr;
    out_result->words = nullptr;
    out_result->num_words = 0;
    out_result->confidence = 1.0f;
    out_result->processing_time_ms = 0;

    rac_event_track("stt.transcription.completed", RAC_EVENT_CATEGORY_STT,
                    RAC_EVENT_DESTINATION_ALL, R"({"backend":"whispercpp"})");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_whispercpp_get_language(rac_handle_t handle, char** out_language) {
    if (handle == nullptr || out_language == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto core_handle = static_cast<ra_whisper_handle>(handle);
    char* language = ra_whisper_get_language(core_handle);

    if (language == nullptr) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    *out_language = language;
    return RAC_SUCCESS;
}

rac_bool_t rac_stt_whispercpp_is_ready(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto core_handle = static_cast<ra_whisper_handle>(handle);
    return (ra_whisper_is_ready(core_handle) != 0) ? RAC_TRUE : RAC_FALSE;
}

void rac_stt_whispercpp_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto core_handle = static_cast<ra_whisper_handle>(handle);
    ra_whisper_destroy(core_handle);

    rac_event_track("stt.backend.destroyed", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"whispercpp"})");
}

}  // extern "C"
