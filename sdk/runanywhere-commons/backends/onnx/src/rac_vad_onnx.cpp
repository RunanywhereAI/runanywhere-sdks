/**
 * @file rac_vad_onnx.cpp
 * @brief RunAnywhere Commons - ONNX VAD Implementation
 *
 * Wraps runanywhere-core's ONNX VAD backend.
 * Mirrors Swift's VADService implementation pattern.
 */

#include "rac_vad_onnx.h"

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

ra_result_code ra_vad_load_model(ra_backend_handle handle, const char* model_path,
                                 const char* config_json);
ra_result_code ra_vad_process(ra_backend_handle handle, const float* samples, size_t num_samples,
                              int* out_is_speech);
ra_result_code ra_vad_start(ra_backend_handle handle);
ra_result_code ra_vad_stop(ra_backend_handle handle);
ra_result_code ra_vad_reset(ra_backend_handle handle);
ra_result_code ra_vad_set_threshold(ra_backend_handle handle, float threshold);
int ra_vad_is_speech_active(ra_backend_handle handle);

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
// ONNX VAD API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_vad_onnx_create(const char* model_path, const rac_vad_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    (void)config;  // Config passed via JSON in real impl

    // Create ONNX backend
    ra_backend_handle backend = ra_create_backend("onnx");
    if (backend == nullptr) {
        rac_error_set_details("Failed to create ONNX VAD backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Initialize backend
    ra_result_code result = ra_initialize(backend, nullptr);
    if (result != RA_SUCCESS) {
        ra_destroy(backend);
        return from_core_result(result);
    }

    // Load VAD model if path provided
    if (model_path != nullptr) {
        result = ra_vad_load_model(backend, model_path, nullptr);
        if (result != RA_SUCCESS) {
            ra_destroy(backend);
            rac_error_set_details("Failed to load VAD model");
            return from_core_result(result);
        }
    }

    // Apply config if provided
    if (config != nullptr && config->energy_threshold > 0) {
        ra_vad_set_threshold(backend, config->energy_threshold);
    }

    *out_handle = static_cast<rac_handle_t>(backend);

    rac_event_track("vad.backend.created", RAC_EVENT_CATEGORY_VOICE, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");

    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples, size_t num_samples,
                                  rac_bool_t* out_is_speech) {
    if (handle == nullptr || samples == nullptr || out_is_speech == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);

    int is_speech = 0;
    ra_result_code result = ra_vad_process(backend, samples, num_samples, &is_speech);

    if (result != RA_SUCCESS) {
        return from_core_result(result);
    }

    *out_is_speech = (is_speech != 0) ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_start(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    return from_core_result(ra_vad_start(backend));
}

rac_result_t rac_vad_onnx_stop(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    return from_core_result(ra_vad_stop(backend));
}

rac_result_t rac_vad_onnx_reset(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    return from_core_result(ra_vad_reset(backend));
}

rac_result_t rac_vad_onnx_set_threshold(rac_handle_t handle, float threshold) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    return from_core_result(ra_vad_set_threshold(backend, threshold));
}

rac_bool_t rac_vad_onnx_is_speech_active(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    return (ra_vad_is_speech_active(backend) != 0) ? RAC_TRUE : RAC_FALSE;
}

void rac_vad_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    ra_destroy(backend);

    rac_event_track("vad.backend.destroyed", RAC_EVENT_CATEGORY_VOICE, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");
}

}  // extern "C"
