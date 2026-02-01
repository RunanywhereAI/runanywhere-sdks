/**
 * @file kokoro_tts_loader.h
 * @brief Internal Kokoro TTS Loader Interface
 *
 * C++ implementation for Kokoro TTS model loading and inference.
 * This is an INTERNAL header - NOT exposed to the application layer.
 *
 * Kokoro models are auto-detected and loaded transparently through the
 * standard TTS API (rac_tts_create). The application never needs to know
 * whether it's using Kokoro or another TTS model.
 *
 * Key differences from Piper/VITS:
 *   - Piper: text → phonemes (internal) → mel spectrogram → waveform
 *   - Kokoro: token IDs (int64) + style vector (float32) + speed (int32) → waveform
 *
 * NPU Support Options:
 *   1. QNN EP (Qualcomm-specific): Direct NPU access via Hexagon DSP
 *      - Requires QNN SDK, potentially more optimized for Snapdragon
 *      - Can have version mismatch issues with device drivers
 *
 *   2. NNAPI EP (Vendor-agnostic): Android's Neural Networks API
 *      - Works on Qualcomm, Samsung, MediaTek, Google Tensor
 *      - Built into Android, no separate SDK needed
 *      - INT8 quantized models get best NPU acceleration
 *      - Recommende face
 d for broad device compatibility
 */

#ifndef RAC_KOKORO_TTS_LOADER_H
#define RAC_KOKORO_TTS_LOADER_H

// QNN DISABLED FOR NNAPI TESTING
// #include "rac/backends/rac_qnn_config.h"
#include "rac/backends/rac_nnapi_config.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#include <memory>
#include <string>
#include <vector>
#include <chrono>

// Forward declarations
struct OrtApi;
struct OrtEnv;
struct OrtSession;
struct OrtSessionOptions;
struct OrtValue;
struct OrtApiBase;

namespace rac {
namespace onnx {

// Forward declarations (conditionally compiled)
// QNN DISABLED FOR NNAPI TESTING
// #if RAC_QNN_AVAILABLE
// class QNNSessionManager;
// #endif

#if RAC_NNAPI_AVAILABLE
class NNAPISessionManager;
#endif

/**
 * @brief NPU backend preference for Kokoro TTS
 */
enum class NPUBackend {
    AUTO = 0,       // Auto-detect best available (NNAPI first, then QNN)
    CPU_ONLY = 1,   // Force CPU execution
    NNAPI = 2,      // Prefer NNAPI (vendor-agnostic)
    QNN = 3,        // Prefer QNN (Qualcomm-specific)
};

/**
 * @brief Kokoro model type (internal)
 */
enum class KokoroModelType {
    UNKNOWN = 0,
    UNIFIED = 1,   // Single model file (ISTFT-free, CPU-compatible)
    SPLIT = 2,     // Split encoder + vocoder (hybrid NPU+CPU)
};

/**
 * @brief Model quantization type for NPU routing
 *
 * INT8 quantized models get the best NPU acceleration via NNAPI.
 * FP32 models may fall back to CPU for unsupported ops.
 */
enum class KokoroQuantizationType {
    UNKNOWN = 0,
    FP32 = 1,      // Float32 precision (larger, may fall back to CPU)
    FP16 = 2,      // Float16 precision (QNN HTP compatible)
    INT8 = 3,      // INT8 quantized (best NNAPI NPU acceleration)
};

/**
 * @brief Kokoro model information (internal)
 */
struct KokoroModelInfo {
    KokoroModelType type = KokoroModelType::UNKNOWN;
    KokoroQuantizationType quantization = KokoroQuantizationType::UNKNOWN;
    std::string unified_path;
    std::string encoder_path;
    std::string vocoder_path;
    std::string tokenizer_path;
    std::string voices_path;
    bool has_tokenizer = false;
    bool has_voices = false;
    bool is_int8 = false;  // True if model is INT8 quantized (for easy checking)
};

/**
 * @brief Kokoro inference statistics (internal)
 */
struct KokoroStats {
    double total_inference_ms = 0;
    double npu_inference_ms = 0;
    double cpu_inference_ms = 0;
    double tokenization_ms = 0;
    int64_t total_inferences = 0;
    bool npu_active = false;
};

/**
 * @brief NPU vs CPU benchmark result
 *
 * Contains timing comparisons between NPU (NNAPI) and CPU-only execution
 * to verify that NPU acceleration is actually providing speedup.
 */
struct KokoroBenchmarkResult {
    // NPU timing (current session with NNAPI if available)
    double npu_inference_ms = 0;
    double npu_rtf = 0;  // Real-time factor (audio_duration / inference_time)
    bool npu_available = false;

