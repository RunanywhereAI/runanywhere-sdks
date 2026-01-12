/**
 * @file rac_stt_whispercpp.cpp
 * @brief RunAnywhere Core - WhisperCPP RAC API Implementation
 *
 * Direct RAC API implementation that calls C++ classes.
 */

#include "rac_stt_whispercpp.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "whispercpp_backend.h"

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

// =============================================================================
// INTERNAL HANDLE STRUCTURE
// =============================================================================

struct rac_whispercpp_handle_impl {
    std::unique_ptr<runanywhere::WhisperCppBackend> backend;
    runanywhere::WhisperCppSTT* stt;  // Owned by backend
    std::string detected_language;
};

// =============================================================================
// RAC API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_stt_whispercpp_create(const char* model_path,
                                       const rac_stt_whispercpp_config_t* config,
                                       rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_whispercpp_handle_impl();
    if (!handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create and initialize backend
    handle->backend = std::make_unique<runanywhere::WhisperCppBackend>();

    nlohmann::json init_config;
    if (config != nullptr) {
        if (config->num_threads > 0) {
            init_config["num_threads"] = config->num_threads;
        }
        init_config["use_gpu"] = config->use_gpu == RAC_TRUE;
    }

    if (!handle->backend->initialize(init_config)) {
        delete handle;
        rac_error_set_details("Failed to initialize WhisperCPP backend");
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
        nlohmann::json model_config;
        if (config != nullptr && config->translate == RAC_TRUE) {
            model_config["translate"] = true;
        }

        if (!handle->stt->load_model(model_path, runanywhere::STTModelType::WHISPER, model_config)) {
            delete handle;
            rac_error_set_details("Failed to load WhisperCPP model");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
    }

    *out_handle = static_cast<rac_handle_t>(handle);

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

    auto* h = static_cast<rac_whispercpp_handle_impl*>(handle);
    if (!h->stt) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Prepare request
    runanywhere::STTRequest request;
    request.audio_samples.assign(audio_samples, audio_samples + num_samples);
    request.sample_rate = (options && options->sample_rate > 0) ? options->sample_rate : 16000;

    if (options && options->language) {
        request.language = options->language;
    }

    // Perform transcription
    auto result = h->stt->transcribe(request);

    // Store detected language for later retrieval
    h->detected_language = result.detected_language;

    // Fill output
    out_result->text = result.text.empty() ? nullptr : strdup(result.text.c_str());
    out_result->detected_language =
        result.detected_language.empty() ? nullptr : strdup(result.detected_language.c_str());
    out_result->confidence = result.confidence;
    out_result->processing_time_ms = result.inference_time_ms;

    // Word-level timestamps
    out_result->words = nullptr;
    out_result->num_words = 0;
    if (!result.word_timings.empty()) {
        out_result->num_words = result.word_timings.size();
        out_result->words =
            static_cast<rac_stt_word_t*>(malloc(result.word_timings.size() * sizeof(rac_stt_word_t)));
        if (out_result->words) {
            for (size_t i = 0; i < result.word_timings.size(); i++) {
                out_result->words[i].text = strdup(result.word_timings[i].word.c_str());
                out_result->words[i].start_ms =
                    static_cast<int64_t>(result.word_timings[i].start_time_ms);
                out_result->words[i].end_ms =
                    static_cast<int64_t>(result.word_timings[i].end_time_ms);
                out_result->words[i].confidence = result.word_timings[i].confidence;
            }
        }
    }

    rac_event_track("stt.transcription.completed", RAC_EVENT_CATEGORY_STT,
                    RAC_EVENT_DESTINATION_ALL, R"({"backend":"whispercpp"})");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_whispercpp_get_language(rac_handle_t handle, char** out_language) {
    if (handle == nullptr || out_language == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_whispercpp_handle_impl*>(handle);

    if (h->detected_language.empty()) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    *out_language = strdup(h->detected_language.c_str());
    return RAC_SUCCESS;
}

rac_bool_t rac_stt_whispercpp_is_ready(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_whispercpp_handle_impl*>(handle);
    return (h->stt && h->stt->is_ready()) ? RAC_TRUE : RAC_FALSE;
}

void rac_stt_whispercpp_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_whispercpp_handle_impl*>(handle);
    if (h->stt) {
        h->stt->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("stt.backend.destroyed", RAC_EVENT_CATEGORY_STT, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"whispercpp"})");
}

}  // extern "C"
