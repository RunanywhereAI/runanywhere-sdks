/**
 * @file rac_tts_sherpa.cpp
 * @brief Sherpa-ONNX RAC API implementation.
 */

#include "rac_tts_sherpa.h"

#include "rac_stt_sherpa.h"
#include "rac_vad_sherpa.h"
#include "sherpa_backend.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <set>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"

struct rac_sherpa_tts_handle_impl {
    std::unique_ptr<runanywhere::SherpaBackend> backend;
    runanywhere::SherpaTTS* tts;  // Owned by backend

    // Voice-info cache for `rac_tts_sherpa_get_info`. The service-layer
    // lifecycle voice-list ABI (`rac_nonllm_lifecycle_proto_abi.cpp`) and the
    // component voice-list path (`tts_component.cpp`) both surface voices via
    // `rac_tts_info_t.available_voices`, which is a `const char* const*`
    // owned by the engine. Storing both the backing strings and the pointer
    // array on the handle keeps the pointer addresses stable across
    // overlapping reads while still letting us refresh after `load_model`.
    std::mutex voice_cache_mutex;
    std::vector<std::string> voice_ids;
    std::vector<const char*> voice_ptrs;
};

extern "C" {

// TTS IMPLEMENTATION

rac_result_t rac_tts_sherpa_create(const char* model_path, const rac_tts_sherpa_config_t* config,
                                   rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_sherpa_tts_handle_impl();
    if (!handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

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

    // "tts.backend.created" now emitted once by the commons TTS
    // service layer
    // (sdk/runanywhere-commons/src/features/tts/rac_tts_service.cpp) so future
    // backends inherit the emit without duplicating it per plugin.

    return RAC_SUCCESS;
}

rac_result_t rac_tts_sherpa_synthesize(rac_handle_t handle, const char* text,
                                       const rac_tts_options_t* options,
                                       rac_tts_result_t* out_result) {
    if (handle == nullptr || text == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_tts_handle_impl*>(handle);
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

    return RAC_SUCCESS;
}

rac_result_t rac_tts_sherpa_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count) {
    if (handle == nullptr || out_voices == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_tts_handle_impl*>(handle);
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

rac_result_t rac_tts_sherpa_get_info(rac_handle_t handle, rac_tts_info_t* out_info) {
    if (handle == nullptr || out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_tts_handle_impl*>(handle);

    out_info->is_ready = (h->tts != nullptr) ? RAC_TRUE : RAC_FALSE;
    out_info->is_synthesizing = RAC_FALSE;

    std::lock_guard<std::mutex> lock(h->voice_cache_mutex);
    h->voice_ids.clear();
    h->voice_ptrs.clear();

    if (h->tts) {
        const auto& voices = h->tts->get_voices();
        h->voice_ids.reserve(voices.size());
        h->voice_ptrs.reserve(voices.size());
        for (const auto& v : voices) {
            if (v.id.empty()) {
                continue;
            }
            h->voice_ids.push_back(v.id);
        }
        for (const auto& id : h->voice_ids) {
            h->voice_ptrs.push_back(id.c_str());
        }
    }

    out_info->available_voices = h->voice_ptrs.empty() ? nullptr : h->voice_ptrs.data();
    out_info->num_voices = h->voice_ptrs.size();
    return RAC_SUCCESS;
}

rac_result_t rac_tts_sherpa_get_languages(rac_handle_t handle, char** out_json) {
    if (handle == nullptr || out_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_tts_handle_impl*>(handle);
    if (!h->tts) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Sherpa-ONNX (Piper) voices expose a language tag. Deduplicate via set so
    // multi-voice models don't emit "[\"en\",\"en\",...]".
    std::set<std::string> seen;
    std::vector<std::string> languages;
    for (const auto& voice : h->tts->get_voices()) {
        if (voice.language.empty() || !seen.insert(voice.language).second) {
            continue;
        }
        languages.push_back(voice.language);
    }

    *out_json = rac::backends::sherpa::build_json_string_array(languages);
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

void rac_tts_sherpa_stop(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }
    auto* h = static_cast<rac_sherpa_tts_handle_impl*>(handle);
    if (h->tts) {
        h->tts->cancel();
    }
}

void rac_tts_sherpa_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_sherpa_tts_handle_impl*>(handle);
    if (h->tts) {
        h->tts->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;
}

}  // extern "C"
