/**
 * @file rac_tts_onnx.cpp
 * @brief RunAnywhere Commons - ONNX TTS Implementation
 *
 * Wraps runanywhere-core's ONNX TTS backend.
 * Mirrors Swift's ONNXTTSService implementation pattern.
 */

#include "rac_tts_onnx.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

// Forward declarations for runanywhere-core C API
extern "C" {

typedef void* ra_backend_handle;

typedef enum ra_result_code {
    RA_SUCCESS = 0,
    RA_ERROR_INIT_FAILED = -1,
    RA_ERROR_MODEL_LOAD_FAILED = -2,
    RA_ERROR_INFERENCE_FAILED = -3,
    RA_ERROR_INVALID_HANDLE = -4,
    RA_ERROR_CANCELLED = -5
} ra_result_code;

ra_backend_handle ra_create_backend(const char* backend_type);
ra_result_code ra_initialize(ra_backend_handle handle, const char* config_json);
void ra_destroy(ra_backend_handle handle);

ra_result_code ra_tts_load_model(ra_backend_handle handle, const char* model_path,
                                 const char* config_json);
ra_result_code ra_tts_synthesize(ra_backend_handle handle, const char* text, const char* voice,
                                 float** out_audio, size_t* out_num_samples, int* out_sample_rate);
void ra_tts_stop(ra_backend_handle handle);
void ra_free_audio(float* audio);

}  // extern "C"

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

namespace {

rac_result_t from_core_result(ra_result_code code) {
    switch (code) {
        case RA_SUCCESS:
            return RAC_SUCCESS;
        case RA_ERROR_INIT_FAILED:
            return RAC_ERROR_BACKEND_INIT_FAILED;
        case RA_ERROR_MODEL_LOAD_FAILED:
            return RAC_ERROR_MODEL_LOAD_FAILED;
        case RA_ERROR_INFERENCE_FAILED:
            return RAC_ERROR_INFERENCE_FAILED;
        case RA_ERROR_INVALID_HANDLE:
            return RAC_ERROR_INVALID_HANDLE;
        case RA_ERROR_CANCELLED:
            return RAC_ERROR_CANCELLED;
        default:
            return RAC_ERROR_INTERNAL;
    }
}

}  // namespace

// =============================================================================
// ONNX TTS API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_tts_onnx_create(const char* model_path, const rac_tts_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    (void)config;  // Config passed via JSON in real impl

    // Create ONNX backend
    ra_backend_handle backend = ra_create_backend("onnx");
    if (backend == nullptr) {
        rac_error_set_details("Failed to create ONNX TTS backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Initialize backend
    ra_result_code result = ra_initialize(backend, nullptr);
    if (result != RA_SUCCESS) {
        ra_destroy(backend);
        return from_core_result(result);
    }

    // Load TTS model if path provided
    if (model_path != nullptr) {
        result = ra_tts_load_model(backend, model_path, nullptr);
        if (result != RA_SUCCESS) {
            ra_destroy(backend);
            rac_error_set_details("Failed to load TTS model");
            return from_core_result(result);
        }
    }

    *out_handle = static_cast<rac_handle_t>(backend);

    rac_event_track("tts.backend.created", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");

    return RAC_SUCCESS;
}

rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text,
                                     const rac_tts_options_t* options,
                                     rac_tts_result_t* out_result) {
    if (handle == nullptr || text == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);

    const char* voice = nullptr;
    if (options != nullptr && options->voice != nullptr) {
        voice = options->voice;
    }

    float* audio_data = nullptr;
    size_t num_samples = 0;
    int sample_rate = 22050;

    ra_result_code result =
        ra_tts_synthesize(backend, text, voice, &audio_data, &num_samples, &sample_rate);

    if (result != RA_SUCCESS) {
        rac_error_set_details("TTS synthesis failed");
        return from_core_result(result);
    }

    // Fill result
    out_result->audio_data = audio_data;  // Caller must free with rac_free
    out_result->audio_size = num_samples * sizeof(float);
    out_result->audio_format = RAC_AUDIO_FORMAT_PCM;
    out_result->sample_rate = sample_rate;
    out_result->duration_ms = (num_samples * 1000) / sample_rate;
    out_result->processing_time_ms = 0;

    rac_event_track("tts.synthesis.completed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    nullptr);

    return RAC_SUCCESS;
}

rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count) {
    if (handle == nullptr || out_voices == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // TODO: Implement when core provides voice listing
    *out_voices = nullptr;
    *out_count = 0;
    return RAC_SUCCESS;
}

void rac_tts_onnx_stop(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    ra_tts_stop(backend);
}

void rac_tts_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    ra_destroy(backend);

    rac_event_track("tts.backend.destroyed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");
}

}  // extern "C"
