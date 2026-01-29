/**
 * @file wakeword_onnx.cpp
 * @brief ONNX Backend for Wake Word Detection
 *
 * Implements wake word detection using:
 * - openWakeWord ONNX models for wake word classification
 * - Existing rac_vad_onnx for voice activity detection (Silero VAD)
 *
 * Architecture:
 * 1. Audio input (16kHz, mono, float32)
 * 2. Optional: VAD pre-filtering using existing rac_vad_onnx (Silero VAD)
 * 3. Feature embedding extraction (openWakeWord embedding model)
 * 4. Wake word classification (per-keyword model)
 *
 * Note: This reuses the existing Silero VAD implementation from rac_vad_onnx.h
 * rather than duplicating VAD code.
 */

#include "rac/backends/rac_wakeword_onnx.h"
#include "rac/backends/rac_vad_onnx.h"  // Reuse existing VAD implementation
#include "rac/core/rac_logger.h"

#ifdef RAC_HAS_ONNX
#include <onnxruntime_cxx_api.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace rac {
namespace backends {
namespace onnx {

// =============================================================================
// CONSTANTS
// =============================================================================

static constexpr int VAD_FRAME_SAMPLES = 512;      // 32ms @ 16kHz for Silero
static constexpr float VAD_THRESHOLD = 0.5f;

// =============================================================================
// INTERNAL TYPES
// =============================================================================

struct WakewordModel {
    std::string model_id;
    std::string wake_word;
    std::string model_path;
    float threshold = 0.5f;

#ifdef RAC_HAS_ONNX
    std::unique_ptr<Ort::Session> session;
#endif
};

struct WakewordOnnxBackend {
    // Configuration
    rac_wakeword_onnx_config_t config;

    // State
    bool initialized = false;
    float global_threshold = 0.5f;

    // ONNX Runtime
#ifdef RAC_HAS_ONNX
    std::unique_ptr<Ort::Env> env;
    std::unique_ptr<Ort::SessionOptions> session_options;
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(
        OrtArenaAllocator, OrtMemTypeDefault);

    // Shared models for openWakeWord
    std::unique_ptr<Ort::Session> embedding_session;
    std::unique_ptr<Ort::Session> melspec_session;
#endif

    // Reuse existing VAD implementation (Silero VAD)
    rac_handle_t vad_handle = nullptr;
    bool vad_loaded = false;

    // Wake word models
    std::vector<WakewordModel> models;

    // Audio buffer
    std::vector<float> audio_buffer;
    std::vector<float> embedding_buffer;

    // Thread safety
    std::mutex mutex;
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static WakewordOnnxBackend* get_backend(rac_handle_t handle) {
    return static_cast<WakewordOnnxBackend*>(handle);
}

static bool is_valid_handle(rac_handle_t handle) {
    return handle != nullptr;
}

#ifdef RAC_HAS_ONNX

static Ort::SessionOptions create_session_options(int num_threads, bool optimize) {
    Ort::SessionOptions options;

    if (num_threads > 0) {
        options.SetIntraOpNumThreads(num_threads);
        options.SetInterOpNumThreads(num_threads);
    }

    if (optimize) {
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    }

    return options;
}

// Compute embedding from audio features
static bool compute_embedding(WakewordOnnxBackend* backend,
                               const float* features,
                               size_t num_features,
                               std::vector<float>& out_embedding) {
    if (!backend->embedding_session) {
        return false;
    }

    try {
        // Input shape: [batch, features]
        std::vector<int64_t> input_shape = {1, static_cast<int64_t>(num_features)};

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            backend->memory_info,
            const_cast<float*>(features),
            num_features,
            input_shape.data(),
            input_shape.size()
        );

        const char* input_names[] = {"input"};
        const char* output_names[] = {"output"};

        auto outputs = backend->embedding_session->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1
        );

        // Get output
        auto& output_tensor = outputs[0];
        auto output_info = output_tensor.GetTensorTypeAndShapeInfo();
        size_t output_size = output_info.GetElementCount();

