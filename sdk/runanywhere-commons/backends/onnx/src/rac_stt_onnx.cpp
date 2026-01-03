/**
 * @file rac_stt_onnx.cpp
 * @brief RunAnywhere Commons - ONNX STT Implementation
 *
 * Wraps runanywhere-core's ONNX STT backend.
 * Mirrors Swift's ONNXSTTService implementation pattern.
 */

#include "rac_stt_onnx.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/events/rac_events.h"

// Android logging for debugging
#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "RAC_STT_ONNX"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGi(...) do {} while(0)
#define LOGe(...) do {} while(0)
#endif

// Forward declarations for runanywhere-core C API
extern "C" {

typedef void* ra_backend_handle;
typedef void* ra_stream_handle;

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

ra_result_code ra_stt_load_model(ra_backend_handle handle, const char* model_path,
                                 const char* model_type, const char* config_json);
ra_result_code ra_stt_transcribe(ra_backend_handle handle, const float* samples, size_t num_samples,
                                 int sample_rate, const char* language, char** out_result);
int ra_stt_supports_streaming(ra_backend_handle handle);

ra_stream_handle ra_stt_create_stream(ra_backend_handle handle, const char* config_json);
void ra_stt_destroy_stream(ra_backend_handle handle, ra_stream_handle stream);
ra_result_code ra_stt_feed_audio(ra_backend_handle handle, ra_stream_handle stream,
                                 const float* samples, size_t num_samples, int sample_rate);
int ra_stt_is_ready(ra_backend_handle handle, ra_stream_handle stream);
ra_result_code ra_stt_decode(ra_backend_handle handle, ra_stream_handle stream, char** out_result);
void ra_stt_input_finished(ra_backend_handle handle, ra_stream_handle stream);
int ra_stt_is_endpoint(ra_backend_handle handle, ra_stream_handle stream);

void ra_free_string(char* str);

}  // extern "C"

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

namespace {

const char* model_type_to_string(rac_stt_onnx_model_type_t type) {
    switch (type) {
        case RAC_STT_ONNX_MODEL_WHISPER:
            return "whisper";
        case RAC_STT_ONNX_MODEL_ZIPFORMER:
            return "zipformer";
        case RAC_STT_ONNX_MODEL_PARAFORMER:
            return "paraformer";
        default:
            return "auto";
    }
}

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
// ONNX STT API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_stt_onnx_create(const char* model_path, const rac_stt_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    LOGi("rac_stt_onnx_create called with model_path=%s", model_path ? model_path : "(null)");
    RAC_LOG_INFO("STT.ONNX", "rac_stt_onnx_create called with model_path=%s",
                 model_path ? model_path : "(null)");

    if (out_handle == nullptr) {
        LOGe("out_handle is null");
        RAC_LOG_ERROR("STT.ONNX", "out_handle is null");
        return RAC_ERROR_NULL_POINTER;
    }

