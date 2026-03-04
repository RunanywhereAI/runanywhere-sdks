/**
 * @file wakeword_onnx.cpp
 * @brief ONNX Backend for Wake Word Detection using openWakeWord
 *
 * Implements the complete openWakeWord 3-stage pipeline:
 * 1. Audio -> Melspectrogram (melspectrogram.onnx)
 * 2. Melspectrogram -> Embeddings (embedding_model.onnx) with 76-frame windowing
 * 3. Embeddings -> Classification (wake word model, e.g., hey_jarvis_v0.1.onnx)
 *
 * Reference: https://github.com/dscripka/openWakeWord
 *
 * Audio Requirements:
 * - Sample rate: 16000 Hz
 * - Format: Float32 normalized to [-1.0, 1.0] or Int16
 * - Channels: Mono
 * - Frame size: 1280 samples (80ms) for optimal processing
 */

#include "rac/backends/rac_wakeword_onnx.h"
#include "rac/backends/rac_vad_onnx.h"
#include "rac/core/rac_logger.h"

#ifdef RAC_HAS_ONNX
#include <onnxruntime_cxx_api.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace rac {
namespace backends {
namespace onnx {

// =============================================================================
// CONSTANTS (from openWakeWord Python implementation)
// =============================================================================

static const char* LOG_TAG = "WakeWordONNX";

// Audio parameters
static constexpr int SAMPLE_RATE = 16000;
static constexpr int FRAME_SIZE = 1280;              // 80ms @ 16kHz (required by openWakeWord)

// Melspectrogram parameters
static constexpr int MELSPEC_BINS = 32;              // Number of mel frequency bins
static constexpr int MELSPEC_WINDOW_SIZE = 76;       // Frames needed for one embedding
static constexpr int MELSPEC_STRIDE = 8;             // Stride between embedding windows

// Embedding parameters
static constexpr int EMBEDDING_DIM = 96;             // Output dimension of embedding model

// Buffer limits
static constexpr size_t MAX_MELSPEC_FRAMES = 970;    // ~10 seconds of audio
static constexpr size_t MAX_EMBEDDING_HISTORY = 120; // ~10 seconds of embeddings
static constexpr size_t DEFAULT_CLASSIFIER_EMBEDDINGS = 16;  // Typical wake word model input

// Audio context overlap (CRITICAL: required for proper melspectrogram computation)
// The openWakeWord Python implementation includes 480 extra samples (160*3 = 30ms)
// of previous audio when computing melspectrogram for frame continuity
static constexpr int MELSPEC_CONTEXT_SAMPLES = 160 * 3;  // 480 samples = 30ms overlap

// VAD parameters
static constexpr int VAD_FRAME_SAMPLES = 512;
static constexpr float VAD_THRESHOLD = 0.5f;

// =============================================================================
// INTERNAL TYPES
// =============================================================================

struct WakewordModel {
    std::string model_id;
    std::string wake_word;
    std::string model_path;
    float threshold = 0.5f;
    int num_embeddings = DEFAULT_CLASSIFIER_EMBEDDINGS;  // Read from model input shape

#ifdef RAC_HAS_ONNX
    std::unique_ptr<Ort::Session> session;
    std::string input_name;
    std::string output_name;
#endif
};

struct WakewordOnnxBackend {
    // Configuration
    rac_wakeword_onnx_config_t config;

    // State
    bool initialized = false;
    float global_threshold = 0.5f;

#ifdef RAC_HAS_ONNX
    // ONNX Runtime
    std::unique_ptr<Ort::Env> env;
    std::unique_ptr<Ort::SessionOptions> session_options;
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(
        OrtArenaAllocator, OrtMemTypeDefault);
    Ort::AllocatorWithDefaultOptions allocator;

    // Stage 1: Melspectrogram model
    std::unique_ptr<Ort::Session> melspec_session;
    std::string melspec_input_name;
    std::string melspec_output_name;

    // Stage 2: Embedding model
    std::unique_ptr<Ort::Session> embedding_session;
    std::string embedding_input_name;
    std::string embedding_output_name;
#endif

