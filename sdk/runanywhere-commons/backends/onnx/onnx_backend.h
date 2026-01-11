#ifndef RUNANYWHERE_ONNX_BACKEND_H
#define RUNANYWHERE_ONNX_BACKEND_H

/**
 * ONNX Backend - Capability-based implementation
 *
 * This backend uses ONNX Runtime for general ML inference and
 * Sherpa-ONNX for speech-specific tasks (STT, TTS, VAD, Diarization).
 *
 * Supported Capabilities:
 * - TEXT_GENERATION: Via ONNX LLM models (ORT GenAI)
 * - EMBEDDINGS: Via ONNX embedding models
 * - STT: Via Whisper (batch) + Sherpa-ONNX Zipformer (streaming)
 * - TTS: Via Sherpa-ONNX Piper/VITS
 * - VAD: Via Sherpa-ONNX Silero VAD
 * - DIARIZATION: Via Sherpa-ONNX speaker models
 */

#include <onnxruntime_c_api.h>

#include <atomic>
#include <chrono>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "capabilities/backend.h"
#include "capabilities/types.h"

// Sherpa-ONNX C API for TTS/STT
#if SHERPA_ONNX_AVAILABLE
#include <sherpa-onnx/c-api/c-api.h>
#endif

namespace runanywhere {

// =============================================================================
// SIMPLE DEVICE INFO (inline for now)
// =============================================================================

struct DeviceInfo {
    ra_device_type device_type = RA_DEVICE_CPU;
    std::string device_name;
    std::string platform;
    size_t available_memory = 0;
    int cpu_cores = 0;
};

// =============================================================================
// SIMPLE TELEMETRY (inline for now)
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

class ONNXTextGeneration;
class ONNXEmbeddings;
class ONNXSTT;
class ONNXTTS;
class ONNXVAD;
class ONNXDiarization;

// =============================================================================
// ONNX BACKEND
// =============================================================================

class ONNXBackendNew : public Backend {
   public:
    ONNXBackendNew();
    ~ONNXBackendNew() override;

    // Backend interface
    BackendInfo get_info() const override;
    bool initialize(const nlohmann::json& config = {}) override;
    bool is_initialized() const override;
    void cleanup() override;

    ra_device_type get_device_type() const override;
    size_t get_memory_usage() const override;

    // Get ONNX Runtime API (for capability implementations)
    const OrtApi* get_ort_api() const { return ort_api_; }
    OrtEnv* get_ort_env() const { return ort_env_; }

    // Get device info
    const DeviceInfo& get_device_info() const { return device_info_; }

    // Set telemetry callback
    void set_telemetry_callback(TelemetryCallback callback);

   private:
    bool initialize_ort();
    void create_capabilities();

    bool initialized_ = false;
    const OrtApi* ort_api_ = nullptr;
    OrtEnv* ort_env_ = nullptr;
    nlohmann::json config_;
    DeviceInfo device_info_;
    TelemetryCollector telemetry_;
    mutable std::mutex mutex_;
};

// =============================================================================
// CAPABILITY IMPLEMENTATIONS
// =============================================================================

class ONNXTextGeneration : public ITextGeneration {
   public:
    explicit ONNXTextGeneration(ONNXBackendNew* backend);
    ~ONNXTextGeneration() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path, const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;

    TextGenerationResult generate(const TextGenerationRequest& request) override;
    bool generate_stream(const TextGenerationRequest& request,
                         TextStreamCallback callback) override;
    void cancel() override;
    nlohmann::json get_model_info() const override;

   private:
    ONNXBackendNew* backend_;
    OrtSession* session_ = nullptr;
    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    std::string model_path_;
    nlohmann::json model_config_;
    mutable std::mutex mutex_;
};

class ONNXEmbeddings : public IEmbeddings {
   public:
    explicit ONNXEmbeddings(ONNXBackendNew* backend);
    ~ONNXEmbeddings() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path, const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;

    EmbeddingResult embed(const EmbeddingRequest& request) override;
    BatchEmbeddingResult embed_batch(const std::vector<std::string>& texts) override;
    int get_dimensions() const override;

   private:
    ONNXBackendNew* backend_;
    OrtSession* session_ = nullptr;
    bool model_loaded_ = false;
    int dimensions_ = 0;
    mutable std::mutex mutex_;
};

class ONNXSTT : public ISTT {
   public:
    explicit ONNXSTT(ONNXBackendNew* backend);
    ~ONNXSTT() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path, STTModelType model_type = STTModelType::WHISPER,
                    const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;
    STTModelType get_model_type() const override;

    STTResult transcribe(const STTRequest& request) override;
    bool supports_streaming() const override;

