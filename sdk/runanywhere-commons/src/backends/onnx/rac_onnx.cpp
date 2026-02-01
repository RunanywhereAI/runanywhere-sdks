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
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define ONNX_TTS_LOG(...) __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", __VA_ARGS__)
#define ONNX_TTS_ERR(...) __android_log_print(ANDROID_LOG_ERROR, "ONNX_TTS", __VA_ARGS__)
#else
#define ONNX_TTS_LOG(...) printf("[ONNX_TTS] " __VA_ARGS__); printf("\n")
#define ONNX_TTS_ERR(...) fprintf(stderr, "[ONNX_TTS ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#endif

#include "onnx_backend.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/events/rac_events.h"

// NPU/QNN support
// QNN DISABLED FOR NNAPI TESTING
// #include "rac/backends/rac_qnn_config.h"
// #include "rac/backends/rac_onnx_npu.h"

// Kokoro TTS loader (internal, auto-detected)
#include "kokoro/kokoro_tts_loader.h"

// =============================================================================
// INTERNAL HANDLE STRUCTURES
// =============================================================================

struct rac_onnx_stt_handle_impl {
    std::unique_ptr<runanywhere::ONNXBackendNew> backend;
    runanywhere::ONNXSTT* stt;  // Owned by backend
};

/**
 * @brief TTS handle that supports both Sherpa-ONNX and Kokoro models
 *
 * Kokoro models are auto-detected and use the dedicated KokoroTTSLoader.
 * Other models (Piper/VITS) use the Sherpa-ONNX backend.
 */
struct rac_onnx_tts_handle_impl {
    // Sherpa-ONNX backend (for Piper/VITS models)
    std::unique_ptr<runanywhere::ONNXBackendNew> backend;
    runanywhere::ONNXTTS* tts;  // Owned by backend

    // Kokoro TTS loader (for Kokoro models - auto-detected)
    std::unique_ptr<rac::onnx::KokoroTTSLoader> kokoro_loader;

    // Flag to indicate which backend is active
    bool is_kokoro = false;
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
    out_result->detected_language =
        result.detected_language.empty() ? nullptr : strdup(result.detected_language.c_str());
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