    // Optional VAD pre-filtering
    rac_handle_t vad_handle = nullptr;
    bool vad_loaded = false;

    // Wake word classifier models
    std::vector<WakewordModel> models;

    // Streaming buffers
    std::vector<float> audio_buffer;                      // Accumulate to FRAME_SIZE
    std::vector<float> audio_context_buffer;              // Keep last MELSPEC_CONTEXT_SAMPLES for overlap
    std::deque<std::vector<float>> melspec_buffer;        // Each entry is [MELSPEC_BINS]
    std::deque<std::vector<float>> embedding_buffer;      // Each entry is [EMBEDDING_DIM]
    size_t last_melspec_embedding_index = 0;              // Track which melspec frames we've embedded
    bool buffers_initialized = false;                     // Track if buffers have been pre-filled

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

/**
 * Initialize streaming buffers with padding data.
 * This matches Python's openWakeWord initialization which pre-fills:
 * - melspectrogram_buffer with np.ones((76, 32))
 * - feature_buffer with embeddings from 4 seconds of random audio
 *
 * This ensures the classifier can produce valid outputs immediately
 * rather than requiring ~1 second of warmup audio.
 */
static void initialize_streaming_buffers(WakewordOnnxBackend* backend) {
    if (backend->buffers_initialized) {
        return;
    }

    // Initialize melspec buffer with 76 frames of ones (matching Python)
    // This provides initial context for the embedding model
    for (int i = 0; i < MELSPEC_WINDOW_SIZE; ++i) {
        std::vector<float> frame(MELSPEC_BINS, 1.0f);  // np.ones((76, 32))
        backend->melspec_buffer.push_back(std::move(frame));
    }

    // Initialize audio context buffer (empty, will be filled on first process)
    backend->audio_context_buffer.clear();
    backend->audio_context_buffer.reserve(MELSPEC_CONTEXT_SAMPLES);

    // Reset tracking index to start of initialized buffer
    backend->last_melspec_embedding_index = 0;

    backend->buffers_initialized = true;

    RAC_LOG_INFO(LOG_TAG, "Initialized streaming buffers (melspec_frames=%zu)",
                 backend->melspec_buffer.size());
}

// =============================================================================
// STAGE 1: MELSPECTROGRAM COMPUTATION
// =============================================================================

/**
 * Compute mel spectrogram from raw audio.
 * Input: [1, N] raw audio samples
 * Output: [num_frames, 32] mel spectrogram with transform applied
 */
static bool compute_melspectrogram(WakewordOnnxBackend* backend,
                                   const std::vector<float>& audio,
                                   std::vector<std::vector<float>>& out_melspec) {
    if (!backend->melspec_session || audio.empty()) {
        return false;
    }

    try {
        // Input shape: [1, num_samples]
        std::vector<int64_t> input_shape = {1, static_cast<int64_t>(audio.size())};

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            backend->memory_info,
            const_cast<float*>(audio.data()),
            audio.size(),
            input_shape.data(),
            input_shape.size()
        );

        const char* input_names[] = {backend->melspec_input_name.c_str()};
        const char* output_names[] = {backend->melspec_output_name.c_str()};

        auto outputs = backend->melspec_session->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1
        );

        // Get output shape and data
        auto& output_tensor = outputs[0];
        auto shape_info = output_tensor.GetTensorTypeAndShapeInfo();
        auto shape = shape_info.GetShape();

        // Output is typically [num_frames, 32] or [1, num_frames, 32]
        const float* output_data = output_tensor.GetTensorData<float>();
        size_t total_elements = shape_info.GetElementCount();

        int num_frames = 0;
        int num_bins = MELSPEC_BINS;

        if (shape.size() == 2) {
            num_frames = static_cast<int>(shape[0]);
            num_bins = static_cast<int>(shape[1]);
        } else if (shape.size() == 3) {
            num_frames = static_cast<int>(shape[1]);
            num_bins = static_cast<int>(shape[2]);
        } else {
            // Fallback: assume flat array with 32 bins per frame
            num_frames = static_cast<int>(total_elements / MELSPEC_BINS);
        }

        // Extract frames and apply openWakeWord transform: (x / 10) + 2
        out_melspec.clear();
        out_melspec.reserve(num_frames);