    // CPU timing (separate CPU-only session)
    double cpu_inference_ms = 0;
    double cpu_rtf = 0;

    // Audio metrics
    double audio_duration_ms = 0;
    size_t audio_samples = 0;
    int32_t sample_rate = 24000;

    // Comparison metrics
    double speedup = 0;  // cpu_time / npu_time (> 1 means NPU is faster)
    bool npu_is_faster = false;

    // Input info
    std::string test_text;
    size_t num_tokens = 0;

    // Status
    bool success = false;
    std::string error_message;
};

/**
 * @brief Kokoro TTS configuration (internal)
 */
struct KokoroConfig {
    int32_t num_threads = 0;            // 0 = auto
    bool enable_profiling = false;
    NPUBackend npu_backend = NPUBackend::AUTO;  // Which NPU backend to use
    // QNN DISABLED FOR NNAPI TESTING
    // rac_qnn_config_t qnn_config;        // QNN config for NPU (Qualcomm-specific)
    rac_nnapi_config_t nnapi_config;    // NNAPI config for NPU (vendor-agnostic)
};

/**
 * @brief Kokoro TTS Loader - Internal Implementation
 *
 * Handles direct ONNX Runtime session management for Kokoro models.
 * This loader is used internally by the ONNX backend when a Kokoro model
 * is detected. It is NOT exposed to the application layer.
 *
 * Supports both:
 *   - Unified models (CPU execution)
 *   - Split models (hybrid NPU+CPU execution via QNN)
 */
class KokoroTTSLoader {
public:
    KokoroTTSLoader();
    ~KokoroTTSLoader();

    // Non-copyable
    KokoroTTSLoader(const KokoroTTSLoader&) = delete;
    KokoroTTSLoader& operator=(const KokoroTTSLoader&) = delete;

    /**
     * @brief Detect Kokoro model type from path
     *
     * Called by rac_tts_onnx_create to determine if a path contains
     * a Kokoro model (unified or split).
     *
     * @param model_path Path to model directory or file
     * @param out_info Output model information
     * @return true if Kokoro model detected
     */
    static bool detect_model(const std::string& model_path, KokoroModelInfo& out_info);

    /**
     * @brief Load a Kokoro model
     *
     * @param model_path Path to model directory
     * @param config Configuration options (internal)
     * @return RAC_SUCCESS or error code
     */
    rac_result_t load(const std::string& model_path, const KokoroConfig& config);

    /**
     * @brief Unload the model and free resources
     */
    void unload();

    /**
     * @brief Check if a model is loaded
     */
    bool is_loaded() const { return loaded_; }

    /**
     * @brief Check if NPU is active (split model only)
     */
    bool is_npu_active() const { return stats_.npu_active; }

    /**
     * @brief Get the loaded model type
     */
    KokoroModelType get_model_type() const { return model_info_.type; }

    /**
     * @brief Synthesize audio from token IDs
     *
     * @param token_ids Token IDs array
     * @param num_tokens Number of tokens
     * @param style_vector Style embedding (256 floats)
     * @param speed Speech speed (integer)
     * @param out_audio Output audio samples
     * @return RAC_SUCCESS or error code
     */
    rac_result_t synthesize(const int64_t* token_ids,
                           size_t num_tokens,
                           const float* style_vector,
                           int32_t speed,
                           std::vector<float>& out_audio);

    /**
     * @brief Synthesize audio from text (uses internal tokenizer)
     *
     * @param text Text to synthesize
     * @param voice_id Voice ID for style selection
     * @param speed_rate Speed multiplier (1.0 = normal)
     * @param out_audio Output audio samples
     * @return RAC_SUCCESS or error code
     */
    rac_result_t synthesize_text(const std::string& text,
                                 const std::string& voice_id,
                                 float speed_rate,
                                 std::vector<float>& out_audio);

    /**
     * @brief Get inference statistics
     */
    const KokoroStats& get_stats() const { return stats_; }

    /**
     * @brief Get sample rate (always 24000 for Kokoro)
     */
    int32_t get_sample_rate() const { return 24000; }

    /**
     * @brief Run NPU vs CPU benchmark
     *
     * This method runs the same synthesis on both NPU (NNAPI if available)
     * and a fresh CPU-only session to compare performance.
     *
     * @param test_text Text to synthesize for benchmark (optional, uses default if empty)
     * @return Benchmark results with timing comparison
     */
    KokoroBenchmarkResult run_benchmark(const std::string& test_text = "");

private:
    /**
     * @brief Load unified model (single ONNX file)
     */
    rac_result_t load_unified_model(const std::string& model_path);

