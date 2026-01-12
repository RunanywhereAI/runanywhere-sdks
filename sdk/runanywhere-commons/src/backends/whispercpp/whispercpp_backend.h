#ifndef RUNANYWHERE_WHISPERCPP_BACKEND_H
#define RUNANYWHERE_WHISPERCPP_BACKEND_H

/**
 * WhisperCPP Backend - Speech-to-Text via whisper.cpp
 *
 * This backend uses whisper.cpp for on-device speech recognition with GGML Whisper models.
 * Internal C++ implementation wrapped by RAC API (rac_stt_whispercpp.cpp).
 */

#include <whisper.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

namespace runanywhere {

// =============================================================================
// INTERNAL TYPES
// =============================================================================

enum class DeviceType {
    CPU = 0,
    GPU = 1,
    METAL = 3,
    CUDA = 4,
};

enum class STTModelType {
    WHISPER,
    ZIPFORMER,
    TRANSDUCER,
    PARAFORMER,
    CUSTOM
};

// =============================================================================
// STT RESULT TYPES
// =============================================================================

struct WordTiming {
    std::string word;
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
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
    bool translate_to_english = false;
};

struct STTResult {
    std::string text;
    std::string detected_language;
    std::vector<AudioSegment> segments;
    std::vector<WordTiming> word_timings;
    double audio_duration_ms = 0.0;
    double inference_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_final = true;
};

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class WhisperCppSTT;

// =============================================================================
// WHISPERCPP BACKEND
// =============================================================================

class WhisperCppBackend {
   public:
    WhisperCppBackend();
    ~WhisperCppBackend();

    bool initialize(const nlohmann::json& config = {});
    bool is_initialized() const;
    void cleanup();

    DeviceType get_device_type() const;
    size_t get_memory_usage() const;

    int get_num_threads() const { return num_threads_; }
    bool is_gpu_enabled() const { return use_gpu_; }

    WhisperCppSTT* get_stt() { return stt_.get(); }

   private:
    void create_stt();

    bool initialized_ = false;
    nlohmann::json config_;
    int num_threads_ = 0;
    bool use_gpu_ = true;
    std::unique_ptr<WhisperCppSTT> stt_;
    mutable std::mutex mutex_;
};

// =============================================================================
// STREAMING STATE
// =============================================================================

struct WhisperStreamState {
    whisper_state* state = nullptr;
    std::vector<float> audio_buffer;
    std::string language;
    bool input_finished = false;
    int sample_rate = 16000;
};

// =============================================================================
// STT IMPLEMENTATION
// =============================================================================

class WhisperCppSTT {
   public:
    explicit WhisperCppSTT(WhisperCppBackend* backend);
    ~WhisperCppSTT();

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
    STTResult transcribe_internal(const std::vector<float>& audio, const std::string& language,
                                  bool detect_language, bool translate, bool word_timestamps);
    std::vector<float> resample_to_16khz(const std::vector<float>& samples, int source_rate);
    std::string generate_stream_id();

    WhisperCppBackend* backend_;
    whisper_context* ctx_ = nullptr;

    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};

    std::string model_path_;
    nlohmann::json model_config_;

    std::unordered_map<std::string, std::unique_ptr<WhisperStreamState>> streams_;
    int stream_counter_ = 0;

    mutable std::mutex mutex_;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_WHISPERCPP_BACKEND_H
