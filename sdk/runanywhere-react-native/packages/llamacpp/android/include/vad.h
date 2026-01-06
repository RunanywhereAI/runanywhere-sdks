#ifndef RUNANYWHERE_VAD_CAPABILITY_H
#define RUNANYWHERE_VAD_CAPABILITY_H

#include "capability.h"

#include <functional>

namespace runanywhere {

// VAD model types
enum class VADModelType {
    SILERO,  // Silero VAD (most common)
    WEBRTC,  // WebRTC VAD
    SHERPA,  // Sherpa-ONNX VAD
    CUSTOM   // Other VAD models
};

// Speech segment detected by VAD
struct SpeechSegment {
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_speech = true;

    double duration_ms() const { return end_time_ms - start_time_ms; }
};

// VAD configuration
struct VADConfig {
    float threshold = 0.5f;             // Speech probability threshold
    int min_speech_duration_ms = 250;   // Minimum speech duration to report
    int min_silence_duration_ms = 100;  // Minimum silence to split segments
    int padding_ms = 30;                // Padding around speech segments
    int window_size_ms = 32;            // Analysis window size
    int sample_rate = 16000;
    nlohmann::json extra_params;
};

// VAD result for a chunk of audio
struct VADResult {
    bool is_speech = false;
    float probability = 0.0f;
    double timestamp_ms = 0.0;
    std::vector<SpeechSegment> segments;  // For batch processing
    nlohmann::json metadata;

    nlohmann::json to_json() const {
        nlohmann::json j = {{"is_speech", is_speech},
                            {"probability", probability},
                            {"timestamp_ms", timestamp_ms},
                            {"metadata", metadata}};
        if (!segments.empty()) {
            j["segments"] = nlohmann::json::array();
            for (const auto& seg : segments) {
                j["segments"].push_back({{"start_ms", seg.start_time_ms},
                                         {"end_ms", seg.end_time_ms},
                                         {"confidence", seg.confidence}});
            }
        }
        return j;
    }
};

// VAD streaming callback: receives speech/silence events
using VADStreamCallback = std::function<void(const VADResult& result)>;

// Voice Activity Detection Capability Interface
class IVAD : public ICapability {
   public:
    CapabilityType type() const override { return CapabilityType::VAD; }

    // Load VAD model
    virtual bool load_model(const std::string& model_path,
                            VADModelType model_type = VADModelType::SILERO,
                            const nlohmann::json& config = {}) = 0;

    // Check if model is loaded
    virtual bool is_model_loaded() const = 0;

    // Unload model
    virtual bool unload_model() = 0;

    // Configure VAD parameters
    virtual bool configure_vad(const VADConfig& config) = 0;

    // Process audio chunk and get speech probability
    virtual VADResult process(const std::vector<float>& audio_samples, int sample_rate) = 0;

    // Process full audio and get all speech segments
    virtual std::vector<SpeechSegment> detect_segments(const std::vector<float>& audio_samples,
                                                       int sample_rate) = 0;

    // --- Streaming interface ---

    // Create streaming session
    virtual std::string create_stream(const VADConfig& config = {}) { return ""; }

    // Feed audio to stream
    virtual VADResult feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                                 int sample_rate) {
        return {};
    }

    // Destroy stream
    virtual void destroy_stream(const std::string& stream_id) {}

    // Reset internal state
    virtual void reset() = 0;

    // Get current VAD configuration
    virtual VADConfig get_vad_config() const = 0;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_VAD_CAPABILITY_H
