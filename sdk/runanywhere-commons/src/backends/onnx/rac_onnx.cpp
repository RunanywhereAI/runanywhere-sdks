/**
 * @file rac_onnx.cpp
 * @brief RunAnywhere Core - ONNX Backend RAC API Implementation
 *
 * Direct RAC API implementation that calls C++ classes.
 * Includes STT, TTS, and VAD functionality.
 */

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "onnx_backend.h"

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

// =============================================================================
// INTERNAL HANDLE STRUCTURES
// =============================================================================

struct rac_onnx_stt_handle_impl {
    std::unique_ptr<runanywhere::ONNXBackendNew> backend;
    runanywhere::ONNXSTT* stt;  // Owned by backend
};

struct rac_onnx_tts_handle_impl {
    std::unique_ptr<runanywhere::ONNXBackendNew> backend;
    runanywhere::ONNXTTS* tts;  // Owned by backend
};

struct rac_onnx_vad_handle_impl {
    std::unique_ptr<runanywhere::ONNXBackendNew> backend;
    runanywhere::ONNXVAD* vad;  // Owned by backend
};

// =============================================================================
// STT IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_stt_onnx_create(const char* model_path, const rac_stt_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_onnx_stt_handle_impl();
    if (!handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create and initialize backend
    handle->backend = std::make_unique<runanywhere::ONNXBackendNew>();
    nlohmann::json init_config;
    if (config != nullptr && config->num_threads > 0) {
        init_config["num_threads"] = config->num_threads;
    }

    if (!handle->backend->initialize(init_config)) {
        delete handle;
        rac_error_set_details("Failed to initialize ONNX backend");
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
                    R"({"backend":"onnx"})");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples,
                                     size_t num_samples, const rac_stt_options_t* options,
                                     rac_stt_result_t* out_result) {
    if (handle == nullptr || audio_samples == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
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

rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }
    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    return (h->stt && h->stt->supports_streaming()) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream) {
    if (handle == nullptr || out_stream == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
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

rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                     const float* audio_samples, size_t num_samples) {
    if (handle == nullptr || stream == nullptr || audio_samples == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    std::vector<float> samples(audio_samples, audio_samples + num_samples);
    bool success = h->stt->feed_audio(stream_id, samples, 16000);

    return success ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
}

rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    return h->stt->is_stream_ready(stream_id) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream, char** out_text) {
    if (handle == nullptr || stream == nullptr || out_text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    auto result = h->stt->decode(stream_id);
    *out_text = strdup(result.text.c_str());
    if (!*out_text) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    return RAC_SUCCESS;
}

void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    h->stt->input_finished(stream_id);
}

rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    return h->stt->is_endpoint(stream_id) ? RAC_TRUE : RAC_FALSE;
}