    // Create ONNX backend
    LOGi("Creating ONNX backend via ra_create_backend(\"onnx\")...");
    RAC_LOG_INFO("STT.ONNX", "Creating ONNX backend via ra_create_backend...");
    ra_backend_handle backend = ra_create_backend("onnx");
    if (backend == nullptr) {
        LOGe("ra_create_backend(\"onnx\") returned nullptr!");
        RAC_LOG_ERROR("STT.ONNX", "ra_create_backend(\"onnx\") returned nullptr!");
        rac_error_set_details("Failed to create ONNX backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }
    LOGi("ONNX backend created: %p", backend);
    RAC_LOG_INFO("STT.ONNX", "ONNX backend created: %p", backend);

    // Initialize backend
    LOGi("Initializing ONNX backend...");
    RAC_LOG_INFO("STT.ONNX", "Initializing ONNX backend...");
    ra_result_code result = ra_initialize(backend, nullptr);
    if (result != RA_SUCCESS) {
        LOGe("ra_initialize failed with result=%d", result);
        RAC_LOG_ERROR("STT.ONNX", "ra_initialize failed with result=%d", result);
        ra_destroy(backend);
        return from_core_result(result);
    }
    LOGi("ONNX backend initialized successfully");
    RAC_LOG_INFO("STT.ONNX", "ONNX backend initialized successfully");

    // Load model if path provided
    if (model_path != nullptr) {
        const char* model_type = "auto";
        if (config != nullptr) {
            model_type = model_type_to_string(config->model_type);
        }

        LOGi("Loading model: %s (type=%s)", model_path, model_type);
        RAC_LOG_INFO("STT.ONNX", "Loading model: %s (type=%s)", model_path, model_type);
        result = ra_stt_load_model(backend, model_path, model_type, nullptr);
        if (result != RA_SUCCESS) {
            LOGe("ra_stt_load_model failed with result=%d", result);
            RAC_LOG_ERROR("STT.ONNX", "ra_stt_load_model failed with result=%d", result);
            ra_destroy(backend);
            rac_error_set_details("Failed to load STT model");
            return from_core_result(result);
        }
        LOGi("Model loaded successfully");
        RAC_LOG_INFO("STT.ONNX", "Model loaded successfully");
    }

    *out_handle = static_cast<rac_handle_t>(backend);

    rac_event_track("stt.backend.created", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");

    LOGi("rac_stt_onnx_create completed successfully");
    RAC_LOG_INFO("STT.ONNX", "rac_stt_onnx_create completed successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples,
                                     size_t num_samples, const rac_stt_options_t* options,
                                     rac_stt_result_t* out_result) {
    if (handle == nullptr || audio_samples == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);

    const char* language = "en";
    int32_t sample_rate = 16000;
    if (options != nullptr) {
        if (options->language != nullptr) {
            language = options->language;
        }
        sample_rate = options->sample_rate;
    }

    char* result_json = nullptr;
    ra_result_code result =
        ra_stt_transcribe(backend, audio_samples, num_samples, sample_rate, language, &result_json);

    if (result != RA_SUCCESS) {
        rac_error_set_details("STT transcription failed");
        return from_core_result(result);
    }

    // Parse JSON result - for now just extract text
    // The result JSON format is: {"text": "...", "confidence": 0.95}
    out_result->text = result_json;  // Caller must free
    out_result->detected_language = nullptr;
    out_result->words = nullptr;
    out_result->num_words = 0;
    out_result->confidence = 1.0f;
    out_result->processing_time_ms = 0;

    rac_event_track("stt.transcription.completed", RAC_EVENT_CATEGORY_STT,
                    RAC_EVENT_DESTINATION_ALL, nullptr);

    return RAC_SUCCESS;
}

rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }
    auto backend = static_cast<ra_backend_handle>(handle);
    return (ra_stt_supports_streaming(backend) != 0) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream) {
    if (handle == nullptr || out_stream == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    ra_stream_handle stream = ra_stt_create_stream(backend, nullptr);

    if (stream == nullptr) {
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    *out_stream = static_cast<rac_handle_t>(stream);
    return RAC_SUCCESS;
}

rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                     const float* audio_samples, size_t num_samples) {
    if (handle == nullptr || stream == nullptr || audio_samples == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    auto stream_handle = static_cast<ra_stream_handle>(stream);

    ra_result_code result =
        ra_stt_feed_audio(backend, stream_handle, audio_samples, num_samples, 16000);
    return from_core_result(result);
}

rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return RAC_FALSE;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    auto stream_handle = static_cast<ra_stream_handle>(stream);

    return (ra_stt_is_ready(backend, stream_handle) != 0) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream, char** out_text) {
    if (handle == nullptr || stream == nullptr || out_text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    auto stream_handle = static_cast<ra_stream_handle>(stream);

    ra_result_code result = ra_stt_decode(backend, stream_handle, out_text);
    return from_core_result(result);
}

void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    auto stream_handle = static_cast<ra_stream_handle>(stream);

    ra_stt_input_finished(backend, stream_handle);
}

rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return RAC_FALSE;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    auto stream_handle = static_cast<ra_stream_handle>(stream);

    return (ra_stt_is_endpoint(backend, stream_handle) != 0) ? RAC_TRUE : RAC_FALSE;
}

void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    auto stream_handle = static_cast<ra_stream_handle>(stream);

    ra_stt_destroy_stream(backend, stream_handle);
}

void rac_stt_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto backend = static_cast<ra_backend_handle>(handle);
    ra_destroy(backend);

    rac_event_track("stt.backend.destroyed", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");
}

}  // extern "C"