        const float* output_data = output_tensor.GetTensorData<float>();
        out_embedding.assign(output_data, output_data + output_size);

        return true;
    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR("WakeWordONNX", "Embedding error: %s", e.what());
        return false;
    }
}

// Run wake word classifier
static float run_classifier(WakewordOnnxBackend* backend,
                            WakewordModel& model,
                            const std::vector<float>& embedding) {
    if (!model.session) {
        return 0.0f;
    }

    try {
        std::vector<int64_t> input_shape = {1, static_cast<int64_t>(embedding.size())};

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            backend->memory_info,
            const_cast<float*>(embedding.data()),
            embedding.size(),
            input_shape.data(),
            input_shape.size()
        );

        const char* input_names[] = {"input"};
        const char* output_names[] = {"output"};

        auto outputs = model.session->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1
        );

        // Get classification score (sigmoid output)
        const float* score = outputs[0].GetTensorData<float>();
        return *score;
    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR("WakeWordONNX", "Classifier error for %s: %s",
                      model.model_id.c_str(), e.what());
        return 0.0f;
    }
}

// Run VAD using existing rac_vad_onnx implementation
static bool run_vad(WakewordOnnxBackend* backend,
                    const float* samples,
                    size_t num_samples,
                    bool* out_is_speech) {
    if (!backend->vad_handle || !backend->vad_loaded) {
        *out_is_speech = true;  // Assume speech if no VAD
        return true;
    }

    rac_bool_t is_speech = RAC_TRUE;
    rac_result_t result = rac_vad_onnx_process(
        backend->vad_handle,
        samples,
        num_samples,
        &is_speech
    );

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("WakeWordONNX", "VAD process error: %d", result);
        *out_is_speech = true;  // Assume speech on error
        return false;
    }

    *out_is_speech = (is_speech == RAC_TRUE);
    return true;
}

#endif // RAC_HAS_ONNX

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