void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream) {
    if (handle == nullptr || stream == nullptr) {
        return;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    auto* stream_id = static_cast<char*>(stream);

    h->stt->destroy_stream(stream_id);
    free(stream_id);
}

void rac_stt_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_onnx_stt_handle_impl*>(handle);
    if (h->stt) {
        h->stt->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("stt.backend.destroyed", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");
}

// =============================================================================
// TTS IMPLEMENTATION
// =============================================================================

rac_result_t rac_tts_onnx_create(const char* model_path, const rac_tts_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_onnx_tts_handle_impl();
    if (!handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    handle->backend = std::make_unique<runanywhere::ONNXBackendNew>();
    nlohmann::json init_config;
    if (config != nullptr && config->num_threads > 0) {
        init_config["num_threads"] = config->num_threads;
    }

    if (!handle->backend->initialize(init_config)) {
        delete handle;
        rac_error_set_details("Failed to initialize ONNX backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Get TTS component
    handle->tts = handle->backend->get_tts();
    if (!handle->tts) {
        delete handle;
        rac_error_set_details("TTS component not available");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    if (model_path != nullptr) {
        if (!handle->tts->load_model(model_path, runanywhere::TTSModelType::PIPER)) {
            delete handle;
            rac_error_set_details("Failed to load TTS model");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
    }

    *out_handle = static_cast<rac_handle_t>(handle);

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

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);
    if (!h->tts) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    runanywhere::TTSRequest request;
    request.text = text;
    if (options && options->voice) {
        request.voice_id = options->voice;
    }
    if (options && options->rate > 0) {
        request.speed_rate = options->rate;
    }

    auto result = h->tts->synthesize(request);
    if (result.audio_samples.empty()) {
        rac_error_set_details("TTS synthesis failed");
        return RAC_ERROR_INFERENCE_FAILED;
    }

    float* audio_copy = static_cast<float*>(malloc(result.audio_samples.size() * sizeof(float)));
    if (!audio_copy) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(audio_copy, result.audio_samples.data(), result.audio_samples.size() * sizeof(float));

    out_result->audio_data = audio_copy;
    out_result->audio_size = result.audio_samples.size() * sizeof(float);
    out_result->audio_format = RAC_AUDIO_FORMAT_PCM;
    out_result->sample_rate = result.sample_rate;
    out_result->duration_ms = result.duration_ms;
    out_result->processing_time_ms = 0;

    rac_event_track("tts.synthesis.completed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    nullptr);

    return RAC_SUCCESS;
}

rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count) {
    if (handle == nullptr || out_voices == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);
    if (!h->tts) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto voices = h->tts->get_voices();

    if (voices.empty()) {
        *out_voices = nullptr;
        *out_count = 0;
        return RAC_SUCCESS;
    }

    *out_voices = static_cast<char**>(malloc(voices.size() * sizeof(char*)));
    if (!*out_voices) {
        *out_count = 0;
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    *out_count = voices.size();
    for (size_t i = 0; i < voices.size(); i++) {
        (*out_voices)[i] = strdup(voices[i].id.c_str());
        if (!(*out_voices)[i]) {
            for (size_t j = 0; j < i; j++) {
                free((*out_voices)[j]);
            }
            free(*out_voices);
            *out_voices = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

void rac_tts_onnx_stop(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }
    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);
    if (h->tts) {
        h->tts->cancel();
    }
}

void rac_tts_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);
    if (h->tts) {
        h->tts->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("tts.backend.destroyed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");
}

// =============================================================================
// VAD IMPLEMENTATION
// =============================================================================

rac_result_t rac_vad_onnx_create(const char* model_path, const rac_vad_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_onnx_vad_handle_impl();
    if (!handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    handle->backend = std::make_unique<runanywhere::ONNXBackendNew>();
    nlohmann::json init_config;
    if (config != nullptr && config->num_threads > 0) {
        init_config["num_threads"] = config->num_threads;
    }

    if (!handle->backend->initialize(init_config)) {
        delete handle;
        rac_error_set_details("Failed to initialize ONNX backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Get VAD component
    handle->vad = handle->backend->get_vad();
    if (!handle->vad) {
        delete handle;
        rac_error_set_details("VAD component not available");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    if (model_path != nullptr) {
        nlohmann::json model_config;
        if (config != nullptr) {
            model_config["energy_threshold"] = config->energy_threshold;
        }
        if (!handle->vad->load_model(model_path, runanywhere::VADModelType::SILERO, model_config)) {
            delete handle;
            rac_error_set_details("Failed to load VAD model");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
    }

    *out_handle = static_cast<rac_handle_t>(handle);

    rac_event_track("vad.backend.created", RAC_EVENT_CATEGORY_VOICE, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");

    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples, size_t num_samples,
                                  rac_bool_t* out_is_speech) {
    if (handle == nullptr || samples == nullptr || out_is_speech == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_vad_handle_impl*>(handle);
    if (!h->vad) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    std::vector<float> audio(samples, samples + num_samples);
    auto result = h->vad->process(audio, 16000);

    *out_is_speech = result.is_speech ? RAC_TRUE : RAC_FALSE;

    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_start(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_stop(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_reset(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_vad_handle_impl*>(handle);
    if (h->vad) {
        h->vad->reset();
    }

    return RAC_SUCCESS;
}

rac_result_t rac_vad_onnx_set_threshold(rac_handle_t handle, float threshold) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_vad_handle_impl*>(handle);
    if (h->vad) {
        auto config = h->vad->get_vad_config();
        config.threshold = threshold;
        h->vad->configure_vad(config);
    }

    return RAC_SUCCESS;
}

rac_bool_t rac_vad_onnx_is_speech_active(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_onnx_vad_handle_impl*>(handle);
    return (h->vad && h->vad->is_ready()) ? RAC_TRUE : RAC_FALSE;
}

void rac_vad_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_onnx_vad_handle_impl*>(handle);
    if (h->vad) {
        h->vad->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("vad.backend.destroyed", RAC_EVENT_CATEGORY_VOICE, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx"})");
}

}  // extern "C"