        for (int f = 0; f < num_frames; ++f) {
            std::vector<float> frame(num_bins);
            for (int b = 0; b < num_bins; ++b) {
                float val = output_data[f * num_bins + b];
                // Apply openWakeWord transform
                frame[b] = (val / 10.0f) + 2.0f;
            }
            out_melspec.push_back(std::move(frame));
        }

        return true;

    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Melspectrogram error: %s", e.what());
        return false;
    }
}

// =============================================================================
// STAGE 2: EMBEDDING COMPUTATION
// =============================================================================

/**
 * Compute embedding from a 76-frame melspectrogram window.
 * Input: [1, 76, 32, 1] melspectrogram window
 * Output: [96] embedding vector
 */
static bool compute_single_embedding(WakewordOnnxBackend* backend,
                                     const float* melspec_window,
                                     std::vector<float>& out_embedding) {
    if (!backend->embedding_session) {
        return false;
    }

    try {
        // Input shape: [1, 76, 32, 1] (batch, frames, bins, channel)
        std::vector<int64_t> input_shape = {1, MELSPEC_WINDOW_SIZE, MELSPEC_BINS, 1};
        size_t input_size = MELSPEC_WINDOW_SIZE * MELSPEC_BINS;

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            backend->memory_info,
            const_cast<float*>(melspec_window),
            input_size,
            input_shape.data(),
            input_shape.size()
        );

        const char* input_names[] = {backend->embedding_input_name.c_str()};
        const char* output_names[] = {backend->embedding_output_name.c_str()};

        auto outputs = backend->embedding_session->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1
        );

        // Get output (typically [1, 96] or [96])
        auto& output_tensor = outputs[0];
        const float* output_data = output_tensor.GetTensorData<float>();
        auto shape_info = output_tensor.GetTensorTypeAndShapeInfo();
        size_t output_size = shape_info.GetElementCount();

        // Take first EMBEDDING_DIM elements (usually 96)
        size_t dim = std::min(output_size, (size_t)EMBEDDING_DIM);
        out_embedding.assign(output_data, output_data + dim);

        // Pad if necessary
        while (out_embedding.size() < EMBEDDING_DIM) {
            out_embedding.push_back(0.0f);
        }

        return true;

    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Embedding error: %s", e.what());
        return false;
    }
}

/**
 * Generate embeddings from melspectrogram buffer using sliding windows.
 * Window size: 76 frames, Stride: 8 frames
 */
static void generate_embeddings_from_melspec(WakewordOnnxBackend* backend) {
    if (!backend->embedding_session) {
        return;
    }

    size_t melspec_size = backend->melspec_buffer.size();

    // Need at least MELSPEC_WINDOW_SIZE frames
    if (melspec_size < MELSPEC_WINDOW_SIZE) {
        return;
    }

    // Prepare window buffer (76 * 32 = 2432 floats)
    std::vector<float> window_data(MELSPEC_WINDOW_SIZE * MELSPEC_BINS);

    // Calculate which windows we haven't processed yet
    // We process windows starting at stride intervals
    size_t start_index = backend->last_melspec_embedding_index;

    // Process new windows
    while (start_index + MELSPEC_WINDOW_SIZE <= melspec_size) {
        // Extract window from melspec buffer
        for (int i = 0; i < MELSPEC_WINDOW_SIZE; ++i) {
            const auto& frame = backend->melspec_buffer[start_index + i];
            for (int b = 0; b < MELSPEC_BINS && b < (int)frame.size(); ++b) {
                window_data[i * MELSPEC_BINS + b] = frame[b];
            }
        }

        // Compute embedding for this window
        std::vector<float> embedding;
        if (compute_single_embedding(backend, window_data.data(), embedding)) {
            backend->embedding_buffer.push_back(std::move(embedding));

            // Maintain max history
            while (backend->embedding_buffer.size() > MAX_EMBEDDING_HISTORY) {
                backend->embedding_buffer.pop_front();
            }
        }

        start_index += MELSPEC_STRIDE;
    }

    // Update tracking index
    backend->last_melspec_embedding_index = start_index;
}

