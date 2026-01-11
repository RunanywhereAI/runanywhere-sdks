#ifndef RUNANYWHERE_STT_CAPABILITY_H
#define RUNANYWHERE_STT_CAPABILITY_H

#include "capability.h"

#include <functional>

namespace runanywhere {

// STT model types
enum class STTModelType {
    WHISPER,     // OpenAI Whisper models
    ZIPFORMER,   // K2/Sherpa Zipformer (streaming)
    TRANSDUCER,  // Generic transducer models
    PARAFORMER,  // Alibaba Paraformer
    CUSTOM       // Other ONNX STT models
};

// Audio segment with timing
struct AudioSegment {
    std::string text;
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    std::string language;
};

// Word-level timing
struct WordTiming {
    std::string word;
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
};

// Transcription request
struct STTRequest {
    std::vector<float> audio_samples;  // Float32 samples [-1.0, 1.0]
    int sample_rate = 16000;
    std::string language;  // ISO 639-1 code (e.g., "en", "es")
    bool detect_language = false;
    bool word_timestamps = false;
    bool translate_to_english = false;  // Whisper translation mode
    nlohmann::json extra_params;
};

// Transcription result
struct STTResult {
    std::string text;
    std::string detected_language;
    std::vector<AudioSegment> segments;
    std::vector<WordTiming> word_timings;
    double audio_duration_ms = 0.0;
    double inference_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_final = true;  // For streaming: partial vs final
    nlohmann::json metadata;

    nlohmann::json to_json() const {
        nlohmann::json j = {{"text", text},
                            {"detected_language", detected_language},
                            {"audio_duration_ms", audio_duration_ms},
                            {"inference_time_ms", inference_time_ms},
                            {"confidence", confidence},
                            {"is_final", is_final},
                            {"metadata", metadata}};
        if (!segments.empty()) {
            j["segments"] = nlohmann::json::array();
            for (const auto& seg : segments) {
                j["segments"].push_back({{"text", seg.text},
                                         {"start_ms", seg.start_time_ms},
                                         {"end_ms", seg.end_time_ms},
                                         {"confidence", seg.confidence}});
            }
        }
        return j;
    }
};

// Streaming STT callback: receives partial/final result, returns false to cancel
using STTStreamCallback = std::function<bool(const STTResult& result)>;

// Speech-to-Text Capability Interface
class ISTT : public ICapability {
   public:
    CapabilityType type() const override { return CapabilityType::STT; }

    // Load STT model
    virtual bool load_model(const std::string& model_path,
                            STTModelType model_type = STTModelType::WHISPER,
                            const nlohmann::json& config = {}) = 0;

    // Check if model is loaded
    virtual bool is_model_loaded() const = 0;

    // Unload model
    virtual bool unload_model() = 0;

    // Get model type
    virtual STTModelType get_model_type() const = 0;

    // Batch transcription (full audio at once)
    virtual STTResult transcribe(const STTRequest& request) = 0;

    // Check if streaming is supported
    virtual bool supports_streaming() const = 0;

    // --- Streaming interface ---

    // Create a new streaming session (returns session ID or empty on failure)
    virtual std::string create_stream(const nlohmann::json& config = {}) { return ""; }

    // Feed audio samples to stream
    virtual bool feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                            int sample_rate) {
        return false;
    }

    // Check if decoder is ready to produce output
    virtual bool is_stream_ready(const std::string& stream_id) { return false; }

    // Decode and get result
    virtual STTResult decode(const std::string& stream_id) { return {}; }

    // Check for end-of-speech
    virtual bool is_endpoint(const std::string& stream_id) { return false; }

    // Signal end of audio input
    virtual void input_finished(const std::string& stream_id) {}

    // Reset stream for new utterance
    virtual void reset_stream(const std::string& stream_id) {}

    // Destroy stream
    virtual void destroy_stream(const std::string& stream_id) {}

    // Cancel ongoing transcription
    virtual void cancel() = 0;

    // Get supported languages
    virtual std::vector<std::string> get_supported_languages() const { return {}; }
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_STT_CAPABILITY_H