    *out_stream = static_cast<rac_handle_t>(strdup(stream_id.c_str()));
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

/**
 * Check if a directory contains split models for hybrid execution.
 * Looks for kokoro_encoder.onnx + kokoro_vocoder.onnx (or similar patterns).
 * Checks both the root directory and common subdirectories like 'package/'.
 */
static bool detect_hybrid_model(const char* model_path, std::string& encoder_path, std::string& vocoder_path) {
    if (model_path == nullptr) return false;

    std::string base_path(model_path);

    // List of paths to check (root and common subdirectories)
    std::vector<std::string> paths_to_check = {
        base_path,
        base_path + "/package",  // ZIP extractions often have this structure
        base_path + "/models",
    };

    for (const auto& path : paths_to_check) {
        std::string encoder_kokoro = path + "/kokoro_encoder.onnx";
        std::string vocoder_kokoro = path + "/kokoro_vocoder.onnx";

        std::ifstream enc_file(encoder_kokoro);
        std::ifstream voc_file(vocoder_kokoro);

        if (enc_file.good() && voc_file.good()) {
            encoder_path = encoder_kokoro;
            vocoder_path = vocoder_kokoro;
            return true;
        }
    }

    return false;
}

/**
 * Check if a directory contains a unified Kokoro model (no split needed).
 * Looks for kokoro.onnx, kokoro_fixed.onnx, or kokoro_fixed_shape.onnx.
 * These models have had ISTFT replaced and can run on CPU directly.
 */
static bool detect_unified_kokoro_model(const char* model_path, std::string& unified_path) {
    if (model_path == nullptr) return false;

    std::string base_path(model_path);

    // List of paths to check
    std::vector<std::string> paths_to_check = {
        base_path,
        base_path + "/package",
        base_path + "/models",
    };

    // Unified model file names to look for (in priority order)
    std::vector<std::string> unified_names = {
        "kokoro.onnx",
        "kokoro_fixed.onnx",
        "kokoro_fixed_shape.onnx",
        "kokoro_unified.onnx",
    };

    for (const auto& path : paths_to_check) {
        for (const auto& name : unified_names) {
            std::string candidate = path + "/" + name;
            std::ifstream file(candidate);
            if (file.good()) {
                unified_path = candidate;
                ONNX_TTS_LOG("Found unified Kokoro model: %s", unified_path.c_str());
                return true;
            }
        }
    }

    return false;
}

rac_result_t rac_tts_onnx_create(const char* model_path, const rac_tts_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    ONNX_TTS_LOG("rac_tts_onnx_create called, model_path=%s", model_path ? model_path : "(null)");

    if (out_handle == nullptr) {
        ONNX_TTS_ERR("out_handle is null");
        return RAC_ERROR_NULL_POINTER;
    }

    // Check for hybrid model (split encoder/vocoder for NPU acceleration)
    std::string encoder_path, vocoder_path;
    bool is_hybrid = detect_hybrid_model(model_path, encoder_path, vocoder_path);
    ONNX_TTS_LOG("is_hybrid=%d, encoder=%s, vocoder=%s", is_hybrid, encoder_path.c_str(), vocoder_path.c_str());

    // If split model detected (encoder + vocoder), use Kokoro loader with NPU support
    if (is_hybrid) {
        ONNX_TTS_LOG("Split Kokoro model detected - using KokoroTTSLoader");
        RAC_LOG_INFO("TTS", "=== SPLIT KOKORO MODEL DETECTED (AUTO NPU ACCELERATION) ===");
        RAC_LOG_INFO("TTS", "Encoder: %s", encoder_path.c_str());
        RAC_LOG_INFO("TTS", "Vocoder: %s", vocoder_path.c_str());

        // Use the Kokoro loader which handles both split and unified models
        auto* handle = new (std::nothrow) rac_onnx_tts_handle_impl();
        if (!handle) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        handle->kokoro_loader = std::make_unique<rac::onnx::KokoroTTSLoader>();
        handle->is_kokoro = true;
        handle->tts = nullptr;

        // Configure for NPU acceleration
        rac::onnx::KokoroConfig kokoro_config;
        kokoro_config.num_threads = (config != nullptr && config->num_threads > 0) ? config->num_threads : 0;
        kokoro_config.enable_profiling = false;

        // QNN DISABLED FOR NNAPI TESTING - using NNAPI instead
        /*
        // Initialize QNN config
#if RAC_QNN_AVAILABLE
        rac_qnn_config_init_default(&kokoro_config.qnn_config);
        bool npu_available = rac_qnn_is_available();
        ONNX_TTS_LOG("NPU available: %s", npu_available ? "YES" : "NO");

        if (!npu_available) {
            // Fall back to CPU for encoder
            kokoro_config.qnn_config.backend = RAC_QNN_BACKEND_CPU;
            RAC_LOG_WARNING("TTS", "NPU not available, using CPU fallback for encoder");
        } else {
            RAC_LOG_INFO("TTS", "NPU available, using QNN HTP for encoder acceleration");
        }
#else
        // Initialize QNN config manually when QNN not compiled
        memset(&kokoro_config.qnn_config, 0, sizeof(kokoro_config.qnn_config));
        kokoro_config.qnn_config.backend = RAC_QNN_BACKEND_CPU;
        ONNX_TTS_LOG("QNN not compiled, using CPU for encoder");
#endif
        */ // END QNN DISABLED

        // Use NNAPI for NPU acceleration instead
        kokoro_config.npu_backend = rac::onnx::NPUBackend::NNAPI;
        ONNX_TTS_LOG("=== QNN DISABLED - Using NNAPI for NPU acceleration ===");

        // Load the split model (KokoroTTSLoader will detect it's split)
        std::string base_path = model_path ? model_path : "";
        rac_result_t result = handle->kokoro_loader->load(base_path, kokoro_config);

        if (result != RAC_SUCCESS) {
            ONNX_TTS_ERR("Failed to load split Kokoro model: %d", result);
            delete handle;
            rac_error_set_details("Failed to load split Kokoro TTS model");
            return result;
        }

        *out_handle = static_cast<rac_handle_t>(handle);

        bool npu_active = handle->kokoro_loader->is_npu_active();
        ONNX_TTS_LOG("Split Kokoro model loaded, NPU=%s", npu_active ? "YES" : "NO");
        RAC_LOG_INFO("TTS", "Split Kokoro TTS ready: NPU=%s", npu_active ? "YES" : "NO");

        rac_event_track("tts.backend.created", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                        npu_active ? R"({"backend":"onnx","mode":"kokoro_hybrid_npu"})"
                                   : R"({"backend":"onnx","mode":"kokoro_hybrid_cpu"})");

        return RAC_SUCCESS;
    }

    // Check for unified Kokoro model (no ISTFT, doesn't need splitting)
    std::string unified_path;
    bool is_unified_kokoro = detect_unified_kokoro_model(model_path, unified_path);
    ONNX_TTS_LOG("is_unified_kokoro=%d, unified_path=%s", is_unified_kokoro, unified_path.c_str());

    if (is_unified_kokoro) {
        ONNX_TTS_LOG("Loading unified Kokoro model via dedicated loader: %s", unified_path.c_str());
        RAC_LOG_INFO("TTS", "=== LOADING KOKORO TTS MODEL (AUTO-DETECTED) ===");
        RAC_LOG_INFO("TTS", "Model path: %s", unified_path.c_str());
        RAC_LOG_INFO("TTS", "Using dedicated KokoroTTSLoader for optimal performance");

        // Use the dedicated Kokoro TTS loader (handles both unified and split models)
        auto* handle = new (std::nothrow) rac_onnx_tts_handle_impl();
        if (!handle) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        // Create Kokoro loader
        handle->kokoro_loader = std::make_unique<rac::onnx::KokoroTTSLoader>();
        handle->is_kokoro = true;
        handle->tts = nullptr;  // Not using Sherpa-ONNX for Kokoro

        // Configure Kokoro loader
        rac::onnx::KokoroConfig kokoro_config;
        kokoro_config.num_threads = (config != nullptr && config->num_threads > 0) ? config->num_threads : 0;
        kokoro_config.enable_profiling = false;

        // Set NPU backend preference: NNAPI ONLY for testing
        // QNN is disabled - using NNAPI EP which routes to device NPU
#if RAC_NNAPI_AVAILABLE
        kokoro_config.npu_backend = rac::onnx::NPUBackend::NNAPI;
        ONNX_TTS_LOG("=== NNAPI BACKEND SELECTED (QNN DISABLED) ===");
        ONNX_TTS_LOG("Using NNAPI backend for NPU acceleration (vendor-agnostic)");
        // Initialize NNAPI config
        memset(&kokoro_config.nnapi_config, 0, sizeof(kokoro_config.nnapi_config));
        kokoro_config.nnapi_config.enabled = RAC_TRUE;
        kokoro_config.nnapi_config.use_fp16 = RAC_FALSE;  // FP32 model
        kokoro_config.nnapi_config.use_nchw = RAC_TRUE;
        kokoro_config.nnapi_config.cpu_disabled = RAC_FALSE;  // Allow CPU fallback for optimal hybrid NPU/CPU execution (1.48x speedup)
        kokoro_config.nnapi_config.min_api_level = 27;
        // QNN backend is DISABLED for NNAPI testing
        // #elif RAC_QNN_AVAILABLE
        //     kokoro_config.npu_backend = rac::onnx::NPUBackend::QNN;
        //     rac_qnn_config_init_default(&kokoro_config.qnn_config);
#else
        // No NNAPI available for unified model, fall back to CPU
        kokoro_config.npu_backend = rac::onnx::NPUBackend::CPU_ONLY;
        ONNX_TTS_LOG("NNAPI not available, using CPU");
#endif

        // Load the model (auto-detects unified vs split)
        // Use the base path, not the specific file, so the loader can detect type
        std::string base_path = model_path ? model_path : "";
        rac_result_t result = handle->kokoro_loader->load(base_path, kokoro_config);

        if (result != RAC_SUCCESS) {
            ONNX_TTS_ERR("Failed to load Kokoro model: %d", result);
            delete handle;
            rac_error_set_details("Failed to load Kokoro TTS model");
            return result;
        }

        *out_handle = static_cast<rac_handle_t>(handle);

        // Report model type and NPU status
        const char* model_type = handle->kokoro_loader->get_model_type() == rac::onnx::KokoroModelType::UNIFIED
                                 ? "unified" : "split";
        bool npu_active = handle->kokoro_loader->is_npu_active();

        ONNX_TTS_LOG("Kokoro model loaded: type=%s, NPU=%s", model_type, npu_active ? "YES" : "NO");
        RAC_LOG_INFO("TTS", "Kokoro TTS ready: type=%s, NPU=%s", model_type, npu_active ? "YES" : "NO");

        rac_event_track("tts.backend.created", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                        npu_active ? R"({"backend":"onnx","mode":"kokoro_hybrid_npu"})"
                                   : R"({"backend":"onnx","mode":"kokoro_unified"})");

        return RAC_SUCCESS;
    }

    // Standard Piper/VITS TTS loading (non-hybrid models only)
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

    // Check if this is a Kokoro model (auto-detected during load)
    if (h->is_kokoro && h->kokoro_loader) {
        ONNX_TTS_LOG("Synthesizing with Kokoro TTS: text='%.50s...'", text);

        // Use the Kokoro loader for synthesis
        std::string voice_id = (options && options->voice) ? options->voice : "af_heart";
        float speed_rate = (options && options->rate > 0) ? options->rate : 1.0f;

        std::vector<float> audio;
        rac_result_t result = h->kokoro_loader->synthesize_text(text, voice_id, speed_rate, audio);

        if (result != RAC_SUCCESS || audio.empty()) {
            ONNX_TTS_ERR("Kokoro synthesis failed: %d", result);
            rac_error_set_details("Kokoro TTS synthesis failed");
            return result != RAC_SUCCESS ? result : RAC_ERROR_INFERENCE_FAILED;
        }

        // Copy audio to result
        float* audio_copy = static_cast<float*>(malloc(audio.size() * sizeof(float)));
        if (!audio_copy) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(audio_copy, audio.data(), audio.size() * sizeof(float));

        out_result->audio_data = audio_copy;
        out_result->audio_size = audio.size() * sizeof(float);
        out_result->audio_format = RAC_AUDIO_FORMAT_PCM;
        out_result->sample_rate = h->kokoro_loader->get_sample_rate();
        out_result->duration_ms = (audio.size() / static_cast<float>(out_result->sample_rate)) * 1000.0f;
        out_result->processing_time_ms = static_cast<int32_t>(h->kokoro_loader->get_stats().total_inference_ms);

        ONNX_TTS_LOG("Kokoro synthesis complete: %zu samples, %d ms", audio.size(), out_result->processing_time_ms);

        rac_event_track("tts.synthesis.completed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                        R"({"backend":"kokoro"})");

        return RAC_SUCCESS;
    }

    // Standard Sherpa-ONNX path for Piper/VITS models
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

    // Kokoro models - return default voice
    if (h->is_kokoro) {
        *out_count = 1;
        *out_voices = static_cast<char**>(malloc(sizeof(char*)));
        (*out_voices)[0] = strdup("af_heart");  // Default Kokoro voice
        return RAC_SUCCESS;
    }

    // Sherpa-ONNX models
    if (!h->tts) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto voices = h->tts->get_voices();
    *out_count = voices.size();

    if (voices.empty()) {
        *out_voices = nullptr;
        return RAC_SUCCESS;
    }

    *out_voices = static_cast<char**>(malloc(voices.size() * sizeof(char*)));
    for (size_t i = 0; i < voices.size(); i++) {
        (*out_voices)[i] = strdup(voices[i].id.c_str());
    }

    return RAC_SUCCESS;
}

void rac_tts_onnx_stop(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }
    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);