    /**
     * @brief Load split models (encoder + vocoder)
     */
    rac_result_t load_split_models(const std::string& encoder_path,
                                   const std::string& vocoder_path);

    /**
     * @brief Run inference on unified model
     */
    rac_result_t run_unified_inference(const int64_t* token_ids,
                                       size_t num_tokens,
                                       const float* style_vector,
                                       int32_t speed,
                                       std::vector<float>& out_audio);

    /**
     * @brief Run hybrid inference on split models
     */
    rac_result_t run_hybrid_inference(const int64_t* token_ids,
                                      size_t num_tokens,
                                      const float* style_vector,
                                      int32_t speed,
                                      std::vector<float>& out_audio);

    /**
     * @brief Create CPU session options
     */
    OrtSessionOptions* create_cpu_session_options();

    // QNN DISABLED FOR NNAPI TESTING
    // #if RAC_QNN_AVAILABLE
    //     /**
    //      * @brief Create QNN session options for NPU (Qualcomm-specific)
    //      */
    //     OrtSessionOptions* create_qnn_session_options();
    // #endif

#if RAC_NNAPI_AVAILABLE
    /**
     * @brief Create NNAPI session options for NPU (vendor-agnostic)
     */
    OrtSessionOptions* create_nnapi_session_options();
#endif

    /**
     * @brief Create best available NPU session options
     *
     * Tries NNAPI first (broader compatibility), then QNN (Qualcomm-specific),
     * finally falls back to CPU.
     */
    OrtSessionOptions* create_npu_session_options();

    /**
     * @brief Get session I/O information
     */
    bool get_session_io_info(OrtSession* session,
                            std::vector<std::string>& input_names,
                            std::vector<std::string>& output_names);

    /**
     * @brief Initialize ONNX Runtime (with QNN EP support via dynamic loading)
     *
     * This method attempts to load a separate QNN-enabled ONNX Runtime library
     * (libonnxruntime_qnn.so) to avoid symbol conflicts with sherpa-onnx.
     * If not found, falls back to the default ONNX Runtime.
     */
    bool initialize_onnx_runtime();

    /**
     * @brief Dynamically load QNN-enabled ONNX Runtime
     * @return true if successfully loaded, false to fall back to default
     */
    bool load_qnn_onnx_runtime();

    /**
     * @brief Cleanup ONNX Runtime resources
     */
    void cleanup_onnx_runtime();

    // ONNX Runtime (possibly from dynamic library)
    const OrtApi* ort_api_ = nullptr;
    OrtEnv* ort_env_ = nullptr;
    bool ort_initialized_ = false;

    // QNN DISABLED FOR NNAPI TESTING
    // Dynamic library handle for QNN-enabled ORT
    // void* ort_qnn_lib_handle_ = nullptr;
    // bool using_qnn_ort_ = false;

    // Sessions
    OrtSession* unified_session_ = nullptr;
    OrtSession* encoder_session_ = nullptr;
    OrtSession* vocoder_session_ = nullptr;

    // Session I/O info
    std::vector<std::string> unified_input_names_;
    std::vector<std::string> unified_output_names_;
    std::vector<std::string> encoder_input_names_;
    std::vector<std::string> encoder_output_names_;
    std::vector<std::string> vocoder_input_names_;
    std::vector<std::string> vocoder_output_names_;

    // Intermediate encoder outputs (for hybrid inference)
    std::vector<OrtValue*> encoder_outputs_;

    // Configuration
    KokoroConfig config_;
    KokoroModelInfo model_info_;

    // State
    bool loaded_ = false;
    KokoroStats stats_;

    // NPU Session Managers (conditionally compiled)
    // QNN DISABLED FOR NNAPI TESTING
    // #if RAC_QNN_AVAILABLE
    //     std::unique_ptr<QNNSessionManager> qnn_session_manager_;      // Qualcomm-specific
    // #endif
#if RAC_NNAPI_AVAILABLE
    std::unique_ptr<NNAPISessionManager> nnapi_session_manager_;  // Vendor-agnostic
#endif

    // Track which NPU backend is active
    NPUBackend active_npu_backend_ = NPUBackend::CPU_ONLY;
};

}  // namespace onnx
}  // namespace rac

#endif  // RAC_KOKORO_TTS_LOADER_H