    std::string create_stream(const nlohmann::json& config = {}) override;
    bool feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                    int sample_rate) override;
    bool is_stream_ready(const std::string& stream_id) override;
    STTResult decode(const std::string& stream_id) override;
    bool is_endpoint(const std::string& stream_id) override;
    void input_finished(const std::string& stream_id) override;
    void reset_stream(const std::string& stream_id) override;
    void destroy_stream(const std::string& stream_id) override;

    void cancel() override;
    std::vector<std::string> get_supported_languages() const override;

   private:
    ONNXBackendNew* backend_;
    OrtSession* whisper_session_ = nullptr;
#if SHERPA_ONNX_AVAILABLE
    const SherpaOnnxOfflineRecognizer* sherpa_recognizer_ = nullptr;
    // Map stream_id -> SherpaOnnxOfflineStream*
    std::unordered_map<std::string, const SherpaOnnxOfflineStream*> sherpa_streams_;
#else
    void* sherpa_recognizer_ = nullptr;
#endif
    STTModelType model_type_ = STTModelType::WHISPER;
    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    std::unordered_map<std::string, void*> streams_;
    int stream_counter_ = 0;
    std::string model_dir_;  // Directory containing model files
    std::string language_;   // Language for transcription
    mutable std::mutex mutex_;
};

class ONNXTTS : public ITTS {
   public:
    explicit ONNXTTS(ONNXBackendNew* backend);
    ~ONNXTTS() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path, TTSModelType model_type = TTSModelType::PIPER,
                    const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;
    TTSModelType get_model_type() const override;

    TTSResult synthesize(const TTSRequest& request) override;
    bool synthesize_stream(const TTSRequest& request, TTSStreamCallback callback) override;
    bool supports_streaming() const override;

    void cancel() override;
    std::vector<VoiceInfo> get_voices() const override;
    std::string get_default_voice(const std::string& language) const override;

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
    std::atomic<int> active_synthesis_count_{0};  // Track active synthesis operations
    std::vector<VoiceInfo> voices_;
    std::string model_dir_;    // Directory containing model files
    int sample_rate_ = 22050;  // Default sample rate for VITS models
    mutable std::mutex mutex_;
};

class ONNXVAD : public IVAD {
   public:
    explicit ONNXVAD(ONNXBackendNew* backend);
    ~ONNXVAD() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path, VADModelType model_type = VADModelType::SILERO,
                    const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;

    bool configure_vad(const VADConfig& config) override;
    VADResult process(const std::vector<float>& audio_samples, int sample_rate) override;
    std::vector<SpeechSegment> detect_segments(const std::vector<float>& audio_samples,
                                               int sample_rate) override;

    std::string create_stream(const VADConfig& config = {}) override;
    VADResult feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                         int sample_rate) override;
    void destroy_stream(const std::string& stream_id) override;

    void reset() override;
    VADConfig get_vad_config() const override;

   private:
    ONNXBackendNew* backend_;
    void* sherpa_vad_ = nullptr;
    VADConfig config_;
    bool model_loaded_ = false;
    mutable std::mutex mutex_;
};

class ONNXDiarization : public IDiarization {
   public:
    explicit ONNXDiarization(ONNXBackendNew* backend);
    ~ONNXDiarization() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path,
                    DiarizationModelType model_type = DiarizationModelType::SHERPA,
                    const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;

    DiarizationResult diarize(const DiarizationRequest& request) override;
    std::vector<float> extract_embedding(const std::vector<float>& audio_samples,
                                         int sample_rate) override;
    float compare_speakers(const std::vector<float>& embedding1,
                           const std::vector<float>& embedding2) override;

    void cancel() override;

   private:
    ONNXBackendNew* backend_;
    void* sherpa_speaker_ = nullptr;
    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    mutable std::mutex mutex_;
};

// =============================================================================
// BACKEND FACTORY & REGISTRATION
// =============================================================================

// Export macro for shared library builds (needed for Android)
#if defined(_WIN32)
#define RA_ONNX_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RA_ONNX_EXPORT __attribute__((visibility("default")))
#else
#define RA_ONNX_EXPORT
#endif

/**
 * Creates a new ONNX backend instance.
 *
 * This factory function is called by the bridge to create backend instances.
 * The registration is done by the bridge itself to avoid singleton issues
 * across shared libraries.
 */
RA_ONNX_EXPORT std::unique_ptr<Backend> create_onnx_backend();

/**
 * Explicitly registers the ONNX backend with the BackendRegistry.
 *
 * NOTE: For shared library builds (Android), prefer calling create_onnx_backend()
 * from the bridge and letting the bridge register it. This function calls
 * BackendRegistry::instance() which may create a separate singleton in each .so.
 *
 * For static library builds (iOS), this function works correctly.
 */
void register_onnx_backend();

}  // namespace runanywhere

#endif  // RUNANYWHERE_ONNX_BACKEND_H