    // Kokoro models don't have stop functionality yet
    if (h->is_kokoro) {
        return;
    }

    if (h->tts) {
        h->tts->cancel();
    }
}

void rac_tts_onnx_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);

    // Handle Kokoro models
    if (h->is_kokoro && h->kokoro_loader) {
        h->kokoro_loader->unload();
        h->kokoro_loader.reset();
        delete h;

        rac_event_track("tts.backend.destroyed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                        R"({"backend":"kokoro"})");
        return;
    }

    // Handle Sherpa-ONNX models
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

// =============================================================================
// HYBRID TTS IMPLEMENTATION (NPU + CPU)
// =============================================================================

/* QNN DISABLED FOR NNAPI TESTING - ENTIRE HYBRID TTS SECTION COMMENTED OUT
#if RAC_QNN_AVAILABLE

// Forward declarations are in headers - no need to redeclare

struct rac_hybrid_tts_handle_impl {
    rac_split_executor_t split_executor = nullptr;
    rac_qnn_config_t qnn_config;
    bool npu_active = false;
};

rac_result_t rac_tts_onnx_create_hybrid(const char* encoder_path, const char* vocoder_path,
                                        const rac_qnn_config_t* qnn_config,
                                        rac_handle_t* out_handle) {
    ONNX_TTS_LOG("rac_tts_onnx_create_hybrid called");
    ONNX_TTS_LOG("  encoder_path=%s", encoder_path ? encoder_path : "(null)");
    ONNX_TTS_LOG("  vocoder_path=%s", vocoder_path ? vocoder_path : "(null)");

    if (encoder_path == nullptr || vocoder_path == nullptr || out_handle == nullptr) {
        ONNX_TTS_ERR("NULL pointer error");
        return RAC_ERROR_NULL_POINTER;
    }

    auto* handle = new (std::nothrow) rac_hybrid_tts_handle_impl();
    if (!handle) {
        ONNX_TTS_ERR("Out of memory allocating handle");
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Copy QNN config or use defaults
    if (qnn_config != nullptr) {
        handle->qnn_config = *qnn_config;
        ONNX_TTS_LOG("Using provided QNN config, backend=%d", qnn_config->backend);
    } else {
#if RAC_QNN_AVAILABLE
        rac_qnn_config_init_default(&handle->qnn_config);
#else
        memset(&handle->qnn_config, 0, sizeof(handle->qnn_config));
        handle->qnn_config.backend = RAC_QNN_BACKEND_CPU;
#endif
        ONNX_TTS_LOG("Using default QNN config");
    }

    // Create split model config
    rac_split_model_config_t split_config;
    rac_split_model_config_init(&split_config, encoder_path, vocoder_path);
    ONNX_TTS_LOG("Split config initialized");

    // Create split executor
    ONNX_TTS_LOG("Calling rac_split_executor_create...");
    rac_result_t result = rac_split_executor_create(&split_config, &handle->qnn_config,
                                                    &handle->split_executor);
    ONNX_TTS_LOG("rac_split_executor_create returned %d", result);
    if (result != RAC_SUCCESS) {
        const char* details = rac_error_get_details();
        ONNX_TTS_ERR("Split executor creation failed: %d, details: %s", result, details ? details : "(null)");
        delete handle;
        return result;
    }

    handle->npu_active = true;
    *out_handle = static_cast<rac_handle_t>(handle);

    rac_event_track("tts.hybrid.created", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx","mode":"hybrid_npu"})");

    return RAC_SUCCESS;
}

rac_result_t rac_tts_onnx_get_npu_stats(rac_handle_t handle, rac_npu_stats_t* out_stats) {
    if (handle == nullptr || out_stats == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_hybrid_tts_handle_impl*>(handle);
    if (!h->split_executor) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Get stats from split executor
    rac_split_exec_stats_t exec_stats;
    rac_result_t result = rac_split_executor_get_stats(h->split_executor, &exec_stats);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Convert to npu_stats
    out_stats->is_npu_active = h->npu_active ? RAC_TRUE : RAC_FALSE;
    out_stats->active_strategy = RAC_NPU_STRATEGY_HYBRID;
    out_stats->encoder_inference_ms = exec_stats.encoder_inference_ms;
    out_stats->vocoder_inference_ms = exec_stats.vocoder_inference_ms;
    out_stats->total_inference_ms = exec_stats.total_inference_ms;
    out_stats->total_inferences = exec_stats.total_inferences;
    // Encoder is 98.3% of ops for Kokoro
    out_stats->npu_op_percentage = exec_stats.encoder_on_npu ? 98.3f : 0.0f;

    return RAC_SUCCESS;
}

rac_bool_t rac_tts_onnx_is_npu_active(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_hybrid_tts_handle_impl*>(handle);
    return h->npu_active ? RAC_TRUE : RAC_FALSE;
}

void rac_tts_onnx_destroy_hybrid(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_hybrid_tts_handle_impl*>(handle);
    if (h->split_executor) {
        rac_split_executor_destroy(h->split_executor);
    }
    delete h;

    rac_event_track("tts.hybrid.destroyed", RAC_EVENT_CATEGORY_TTS, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"onnx","mode":"hybrid_npu"})");
}

#else // !RAC_QNN_AVAILABLE
*/ // END QNN DISABLED

// QNN DISABLED - All hybrid functions return error
rac_result_t rac_tts_onnx_create_hybrid(const char* encoder_path, const char* vocoder_path,
                                        const void* qnn_config,  // Changed from rac_qnn_config_t*
                                        rac_handle_t* out_handle) {
    (void)encoder_path;
    (void)vocoder_path;
    (void)qnn_config;
    (void)out_handle;
    ONNX_TTS_LOG("QNN DISABLED: rac_tts_onnx_create_hybrid not available");
    return RAC_ERROR_NOT_IMPLEMENTED;  // QNN disabled for NNAPI testing
}

rac_result_t rac_tts_onnx_get_npu_stats(rac_handle_t handle, void* out_stats) {  // Changed from rac_npu_stats_t*
    (void)handle;
    (void)out_stats;
    ONNX_TTS_LOG("QNN DISABLED: rac_tts_onnx_get_npu_stats not available");
    return RAC_ERROR_NOT_IMPLEMENTED;  // QNN disabled for NNAPI testing
}

rac_bool_t rac_tts_onnx_is_npu_active(rac_handle_t handle) {
    (void)handle;
    return RAC_FALSE;  // QNN disabled for NNAPI testing
}

void rac_tts_onnx_destroy_hybrid(rac_handle_t handle) {
    (void)handle;
    // QNN disabled for NNAPI testing
}

/* QNN DISABLED - closing bracket for the commented section
#endif // RAC_QNN_AVAILABLE
*/

// =============================================================================
// NPU DETECTION (wrapper for qnn_device_detector)
// =============================================================================

/* QNN DISABLED FOR NNAPI TESTING - All NPU detection functions return QNN disabled
rac_bool_t rac_onnx_is_npu_available(void) {
#if RAC_QNN_AVAILABLE
    return rac_qnn_is_available();
#else
    return RAC_FALSE;
#endif
}
*/

// QNN DISABLED - Always return FALSE for QNN availability
rac_bool_t rac_onnx_is_npu_available(void) {
    ONNX_TTS_LOG("QNN DISABLED: rac_onnx_is_npu_available always returns FALSE");
    return RAC_FALSE;  // QNN disabled for NNAPI testing
}

rac_result_t rac_onnx_get_npu_info_json(char* out_json, size_t json_size) {
    // QNN DISABLED FOR NNAPI TESTING
    if (out_json && json_size > 0) {
        snprintf(out_json, json_size, "{\"htp_available\":false,\"reason\":\"QNN disabled for NNAPI testing\"}");
    }
    return RAC_SUCCESS;
}

/* QNN DISABLED - rac_soc_info_t type not available
rac_result_t rac_onnx_get_soc_info(rac_soc_info_t* out_info) {
#if RAC_QNN_AVAILABLE
    return rac_qnn_get_soc_info(out_info);
#else
    if (out_info) {
        memset(out_info, 0, sizeof(rac_soc_info_t));
        strncpy(out_info->name, "Unknown", sizeof(out_info->name) - 1);
        out_info->htp_available = RAC_FALSE;
    }
    return RAC_ERROR_QNN_NOT_AVAILABLE;
#endif
}
*/

rac_result_t rac_onnx_get_soc_info(void* out_info) {
    (void)out_info;
    ONNX_TTS_LOG("QNN DISABLED: rac_onnx_get_soc_info not available");
    return RAC_ERROR_NOT_IMPLEMENTED;  // QNN disabled for NNAPI testing
}

/* QNN DISABLED - rac_model_validation_result_t type not available
rac_result_t rac_onnx_validate_model_for_npu(const char* model_path,
                                             rac_model_validation_result_t* out_result) {
#if RAC_QNN_AVAILABLE
    return rac_qnn_validate_model(model_path, out_result);
#else
    (void)model_path;
    if (out_result) {
        memset(out_result, 0, sizeof(rac_model_validation_result_t));
        out_result->is_npu_ready = RAC_FALSE;
        strncpy(out_result->recommendation, "QNN not compiled", sizeof(out_result->recommendation) - 1);
    }
    return RAC_ERROR_QNN_NOT_AVAILABLE;
#endif
}
*/

rac_result_t rac_onnx_validate_model_for_npu(const char* model_path, void* out_result) {
    (void)model_path;
    (void)out_result;
    ONNX_TTS_LOG("QNN DISABLED: rac_onnx_validate_model_for_npu not available");
    return RAC_ERROR_NOT_IMPLEMENTED;  // QNN disabled for NNAPI testing
}

}  // extern "C"

