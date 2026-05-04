/**
 * @file rac_stt_sherpa.cpp
 * @brief Sherpa-ONNX RAC API implementation.
 */

#include "sherpa_backend.h"
#include "rac_stt_sherpa.h"
#include "rac_tts_sherpa.h"
#include "rac_vad_sherpa.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <set>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

namespace {
// Build a minimal JSON array of string codes. Returns a malloc'd NUL-terminated
// buffer; caller must free() it. We skip escaping because language codes are
// ASCII alphabet / digits / hyphen.
char* build_json_string_array(const std::vector<std::string>& items) {
    std::string json;
    json.reserve(items.size() * 8 + 2);
    json.push_back('[');
    for (size_t i = 0; i < items.size(); ++i) {
        if (i > 0)
            json.push_back(',');
        json.push_back('"');
        json.append(items[i]);
        json.push_back('"');
    }
    json.push_back(']');
    return strdup(json.c_str());
}
}  // namespace

struct rac_sherpa_stt_handle_impl {
    std::unique_ptr<runanywhere::SherpaBackend> backend;
    runanywhere::SherpaSTT* stt;  // Owned by backend
};

// =============================================================================
// STT IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_stt_sherpa_create(const char* model_path, const rac_stt_sherpa_config_t* config,
                                 rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_sherpa_stt_handle_impl();
    if (!handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create and initialize backend
    handle->backend = std::make_unique<runanywhere::SherpaBackend>();
    nlohmann::json init_config;
    if (config != nullptr && config->num_threads > 0) {
        init_config["num_threads"] = config->num_threads;
    }

    if (!handle->backend->initialize(init_config)) {
        delete handle;
        rac_error_set_details("Failed to initialize Sherpa backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Get STT component
    handle->stt = handle->backend->get_stt();
    if (!handle->stt) {
        delete handle;
        rac_error_set_details("STT component not available");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Load model if path provided
    if (model_path != nullptr) {
        runanywhere::STTModelType model_type = runanywhere::STTModelType::WHISPER;
        if (config != nullptr) {
            switch (config->model_type) {
                case RAC_STT_ONNX_MODEL_ZIPFORMER:
                    model_type = runanywhere::STTModelType::ZIPFORMER;
                    break;
                case RAC_STT_ONNX_MODEL_PARAFORMER:
                    model_type = runanywhere::STTModelType::PARAFORMER;
                    break;
                case RAC_STT_ONNX_MODEL_NEMO_CTC:
                    model_type = runanywhere::STTModelType::NEMO_CTC;
                    break;
                case RAC_STT_ONNX_MODEL_AUTO:
                    // Auto-detect: let load_model figure it out from directory structure
                    model_type = runanywhere::STTModelType::WHISPER;
                    break;
                default:
                    model_type = runanywhere::STTModelType::WHISPER;
            }
        }

        if (!handle->stt->load_model(model_path, model_type)) {
            delete handle;
            rac_error_set_details("Failed to load STT model");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
    }

    *out_handle = static_cast<rac_handle_t>(handle);

    rac_event_track("stt.backend.created", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"sherpa"})");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_sherpa_transcribe(rac_handle_t handle, const float* audio_samples,
                                     size_t num_samples, const rac_stt_options_t* options,
                                     rac_stt_result_t* out_result) {
    if (handle == nullptr || audio_samples == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    if (!h->stt) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    runanywhere::STTRequest request;
    request.audio_samples.assign(audio_samples, audio_samples + num_samples);
    request.sample_rate = (options && options->sample_rate > 0) ? options->sample_rate : 16000;
    if (options && options->language) {
        request.language = options->language;
    }

    auto result = h->stt->transcribe(request);

    out_result->text = result.text.empty() ? nullptr : strdup(result.text.c_str());
    if (!result.text.empty() && !out_result->text) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->detected_language =
        result.detected_language.empty() ? nullptr : strdup(result.detected_language.c_str());
    if (!result.detected_language.empty() && !out_result->detected_language) {
        free(out_result->text);
        out_result->text = nullptr;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->words = nullptr;
    out_result->num_words = 0;
    out_result->confidence = 1.0f;
    out_result->processing_time_ms = result.inference_time_ms;

    rac_event_track("stt.transcription.completed", RAC_EVENT_CATEGORY_STT,
                    RAC_EVENT_DESTINATION_ALL, nullptr);

    return RAC_SUCCESS;
}

rac_bool_t rac_stt_sherpa_supports_streaming(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }
    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    return (h->stt && h->stt->supports_streaming()) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_stt_sherpa_create_stream(rac_handle_t handle, rac_handle_t* out_stream) {
    if (handle == nullptr || out_stream == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    if (!h->stt) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    std::string stream_id = h->stt->create_stream();
    if (stream_id.empty()) {
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    char* stream_copy = strdup(stream_id.c_str());
    if (!stream_copy) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_stream = static_cast<rac_handle_t>(stream_copy);
    return RAC_SUCCESS;
}

rac_result_t rac_stt_sherpa_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                     const float* audio_samples, size_t num_samples) {
    if (handle == nullptr || stream == nullptr || audio_samples == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    std::vector<float> samples(audio_samples, audio_samples + num_samples);
    bool success = h->stt->feed_audio(stream_id, samples, 16000);

    return success ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
}

rac_bool_t rac_stt_sherpa_stream_is_ready(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    return h->stt->is_stream_ready(stream_id) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_stt_sherpa_decode_stream(rac_handle_t handle, rac_handle_t stream, char** out_text) {
    if (handle == nullptr || stream == nullptr || out_text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    auto result = h->stt->decode(stream_id);
    *out_text = strdup(result.text.c_str());
    if (!*out_text) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    return RAC_SUCCESS;
}

void rac_stt_sherpa_input_finished(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    h->stt->input_finished(stream_id);
}

rac_bool_t rac_stt_sherpa_is_endpoint(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    return h->stt->is_endpoint(stream_id) ? RAC_TRUE : RAC_FALSE;
}

void rac_stt_sherpa_destroy_stream(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    h->stt->destroy_stream(stream_id);
    free(stream_id);
}

rac_result_t rac_stt_sherpa_get_languages(rac_handle_t handle, char** out_json) {
    if (handle == nullptr || out_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    if (!h->stt) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    const auto languages = h->stt->get_supported_languages();
    *out_json = build_json_string_array(languages);
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_stt_sherpa_detect_language(rac_handle_t handle, const void* audio_data,
                                          size_t audio_size, const rac_stt_options_t* options,
                                          char** out_language) {
    if (handle == nullptr || audio_data == nullptr || out_language == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    if (!h->stt) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Convert Int16 PCM -> Float32 (same format the Sherpa STT vtable uses).
    const int16_t* samples = static_cast<const int16_t*>(audio_data);
    const size_t num_samples = audio_size / sizeof(int16_t);
    if (num_samples == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    runanywhere::STTRequest request;
    request.audio_samples.resize(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        request.audio_samples[i] = static_cast<float>(samples[i]) / 32768.0f;
    }
    request.sample_rate = (options && options->sample_rate > 0) ? options->sample_rate : 16000;
    request.detect_language = true;
    request.language.clear();

    const auto result = h->stt->transcribe(request);
    if (result.detected_language.empty()) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    *out_language = strdup(result.detected_language.c_str());
    if (!*out_language) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

void rac_stt_sherpa_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_sherpa_stt_handle_impl*>(handle);
    if (h->stt) {
        h->stt->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("stt.backend.destroyed", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"sherpa"})");
}

}  // extern "C"
