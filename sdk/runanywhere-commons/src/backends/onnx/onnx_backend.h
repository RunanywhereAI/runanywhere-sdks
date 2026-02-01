#ifndef RUNANYWHERE_ONNX_BACKEND_H
#define RUNANYWHERE_ONNX_BACKEND_H

/**
 * ONNX Backend - Internal implementation for STT, TTS, VAD
 *
 * This backend uses ONNX Runtime for general ML inference and
 * Sherpa-ONNX for speech-specific tasks (STT, TTS, VAD).
 * Internal C++ implementation wrapped by RAC API (rac_onnx.cpp).
 */

#include <onnxruntime_c_api.h>

#include <atomic>
#include <chrono>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

// QNN Configuration for NPU support - COMPLETELY DISABLED FOR NNAPI TESTING
// #include "rac/backends/rac_qnn_config.h"  // QNN DISABLED
// All QNN types and functions are disabled. Use NNAPI for NPU acceleration.

// Sherpa-ONNX C API for TTS/STT
#if SHERPA_ONNX_AVAILABLE
#include <sherpa-onnx/c-api/c-api.h>
#endif

namespace runanywhere {

// =============================================================================
// INTERNAL TYPES
// =============================================================================

enum class DeviceType {
    CPU = 0,
    GPU = 1,
    NEURAL_ENGINE = 2,
    NPU = 3,           // Qualcomm HTP (QNN)
    COREML = 6,
};

// =============================================================================
// NPU STRATEGY (for hybrid execution)
// =============================================================================

/**
 * @brief NPU execution strategy for models with partial NPU support
 *
 * IMPORTANT: For models with ISTFT (e.g., Kokoro TTS), HYBRID is required
 * because ISTFT is NOT supported on QNN HTP.
 */
enum class NPUStrategy {
    CPU_ONLY = 0,       // No NPU, use CPU only
    NPU_PREFERRED = 1,  // Try NPU, fallback to CPU for unsupported ops
    NPU_REQUIRED = 2,   // NPU only, fail if any op can't run on NPU
    HYBRID = 3,         // NPU for encoder, CPU for vocoder (DEFAULT for Kokoro)
};

struct DeviceInfo {
    DeviceType device_type = DeviceType::CPU;
    std::string device_name;
    std::string platform;
    size_t available_memory = 0;
    int cpu_cores = 0;
};

// =============================================================================
// STT TYPES
// =============================================================================

enum class STTModelType {
    WHISPER,
    ZIPFORMER,
    TRANSDUCER,
    PARAFORMER,
    CUSTOM
};

struct AudioSegment {
    std::string text;
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    std::string language;
};

struct STTRequest {
    std::vector<float> audio_samples;
    int sample_rate = 16000;
    std::string language;
    bool detect_language = false;
    bool word_timestamps = false;
};

struct STTResult {
    std::string text;
    std::string detected_language;
    std::vector<AudioSegment> segments;
    double audio_duration_ms = 0.0;
    double inference_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_final = true;
};

// =============================================================================
// TTS TYPES
// =============================================================================

enum class TTSModelType {
    PIPER,
    COQUI,
    BARK,
    ESPEAK,
    CUSTOM
};

struct VoiceInfo {
    std::string id;
    std::string name;
    std::string language;
    std::string gender;
    std::string description;
    int sample_rate = 22050;
};

struct TTSRequest {
    std::string text;
    std::string voice_id;
    std::string language;
    float speed_rate = 1.0f;
    int sample_rate = 22050;
};

struct TTSResult {
    std::vector<float> audio_samples;
    int sample_rate = 22050;
    int channels = 1;
    double duration_ms = 0.0;
    double inference_time_ms = 0.0;
};

// =============================================================================
// VAD TYPES
// =============================================================================

enum class VADModelType {
    SILERO,
    WEBRTC,
    SHERPA,
    CUSTOM
};

struct SpeechSegment {
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_speech = true;
};

struct VADConfig {
    float threshold = 0.5f;
    int min_speech_duration_ms = 250;
    int min_silence_duration_ms = 100;
    int padding_ms = 30;
    int window_size_ms = 32;
    int sample_rate = 16000;
};

struct VADResult {
    bool is_speech = false;
    float probability = 0.0f;
    double timestamp_ms = 0.0;
    std::vector<SpeechSegment> segments;
};

// =============================================================================
// TELEMETRY (simple inline implementation)
// =============================================================================

using TelemetryCallback = std::function<void(const std::string& event_json)>;

class TelemetryCollector {
   public:
    void set_callback(TelemetryCallback callback) { callback_ = callback; }

    void emit(const std::string& event_type, const nlohmann::json& data = {}) {
        if (callback_) {
            nlohmann::json event = {
                {"type", event_type},
                {"data", data},
                {"timestamp", std::chrono::system_clock::now().time_since_epoch().count()}};
            callback_(event.dump());
        }
    }

   private:
    TelemetryCallback callback_;
};

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class ONNXSTT;
class ONNXTTS;
class ONNXVAD;

// =============================================================================
// ONNX BACKEND
// =============================================================================

class ONNXBackendNew {
   public:
    ONNXBackendNew();
    ~ONNXBackendNew();

    bool initialize(const nlohmann::json& config = {});
    bool is_initialized() const;
    void cleanup();

    DeviceType get_device_type() const;
    size_t get_memory_usage() const;

    const OrtApi* get_ort_api() const { return ort_api_; }
    OrtEnv* get_ort_env() const { return ort_env_; }

    const DeviceInfo& get_device_info() const { return device_info_; }

    void set_telemetry_callback(TelemetryCallback callback);

    // Get capability implementations
    ONNXSTT* get_stt() { return stt_.get(); }
    ONNXTTS* get_tts() { return tts_.get(); }
    ONNXVAD* get_vad() { return vad_.get(); }