// =============================================================================
// KOKORO NPU vs CPU BENCHMARK API
// =============================================================================

/**
 * @brief Run NPU vs CPU benchmark on Kokoro TTS
 *
 * This function runs the same text through both NPU (NNAPI) and CPU-only
 * execution paths and returns a JSON string with the comparison results.
 *
 * @param handle TTS handle (must be a Kokoro model)
 * @param test_text Optional test text (uses default if NULL or empty)
 * @param out_json Output buffer for JSON result
 * @param json_size Size of the output buffer
 * @return RAC_SUCCESS on success, error code on failure
 */
__attribute__((visibility("default"), used))
extern "C" rac_result_t rac_tts_kokoro_run_benchmark(rac_handle_t handle, const char* test_text,
                                          char* out_json, size_t json_size) {
    ONNX_TTS_LOG("rac_tts_kokoro_run_benchmark called");

    if (handle == nullptr || out_json == nullptr || json_size == 0) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);

    // Check if this is a Kokoro model
    if (!h->is_kokoro || !h->kokoro_loader) {
        ONNX_TTS_ERR("Benchmark only available for Kokoro TTS models");
        snprintf(out_json, json_size,
                "{\"success\":false,\"error\":\"Benchmark only available for Kokoro TTS models\"}");
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Check if model is loaded
    if (!h->kokoro_loader->is_loaded()) {
        ONNX_TTS_ERR("Kokoro model not loaded");
        snprintf(out_json, json_size,
                "{\"success\":false,\"error\":\"Model not loaded\"}");
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    ONNX_TTS_LOG("Running Kokoro NPU vs CPU benchmark...");

    // Run the benchmark
    std::string text = (test_text != nullptr && test_text[0] != '\0') ? test_text : "";
    rac::onnx::KokoroBenchmarkResult result = h->kokoro_loader->run_benchmark(text);

    // Format result as JSON
    snprintf(out_json, json_size,
        "{"
        "\"success\":%s,"
        "\"npu_available\":%s,"
        "\"npu_is_faster\":%s,"
        "\"npu_inference_ms\":%.2f,"
        "\"cpu_inference_ms\":%.2f,"
        "\"audio_duration_ms\":%.2f,"
        "\"npu_rtf\":%.2f,"
        "\"cpu_rtf\":%.2f,"
        "\"speedup\":%.2f,"
        "\"audio_samples\":%zu,"
        "\"sample_rate\":%d,"
        "\"num_tokens\":%zu,"
        "\"test_text\":\"%s\","
        "\"error\":\"%s\""
        "}",
        result.success ? "true" : "false",
        result.npu_available ? "true" : "false",
        result.npu_is_faster ? "true" : "false",
        result.npu_inference_ms,
        result.cpu_inference_ms,
        result.audio_duration_ms,
        result.npu_rtf,
        result.cpu_rtf,
        result.speedup,
        result.audio_samples,
        result.sample_rate,
        result.num_tokens,
        result.test_text.substr(0, 50).c_str(),  // Truncate for JSON
        result.error_message.c_str()
    );

    ONNX_TTS_LOG("Benchmark complete: NPU=%.2fms, CPU=%.2fms, Speedup=%.2fx",
                result.npu_inference_ms, result.cpu_inference_ms, result.speedup);

    return result.success ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
}

/**
 * @brief Check if a TTS handle is a Kokoro model
 *
 * @param handle TTS handle
 * @return RAC_TRUE if Kokoro, RAC_FALSE otherwise
 */
__attribute__((visibility("default"), used))
extern "C" rac_bool_t rac_tts_is_kokoro(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);
    return (h->is_kokoro && h->kokoro_loader) ? RAC_TRUE : RAC_FALSE;
}

