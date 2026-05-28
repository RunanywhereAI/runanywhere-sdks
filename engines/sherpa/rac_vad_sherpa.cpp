/**
 * @file rac_vad_sherpa.cpp
 * @brief Sherpa-ONNX RAC API implementation.
 */

#include "rac_vad_sherpa.h"

#include "rac_stt_sherpa.h"
#include "rac_tts_sherpa.h"
#include "sherpa_backend.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <set>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

struct rac_sherpa_vad_handle_impl {
    std::unique_ptr<runanywhere::SherpaBackend> backend;
    runanywhere::SherpaVAD* vad;  // Owned by backend
};

extern "C" {

// =============================================================================
// VAD IMPLEMENTATION
// =============================================================================

rac_result_t rac_vad_sherpa_create(const char* model_path, const rac_vad_sherpa_config_t* config,
                                   rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_sherpa_vad_handle_impl();
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

    // DUP-06: "vad.backend.created" now emitted once by the commons VAD
    // component load path
    // (sdk/runanywhere-commons/src/features/vad/vad_component.cpp in
    // rac_vad_component_load_model) so future backends inherit the emit.

    return RAC_SUCCESS;
}

rac_result_t rac_vad_sherpa_process(rac_handle_t handle, const float* samples, size_t num_samples,
                                    rac_bool_t* out_is_speech) {
    if (handle == nullptr || samples == nullptr || out_is_speech == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_vad_handle_impl*>(handle);
    if (!h->vad) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    std::vector<float> audio(samples, samples + num_samples);
    // engines-012/013: honor the configured VAD sample rate instead of
    // hard-coding 16000. The C ABI/vtable here does not yet carry a
    // per-call sample_rate (unlike rac_stt_sherpa_feed_audio, which got
    // that surgical fix under engines-sherpa-003), so we route the rate
    // from the per-handle VAD config that was set at load/configure time.
    // Non-positive configured rates fall back to 16k to preserve the
    // historic default for callers that have not been updated yet.
    const auto vad_config = h->vad->get_vad_config();
    const int effective_rate = vad_config.sample_rate > 0 ? vad_config.sample_rate : 16000;
    auto result = h->vad->process(audio, effective_rate);

    *out_is_speech = result.is_speech ? RAC_TRUE : RAC_FALSE;

    return RAC_SUCCESS;
}

rac_result_t rac_vad_sherpa_start(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_sherpa_stop(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_sherpa_reset(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_vad_handle_impl*>(handle);
    if (h->vad) {
        h->vad->reset();
    }

    return RAC_SUCCESS;
}

rac_result_t rac_vad_sherpa_set_threshold(rac_handle_t handle, float threshold) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_sherpa_vad_handle_impl*>(handle);
    if (!h->vad) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto config = h->vad->get_vad_config();
    config.threshold = threshold;
    // Surface the live-detector rebuild result to callers so a failed
    // recreate (e.g. SherpaOnnxCreateVoiceActivityDetector returns null)
    // is not silently reported as a successful threshold change.
    return h->vad->configure_vad(config) ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
}

rac_bool_t rac_vad_sherpa_is_speech_active(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_sherpa_vad_handle_impl*>(handle);
    // Report the *latest detected speech* state instead of model readiness.
    // is_ready() is true the moment the model loads and stays true through
    // silence/reset, so consumers of VADServiceState.is_speech_active (UI,
    // speech gates, barge-in) would otherwise see a stuck-active signal.
    return (h->vad && h->vad->is_speech_active()) ? RAC_TRUE : RAC_FALSE;
}

void rac_vad_sherpa_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_sherpa_vad_handle_impl*>(handle);
    if (h->vad) {
        h->vad->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("vad.backend.destroyed", RAC_EVENT_CATEGORY_VOICE, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"sherpa"})");
}

}  // extern "C"