RAC_ONNX_API rac_result_t rac_wakeword_onnx_create(
    const rac_wakeword_onnx_config_t* config,
    rac_handle_t* out_handle) {

    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#ifndef RAC_HAS_ONNX
    RAC_LOG_ERROR("WakeWordONNX", "ONNX Runtime not available");
    return RAC_ERROR_NOT_IMPLEMENTED;
#else

    auto* backend = new (std::nothrow) WakewordOnnxBackend();
    if (!backend) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Apply configuration
    if (config) {
        backend->config = *config;
    } else {
        backend->config = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    }

    backend->global_threshold = backend->config.threshold;

    try {
        // Initialize ONNX Runtime
        backend->env = std::make_unique<Ort::Env>(
            ORT_LOGGING_LEVEL_WARNING, "WakeWord");

        backend->session_options = std::make_unique<Ort::SessionOptions>(
            create_session_options(backend->config.num_threads,
                                   backend->config.enable_optimization == RAC_TRUE));

        backend->initialized = true;
        *out_handle = static_cast<rac_handle_t>(backend);

        RAC_LOG_INFO("WakeWordONNX", "Created backend (threads=%d)",
                     backend->config.num_threads);

        return RAC_SUCCESS;
    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR("WakeWordONNX", "Failed to create: %s", e.what());
        delete backend;
        return RAC_ERROR_WAKEWORD_NOT_INITIALIZED;
    }

#endif
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_init_shared_models(
    rac_handle_t handle,
    const char* embedding_model_path,
    const char* melspec_model_path) {

#ifndef RAC_HAS_ONNX
    return RAC_ERROR_NOT_IMPLEMENTED;
#else

    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    try {
        // Load embedding model (required)
        if (embedding_model_path) {
            backend->embedding_session = std::make_unique<Ort::Session>(
                *backend->env, embedding_model_path, *backend->session_options);
            RAC_LOG_INFO("WakeWordONNX", "Loaded embedding model: %s",
                         embedding_model_path);
        }

        // Load melspec model (optional)
        if (melspec_model_path) {
            backend->melspec_session = std::make_unique<Ort::Session>(
                *backend->env, melspec_model_path, *backend->session_options);
            RAC_LOG_INFO("WakeWordONNX", "Loaded melspec model: %s",
                         melspec_model_path);
        }

        return RAC_SUCCESS;
    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR("WakeWordONNX", "Failed to load shared models: %s", e.what());
        return RAC_ERROR_WAKEWORD_MODEL_LOAD_FAILED;
    }

#endif
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_load_model(
    rac_handle_t handle,
    const char* model_path,
    const char* model_id,
    const char* wake_word) {

#ifndef RAC_HAS_ONNX
    return RAC_ERROR_NOT_IMPLEMENTED;
#else

    if (!is_valid_handle(handle) || !model_path || !model_id || !wake_word) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Check for duplicate
    for (const auto& model : backend->models) {
        if (model.model_id == model_id) {
            RAC_LOG_WARNING("WakeWordONNX", "Model already loaded: %s", model_id);
            return RAC_SUCCESS;
        }
    }

    try {
        WakewordModel model;
        model.model_id = model_id;
        model.wake_word = wake_word;
        model.model_path = model_path;
        model.threshold = backend->global_threshold;

        model.session = std::make_unique<Ort::Session>(
            *backend->env, model_path, *backend->session_options);

        backend->models.push_back(std::move(model));

        RAC_LOG_INFO("WakeWordONNX", "Loaded model: %s ('%s')", model_id, wake_word);

        return RAC_SUCCESS;
    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR("WakeWordONNX", "Failed to load model %s: %s",
                      model_id, e.what());
        return RAC_ERROR_WAKEWORD_MODEL_LOAD_FAILED;
    }

#endif
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_load_vad(
    rac_handle_t handle,
    const char* vad_model_path) {

    if (!is_valid_handle(handle) || !vad_model_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Destroy existing VAD if any
    if (backend->vad_handle) {
        rac_vad_onnx_destroy(backend->vad_handle);
        backend->vad_handle = nullptr;
        backend->vad_loaded = false;
    }

    // Create VAD using existing rac_vad_onnx implementation
    rac_vad_onnx_config_t vad_config = RAC_VAD_ONNX_CONFIG_DEFAULT;
    vad_config.sample_rate = backend->config.sample_rate;
    vad_config.energy_threshold = VAD_THRESHOLD;

    rac_result_t result = rac_vad_onnx_create(
        vad_model_path,
        &vad_config,
        &backend->vad_handle
    );

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("WakeWordONNX", "Failed to create VAD: %d", result);
        return RAC_ERROR_WAKEWORD_MODEL_LOAD_FAILED;
    }

    backend->vad_loaded = true;
    RAC_LOG_INFO("WakeWordONNX", "Loaded VAD model: %s", vad_model_path);

    return RAC_SUCCESS;
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_process(
    rac_handle_t handle,
    const float* samples,
    size_t num_samples,
    int32_t* out_detected,
    float* out_confidence) {

    rac_bool_t vad_speech;
    float vad_conf;

    return rac_wakeword_onnx_process_with_vad(
        handle, samples, num_samples,
        out_detected, out_confidence,
        &vad_speech, &vad_conf);
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_process_with_vad(
    rac_handle_t handle,
    const float* samples,
    size_t num_samples,
    int32_t* out_detected,
    float* out_confidence,
    rac_bool_t* out_vad_speech,
    float* out_vad_confidence) {

#ifndef RAC_HAS_ONNX
    return RAC_ERROR_NOT_IMPLEMENTED;
#else

    if (!is_valid_handle(handle) || !samples || num_samples == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Initialize outputs
    if (out_detected) *out_detected = -1;
    if (out_confidence) *out_confidence = 0.0f;
    if (out_vad_speech) *out_vad_speech = RAC_TRUE;
    if (out_vad_confidence) *out_vad_confidence = 1.0f;

    // Run VAD using existing rac_vad_onnx if loaded
    bool is_speech = true;
    if (backend->vad_loaded && backend->vad_handle) {
        run_vad(backend, samples,
                std::min(num_samples, (size_t)VAD_FRAME_SAMPLES),
                &is_speech);

        if (out_vad_speech) *out_vad_speech = is_speech ? RAC_TRUE : RAC_FALSE;
        // Note: rac_vad_onnx doesn't expose confidence, so we use binary result
        if (out_vad_confidence) *out_vad_confidence = is_speech ? 1.0f : 0.0f;

        // Skip wake word detection if no speech
        if (!is_speech) {
            return RAC_SUCCESS;
        }
    }

    // Compute embedding (simplified - real impl would use melspec)
    std::vector<float> embedding;
    if (backend->embedding_session) {
        if (!compute_embedding(backend, samples, num_samples, embedding)) {
            return RAC_SUCCESS;  // Continue without detection
        }
    } else {
        // No embedding model - use raw audio as features
        embedding.assign(samples, samples + num_samples);
    }

    // Run each wake word classifier
    float max_confidence = 0.0f;
    int32_t detected_index = -1;

    for (size_t i = 0; i < backend->models.size(); ++i) {
        auto& model = backend->models[i];
        float score = run_classifier(backend, model, embedding);

        if (score > max_confidence) {
            max_confidence = score;
            if (score >= model.threshold) {
                detected_index = static_cast<int32_t>(i);
            }
        }
    }

    if (out_detected) *out_detected = detected_index;
    if (out_confidence) *out_confidence = max_confidence;

    if (detected_index >= 0) {
        RAC_LOG_DEBUG("WakeWordONNX", "Detected: %s (%.2f)",
                      backend->models[detected_index].wake_word.c_str(),
                      max_confidence);
    }

    return RAC_SUCCESS;

#endif
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_set_threshold(
    rac_handle_t handle,
    float threshold) {

    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (threshold < 0.0f || threshold > 1.0f) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    backend->global_threshold = threshold;

    // Update all models that don't have override
    for (auto& model : backend->models) {
        model.threshold = threshold;
    }

    return RAC_SUCCESS;
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_reset(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Reset VAD using existing API
    if (backend->vad_handle && backend->vad_loaded) {
        rac_vad_onnx_reset(backend->vad_handle);
    }

#ifdef RAC_HAS_ONNX
    // Clear audio buffer
    backend->audio_buffer.clear();
    backend->embedding_buffer.clear();
#endif

    return RAC_SUCCESS;
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_unload_model(
    rac_handle_t handle,
    const char* model_id) {

    if (!is_valid_handle(handle) || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#ifdef RAC_HAS_ONNX
    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    auto it = std::find_if(backend->models.begin(), backend->models.end(),
                           [model_id](const WakewordModel& m) {
                               return m.model_id == model_id;
                           });

    if (it == backend->models.end()) {
        return RAC_ERROR_WAKEWORD_MODEL_NOT_FOUND;
    }

    backend->models.erase(it);
#endif

    return RAC_SUCCESS;
}

RAC_ONNX_API void rac_wakeword_onnx_destroy(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return;
    }

    auto* backend = get_backend(handle);

    // Destroy VAD handle if loaded
    if (backend->vad_handle) {
        rac_vad_onnx_destroy(backend->vad_handle);
        backend->vad_handle = nullptr;
    }

    delete backend;
}

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

static bool g_wakeword_onnx_registered = false;

RAC_ONNX_API rac_result_t rac_backend_wakeword_onnx_register(void) {
    if (g_wakeword_onnx_registered) {
        return RAC_SUCCESS;
    }

    // TODO: Register with backend registry
    g_wakeword_onnx_registered = true;
    RAC_LOG_INFO("WakeWordONNX", "Backend registered");

    return RAC_SUCCESS;
}

RAC_ONNX_API rac_result_t rac_backend_wakeword_onnx_unregister(void) {
    if (!g_wakeword_onnx_registered) {
        return RAC_SUCCESS;
    }

    // TODO: Unregister from backend registry
    g_wakeword_onnx_registered = false;
    RAC_LOG_INFO("WakeWordONNX", "Backend unregistered");

    return RAC_SUCCESS;
}

} // extern "C"

} // namespace onnx
} // namespace backends
} // namespace rac