// =============================================================================
// STAGE 3: WAKE WORD CLASSIFICATION
// =============================================================================

/**
 * Run wake word classifier on embedding history.
 * Input: [1, num_embeddings, 96]
 * Output: probability score [0.0, 1.0]
 */
static float run_classifier(WakewordOnnxBackend* backend,
                            WakewordModel& model) {
    if (!model.session || backend->embedding_buffer.empty()) {
        return 0.0f;
    }

    try {
        int num_embeddings = model.num_embeddings;
        int available = static_cast<int>(backend->embedding_buffer.size());

        // Need at least num_embeddings to classify
        if (available < num_embeddings) {
            return 0.0f;
        }

        // Prepare input: take last num_embeddings from buffer
        std::vector<float> input_data;
        input_data.reserve(num_embeddings * EMBEDDING_DIM);

        int start_idx = available - num_embeddings;
        for (int i = start_idx; i < available; ++i) {
            const auto& emb = backend->embedding_buffer[i];
            input_data.insert(input_data.end(), emb.begin(), emb.end());
        }

        // Input shape: [1, num_embeddings, 96]
        std::vector<int64_t> input_shape = {1, static_cast<int64_t>(num_embeddings), EMBEDDING_DIM};

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            backend->memory_info,
            input_data.data(),
            input_data.size(),
            input_shape.data(),
            input_shape.size()
        );

        const char* input_names[] = {model.input_name.c_str()};
        const char* output_names[] = {model.output_name.c_str()};

        auto outputs = model.session->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1
        );

        // Output is typically [1, 1, 1] or [1, 1] - take first value
        const float* score = outputs[0].GetTensorData<float>();
        return *score;

    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Classifier error for %s: %s",
                      model.model_id.c_str(), e.what());
        return 0.0f;
    }
}