/**
 * @brief Check if NNAPI NPU is active for the loaded Kokoro model
 *
 * @param handle TTS handle (must be a Kokoro model)
 * @return RAC_TRUE if NPU is active, RAC_FALSE otherwise
 */
__attribute__((visibility("default"), used))
extern "C" rac_bool_t rac_tts_kokoro_is_npu_active(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* h = static_cast<rac_onnx_tts_handle_impl*>(handle);
    if (!h->is_kokoro || !h->kokoro_loader) {
        return RAC_FALSE;
    }

    return h->kokoro_loader->is_npu_active() ? RAC_TRUE : RAC_FALSE;
}

/**
 * @brief Standalone NPU vs CPU benchmark for Kokoro TTS
 *
 * This function creates a temporary Kokoro TTS loader, runs the benchmark,
 * and cleans up. It does NOT require an existing TTS handle.
 *
 * @param model_path Path to Kokoro model directory
 * @param test_text Optional test text (uses default if NULL or empty)
 * @param out_json Output buffer for JSON result
 * @param json_size Size of the output buffer
 * @return RAC_SUCCESS on success, error code on failure
 */
__attribute__((visibility("default"), used))
extern "C" rac_result_t rac_tts_kokoro_run_standalone_benchmark(const char* model_path, const char* test_text,
                                                      char* out_json, size_t json_size) {
    ONNX_TTS_LOG("╔═══════════════════════════════════════════════════════════════╗");
    ONNX_TTS_LOG("║  STANDALONE KOKORO NPU vs CPU BENCHMARK                       ║");
    ONNX_TTS_LOG("╚═══════════════════════════════════════════════════════════════╝");
    ONNX_TTS_LOG("Model path: %s", model_path ? model_path : "(null)");

    if (model_path == nullptr || out_json == nullptr || json_size == 0) {
        ONNX_TTS_ERR("Invalid parameters: model_path=%p, out_json=%p, json_size=%zu",
                    (void*)model_path, (void*)out_json, json_size);
        if (out_json && json_size > 0) {
            snprintf(out_json, json_size, "{\"success\":false,\"error\":\"Invalid parameters\"}");
        }
        return RAC_ERROR_NULL_POINTER;
    }

    // Create temporary Kokoro TTS loader
    auto kokoro_loader = std::make_unique<rac::onnx::KokoroTTSLoader>();

    // Configure for NNAPI (NPU)
    rac::onnx::KokoroConfig config;
    config.num_threads = 4;
    config.enable_profiling = false;
#if RAC_NNAPI_AVAILABLE
    config.npu_backend = rac::onnx::NPUBackend::NNAPI;
    memset(&config.nnapi_config, 0, sizeof(config.nnapi_config));
    config.nnapi_config.enabled = RAC_TRUE;
    config.nnapi_config.use_fp16 = RAC_FALSE;
    config.nnapi_config.use_nchw = RAC_TRUE;
    config.nnapi_config.cpu_disabled = RAC_FALSE;  // Allow CPU fallback for optimal hybrid NPU/CPU execution (1.48x speedup)
    config.nnapi_config.min_api_level = 27;
    ONNX_TTS_LOG("NNAPI backend enabled for benchmark (HYBRID MODE - optimal performance)");
#else
    config.npu_backend = rac::onnx::NPUBackend::CPU_ONLY;
    ONNX_TTS_LOG("NNAPI not available, using CPU");
#endif

    // Load the model
    ONNX_TTS_LOG("Loading Kokoro model for benchmark...");
    rac_result_t load_result = kokoro_loader->load(model_path, config);

    if (load_result != RAC_SUCCESS) {
        ONNX_TTS_ERR("Failed to load Kokoro model: %d", load_result);
        snprintf(out_json, json_size,
                "{\"success\":false,\"error\":\"Failed to load model: %d\",\"npu_available\":false}",
                load_result);
        return load_result;
    }

    bool npu_active_on_load = kokoro_loader->is_npu_active();
    ONNX_TTS_LOG("Model loaded. NPU active: %s", npu_active_on_load ? "YES" : "NO");

    // Run the benchmark
    ONNX_TTS_LOG("Running benchmark...");
    std::string text = (test_text != nullptr && test_text[0] != '\0') ? test_text : "";
    rac::onnx::KokoroBenchmarkResult result = kokoro_loader->run_benchmark(text);

    // Cleanup
    kokoro_loader->unload();
    kokoro_loader.reset();

    // Format result as JSON
    snprintf(out_json, json_size,
        "{"
        "\"success\":%s,"
        "\"npu_available\":%s,"
        "\"npu_is_faster\":%s,"
        "\"npu_inference_ms\":%.2f,"
        "\"cpu_inference_ms\":%.2f,"
        "\"audio_duration_ms\":%.2f,"
        "\"npu_rtf\":%.2f,"
        "\"cpu_rtf\":%.2f,"
        "\"speedup\":%.2f,"
        "\"audio_samples\":%zu,"
        "\"sample_rate\":%d,"
        "\"num_tokens\":%zu,"
        "\"test_text\":\"%s\","
        "\"error\":\"%s\""
        "}",
        result.success ? "true" : "false",
        result.npu_available ? "true" : "false",
        result.npu_is_faster ? "true" : "false",
        result.npu_inference_ms,
        result.cpu_inference_ms,
        result.audio_duration_ms,
        result.npu_rtf,
        result.cpu_rtf,
        result.speedup,
        result.audio_samples,
        result.sample_rate,
        result.num_tokens,
        result.test_text.substr(0, 50).c_str(),  // Truncate for JSON
        result.error_message.c_str()
    );

    ONNX_TTS_LOG("╔═══════════════════════════════════════════════════════════════╗");
    ONNX_TTS_LOG("║  BENCHMARK COMPLETE                                           ║");
    ONNX_TTS_LOG("╠═══════════════════════════════════════════════════════════════╣");
    ONNX_TTS_LOG("║  NPU: %.2f ms (RTF: %.2fx)                                    ║", result.npu_inference_ms, result.npu_rtf);
    ONNX_TTS_LOG("║  CPU: %.2f ms (RTF: %.2fx)                                    ║", result.cpu_inference_ms, result.cpu_rtf);
    ONNX_TTS_LOG("║  Speedup: %.2fx %s                                           ║",
               result.speedup, result.npu_is_faster ? "(NPU faster)" : "(CPU faster)");
    ONNX_TTS_LOG("╚═══════════════════════════════════════════════════════════════╝");

    return result.success ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
}