   private:
    bool initialize_ort();
    void create_capabilities();

    bool initialized_ = false;
    const OrtApi* ort_api_ = nullptr;
    OrtEnv* ort_env_ = nullptr;
    nlohmann::json config_;
    DeviceInfo device_info_;
    TelemetryCollector telemetry_;

    std::unique_ptr<ONNXSTT> stt_;
    std::unique_ptr<ONNXTTS> tts_;
    std::unique_ptr<ONNXVAD> vad_;

    mutable std::mutex mutex_;
};

// =============================================================================
// STT IMPLEMENTATION
// =============================================================================

class ONNXSTT {
   public:
    explicit ONNXSTT(ONNXBackendNew* backend);
    ~ONNXSTT();

    bool is_ready() const;
    bool load_model(const std::string& model_path, STTModelType model_type = STTModelType::WHISPER,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();
    STTModelType get_model_type() const;

    STTResult transcribe(const STTRequest& request);
    bool supports_streaming() const;

    std::string create_stream(const nlohmann::json& config = {});
    bool feed_audio(const std::string& stream_id, const std::vector<float>& samples, int sample_rate);
    bool is_stream_ready(const std::string& stream_id);
    STTResult decode(const std::string& stream_id);
    bool is_endpoint(const std::string& stream_id);
    void input_finished(const std::string& stream_id);
    void reset_stream(const std::string& stream_id);
    void destroy_stream(const std::string& stream_id);

    void cancel();
    std::vector<std::string> get_supported_languages() const;

   private:
    ONNXBackendNew* backend_;
    OrtSession* whisper_session_ = nullptr;
#if SHERPA_ONNX_AVAILABLE
    const SherpaOnnxOfflineRecognizer* sherpa_recognizer_ = nullptr;
    std::unordered_map<std::string, const SherpaOnnxOfflineStream*> sherpa_streams_;
#else
    void* sherpa_recognizer_ = nullptr;
#endif
    STTModelType model_type_ = STTModelType::WHISPER;
    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    std::unordered_map<std::string, void*> streams_;
    int stream_counter_ = 0;
    std::string model_dir_;
    std::string language_;
    mutable std::mutex mutex_;
};

// =============================================================================
// TTS IMPLEMENTATION
// =============================================================================

class ONNXTTS {
   public:
    explicit ONNXTTS(ONNXBackendNew* backend);
    ~ONNXTTS();

    bool is_ready() const;
    bool load_model(const std::string& model_path, TTSModelType model_type = TTSModelType::PIPER,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();
    TTSModelType get_model_type() const;

    TTSResult synthesize(const TTSRequest& request);
    bool supports_streaming() const;

    void cancel();
    std::vector<VoiceInfo> get_voices() const;
    std::string get_default_voice(const std::string& language) const;

    // ==========================================================================
    // NPU Support - QNN DISABLED FOR NNAPI TESTING
    // ==========================================================================
    // NOTE: All QNN-related methods are disabled. Use NNAPI for NPU acceleration.
    // These methods are kept for API compatibility but always return false/empty.

    /**
     * @brief Check if NPU is being used
     * NOTE: QNN DISABLED - always returns false
     */
    bool is_npu_active() const { return npu_active_; }

    /**
     * @brief Get current NPU strategy
     * NOTE: QNN DISABLED - always returns CPU_ONLY
     */
    NPUStrategy get_npu_strategy() const { return npu_strategy_; }

    // QNN DISABLED - These methods are commented out
    // bool load_split_models(const std::string& encoder_path, const std::string& vocoder_path,
    //                       const rac_qnn_config_t& qnn_config);
    // bool load_model_npu(const std::string& model_path, const rac_qnn_config_t& qnn_config,
    //                     NPUStrategy strategy = NPUStrategy::HYBRID);
    // rac_npu_stats_t get_npu_stats() const;

   private:
    ONNXBackendNew* backend_;
#if SHERPA_ONNX_AVAILABLE
    const SherpaOnnxOfflineTts* sherpa_tts_ = nullptr;
#else
    void* sherpa_tts_ = nullptr;
#endif
    TTSModelType model_type_ = TTSModelType::PIPER;
    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    std::atomic<int> active_synthesis_count_{0};
    std::vector<VoiceInfo> voices_;
    std::string model_dir_;
    int sample_rate_ = 22050;
    mutable std::mutex mutex_;

    // NPU support members - QNN DISABLED
    bool npu_active_ = false;
    NPUStrategy npu_strategy_ = NPUStrategy::CPU_ONLY;
    void* split_executor_ = nullptr;  // rac_split_executor_t for hybrid mode
    // rac_qnn_config_t qnn_config_ = {};  // QNN DISABLED
};

// =============================================================================
// VAD IMPLEMENTATION
// =============================================================================

class ONNXVAD {
   public:
    explicit ONNXVAD(ONNXBackendNew* backend);
    ~ONNXVAD();

    bool is_ready() const;
    bool load_model(const std::string& model_path, VADModelType model_type = VADModelType::SILERO,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();

    bool configure_vad(const VADConfig& config);
    VADResult process(const std::vector<float>& audio_samples, int sample_rate);
    std::vector<SpeechSegment> detect_segments(const std::vector<float>& audio_samples, int sample_rate);

    std::string create_stream(const VADConfig& config = {});
    VADResult feed_audio(const std::string& stream_id, const std::vector<float>& samples, int sample_rate);
    void destroy_stream(const std::string& stream_id);

    void reset();
    VADConfig get_vad_config() const;

   private:
    ONNXBackendNew* backend_;
    void* sherpa_vad_ = nullptr;
    VADConfig config_;
    bool model_loaded_ = false;
    mutable std::mutex mutex_;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_ONNX_BACKEND_H