// =============================================================================
// VAD INTEGRATION
// =============================================================================

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
        std::min(num_samples, (size_t)VAD_FRAME_SAMPLES),
        &is_speech
    );

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG, "VAD process error: %d", result);
        *out_is_speech = true;
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
    RAC_LOG_ERROR(LOG_TAG, "ONNX Runtime not available");
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

        RAC_LOG_INFO(LOG_TAG, "Created backend (threads=%d, frame_size=%d)",
                     backend->config.num_threads, FRAME_SIZE);

        return RAC_SUCCESS;

    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to create ONNX environment: %s", e.what());
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
        // Load melspectrogram model (required for proper pipeline)
        if (melspec_model_path) {
            backend->melspec_session = std::make_unique<Ort::Session>(
                *backend->env, melspec_model_path, *backend->session_options);

            // Get input/output names
            auto input_name = backend->melspec_session->GetInputNameAllocated(0, backend->allocator);
            auto output_name = backend->melspec_session->GetOutputNameAllocated(0, backend->allocator);
            backend->melspec_input_name = input_name.get();
            backend->melspec_output_name = output_name.get();

            RAC_LOG_INFO(LOG_TAG, "Loaded melspectrogram model: %s (input='%s', output='%s')",
                         melspec_model_path,
                         backend->melspec_input_name.c_str(),
                         backend->melspec_output_name.c_str());
        }

        // Load embedding model (required)
        if (embedding_model_path) {
            backend->embedding_session = std::make_unique<Ort::Session>(
                *backend->env, embedding_model_path, *backend->session_options);

            // Get input/output names
            auto input_name = backend->embedding_session->GetInputNameAllocated(0, backend->allocator);
            auto output_name = backend->embedding_session->GetOutputNameAllocated(0, backend->allocator);
            backend->embedding_input_name = input_name.get();
            backend->embedding_output_name = output_name.get();

            // Log input shape for debugging
            auto input_info = backend->embedding_session->GetInputTypeInfo(0);
            auto shape = input_info.GetTensorTypeAndShapeInfo().GetShape();
            std::string shape_str;
            for (size_t i = 0; i < shape.size(); ++i) {
                if (i > 0) shape_str += "x";
                shape_str += std::to_string(shape[i]);
            }

            RAC_LOG_INFO(LOG_TAG, "Loaded embedding model: %s (input='%s' shape=[%s], output='%s')",
                         embedding_model_path,
                         backend->embedding_input_name.c_str(),
                         shape_str.c_str(),
                         backend->embedding_output_name.c_str());
        }

        return RAC_SUCCESS;

    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to load shared models: %s", e.what());
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
            RAC_LOG_WARNING(LOG_TAG, "Model already loaded: %s", model_id);
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

        // Get input/output names
        auto input_name = model.session->GetInputNameAllocated(0, backend->allocator);
        auto output_name = model.session->GetOutputNameAllocated(0, backend->allocator);
        model.input_name = input_name.get();
        model.output_name = output_name.get();

        // Try to read num_embeddings from input shape
        auto input_info = model.session->GetInputTypeInfo(0);
        auto shape = input_info.GetTensorTypeAndShapeInfo().GetShape();
        // Shape is typically [1, num_embeddings, 96]
        if (shape.size() >= 2 && shape[1] > 0) {
            model.num_embeddings = static_cast<int>(shape[1]);
        } else {
            model.num_embeddings = DEFAULT_CLASSIFIER_EMBEDDINGS;
        }

        RAC_LOG_INFO(LOG_TAG, "Loaded wake word model: %s ('%s') - requires %d embeddings",
                     model_id, wake_word, model.num_embeddings);

        backend->models.push_back(std::move(model));

        return RAC_SUCCESS;

    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to load model %s: %s", model_id, e.what());
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
        RAC_LOG_ERROR(LOG_TAG, "Failed to create VAD: %d", result);
        return RAC_ERROR_WAKEWORD_MODEL_LOAD_FAILED;
    }

    backend->vad_loaded = true;
    RAC_LOG_INFO(LOG_TAG, "Loaded VAD model: %s", vad_model_path);

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

    // Check if we have the required models
    if (!backend->melspec_session || !backend->embedding_session) {
        // Fallback: can't process without melspec and embedding models
        RAC_LOG_DEBUG(LOG_TAG, "Missing melspec or embedding model, skipping detection");
        return RAC_SUCCESS;
    }

    if (backend->models.empty()) {
        RAC_LOG_DEBUG(LOG_TAG, "No wake word models loaded, skipping detection");
        return RAC_SUCCESS;
    }

    // Initialize streaming buffers on first call (matching Python's initialization)
    if (!backend->buffers_initialized) {
        initialize_streaming_buffers(backend);
    }

    // Optional: Run VAD pre-filtering
    bool is_speech = true;
    if (backend->vad_loaded && backend->vad_handle) {
        run_vad(backend, samples, num_samples, &is_speech);
        if (out_vad_speech) *out_vad_speech = is_speech ? RAC_TRUE : RAC_FALSE;
        if (out_vad_confidence) *out_vad_confidence = is_speech ? 1.0f : 0.0f;

        // Skip detection if no speech (but still accumulate audio)
        if (!is_speech) {
            // Still add to buffer for continuity, but don't run expensive detection
        }
    }

    // Step 1: Accumulate audio to FRAME_SIZE boundary
    backend->audio_buffer.insert(backend->audio_buffer.end(), samples, samples + num_samples);

    // Step 2: Process complete frames WITH context overlap
    // The Python implementation includes 480 extra samples (160*3) of previous audio
    // when computing melspectrogram for frame continuity at boundaries
    while (backend->audio_buffer.size() >= FRAME_SIZE) {
        // Build frame with context: [context_samples | new_frame_samples]
        std::vector<float> frame_with_context;
        frame_with_context.reserve(MELSPEC_CONTEXT_SAMPLES + FRAME_SIZE);

        // Add context from previous frame (if available)
        if (!backend->audio_context_buffer.empty()) {
            frame_with_context.insert(frame_with_context.end(),
                                     backend->audio_context_buffer.begin(),
                                     backend->audio_context_buffer.end());
        }

        // Add current frame samples
        frame_with_context.insert(frame_with_context.end(),
                                 backend->audio_buffer.begin(),
                                 backend->audio_buffer.begin() + FRAME_SIZE);

        // Update context buffer with last MELSPEC_CONTEXT_SAMPLES of current frame
        // This will be used as context for the NEXT frame
        backend->audio_context_buffer.clear();
        if (FRAME_SIZE >= MELSPEC_CONTEXT_SAMPLES) {
            backend->audio_context_buffer.insert(
                backend->audio_context_buffer.end(),
                backend->audio_buffer.begin() + (FRAME_SIZE - MELSPEC_CONTEXT_SAMPLES),
                backend->audio_buffer.begin() + FRAME_SIZE);
        } else {
            // Frame is smaller than context size - use all of it
            backend->audio_context_buffer.insert(
                backend->audio_context_buffer.end(),
                backend->audio_buffer.begin(),
                backend->audio_buffer.begin() + FRAME_SIZE);
        }

        // Remove processed samples from audio buffer
        backend->audio_buffer.erase(backend->audio_buffer.begin(),
                                    backend->audio_buffer.begin() + FRAME_SIZE);

        // Step 3: Compute melspectrogram for frame WITH context
        std::vector<std::vector<float>> melspec_frames;
        if (!compute_melspectrogram(backend, frame_with_context, melspec_frames)) {
            continue;  // Skip on error
        }

        // Step 4: Add melspec frames to buffer
        for (auto& mf : melspec_frames) {
            backend->melspec_buffer.push_back(std::move(mf));
        }

        // Maintain max buffer size
        while (backend->melspec_buffer.size() > MAX_MELSPEC_FRAMES) {
            backend->melspec_buffer.pop_front();
            // Adjust tracking index
            if (backend->last_melspec_embedding_index > 0) {
                backend->last_melspec_embedding_index--;
            }
        }

        // Step 5: Generate embeddings from new melspec data
        generate_embeddings_from_melspec(backend);
    }

    // Step 6: Run classifiers if we have enough embeddings
    float max_confidence = 0.0f;
    int32_t detected_index = -1;

    for (size_t i = 0; i < backend->models.size(); ++i) {
        auto& model = backend->models[i];

        // Check if we have enough embeddings for this model
        if ((int)backend->embedding_buffer.size() < model.num_embeddings) {
            continue;
        }

        float score = run_classifier(backend, model);

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
        RAC_LOG_INFO(LOG_TAG, "DETECTED: '%s' (confidence=%.3f, threshold=%.3f)",
                     backend->models[detected_index].wake_word.c_str(),
                     max_confidence,
                     backend->models[detected_index].threshold);
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

    // Update all models
    for (auto& model : backend->models) {
        model.threshold = threshold;
    }

    RAC_LOG_INFO(LOG_TAG, "Set threshold to %.3f", threshold);

    return RAC_SUCCESS;
}

RAC_ONNX_API rac_result_t rac_wakeword_onnx_reset(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* backend = get_backend(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Reset VAD
    if (backend->vad_handle && backend->vad_loaded) {
        rac_vad_onnx_reset(backend->vad_handle);
    }

#ifdef RAC_HAS_ONNX
    // Clear all buffers
    backend->audio_buffer.clear();
    backend->audio_context_buffer.clear();
    backend->melspec_buffer.clear();
    backend->embedding_buffer.clear();
    backend->last_melspec_embedding_index = 0;
    backend->buffers_initialized = false;  // Will be re-initialized on next process call
#endif

    RAC_LOG_DEBUG(LOG_TAG, "Reset buffers");

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

    RAC_LOG_INFO(LOG_TAG, "Unloaded model: %s", model_id);
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

    RAC_LOG_INFO(LOG_TAG, "Destroyed backend");
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

    g_wakeword_onnx_registered = true;
    RAC_LOG_INFO(LOG_TAG, "Backend registered");

    return RAC_SUCCESS;
}

RAC_ONNX_API rac_result_t rac_backend_wakeword_onnx_unregister(void) {
    if (!g_wakeword_onnx_registered) {
        return RAC_SUCCESS;
    }

    g_wakeword_onnx_registered = false;
    RAC_LOG_INFO(LOG_TAG, "Backend unregistered");

    return RAC_SUCCESS;
}

} // extern "C"

} // namespace onnx
} // namespace backends
} // namespace rac
