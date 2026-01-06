#ifndef RUNANYWHERE_DIARIZATION_CAPABILITY_H
#define RUNANYWHERE_DIARIZATION_CAPABILITY_H

#include "capability.h"

#include <functional>

namespace runanywhere {

// Diarization model types
enum class DiarizationModelType {
    PYANNOTE,   // Pyannote speaker diarization
    WESPEAKER,  // WeSpeaker (speaker embedding + clustering)
    SHERPA,     // Sherpa-ONNX speaker diarization
    CUSTOM      // Other diarization models
};

// Speaker segment
struct SpeakerSegment {
    std::string speaker_id;  // "SPEAKER_00", "SPEAKER_01", etc.
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    std::vector<float> embedding;  // Optional: speaker embedding

    double duration_ms() const { return end_time_ms - start_time_ms; }
};

// Speaker info
struct SpeakerInfo {
    std::string id;
    std::string label;             // User-provided label if any
    std::vector<float> embedding;  // Representative embedding
    double total_speech_ms = 0.0;
    int segment_count = 0;
};

// Diarization request
struct DiarizationRequest {
    std::vector<float> audio_samples;
    int sample_rate = 16000;
    int min_speakers = 1;   // Minimum expected speakers
    int max_speakers = 10;  // Maximum expected speakers (0 = auto)
    float min_segment_duration_ms = 500.0f;
    nlohmann::json extra_params;
};

// Diarization result
struct DiarizationResult {
    std::vector<SpeakerSegment> segments;
    std::vector<SpeakerInfo> speakers;
    int num_speakers = 0;
    double audio_duration_ms = 0.0;
    double inference_time_ms = 0.0;
    nlohmann::json metadata;

    nlohmann::json to_json() const {
        nlohmann::json j = {{"num_speakers", num_speakers},
                            {"audio_duration_ms", audio_duration_ms},
                            {"inference_time_ms", inference_time_ms},
                            {"metadata", metadata}};
        j["segments"] = nlohmann::json::array();
        for (const auto& seg : segments) {
            j["segments"].push_back({{"speaker_id", seg.speaker_id},
                                     {"start_ms", seg.start_time_ms},
                                     {"end_ms", seg.end_time_ms},
                                     {"confidence", seg.confidence}});
        }
        j["speakers"] = nlohmann::json::array();
        for (const auto& spk : speakers) {
            j["speakers"].push_back({{"id", spk.id},
                                     {"label", spk.label},
                                     {"total_speech_ms", spk.total_speech_ms},
                                     {"segment_count", spk.segment_count}});
        }
        return j;
    }
};

// Speaker Diarization Capability Interface
class IDiarization : public ICapability {
   public:
    CapabilityType type() const override { return CapabilityType::DIARIZATION; }

    // Load diarization model
    virtual bool load_model(const std::string& model_path,
                            DiarizationModelType model_type = DiarizationModelType::SHERPA,
                            const nlohmann::json& config = {}) = 0;

    // Check if model is loaded
    virtual bool is_model_loaded() const = 0;

    // Unload model
    virtual bool unload_model() = 0;

    // Perform diarization on audio
    virtual DiarizationResult diarize(const DiarizationRequest& request) = 0;

    // Extract speaker embedding from audio segment
    virtual std::vector<float> extract_embedding(const std::vector<float>& audio_samples,
                                                 int sample_rate) {
        return {};
    }

    // Compare two speaker embeddings (cosine similarity)
    virtual float compare_speakers(const std::vector<float>& embedding1,
                                   const std::vector<float>& embedding2) {
        return 0.0f;
    }

    // --- Online/Streaming interface ---

    // Create streaming session
    virtual std::string create_stream(const nlohmann::json& config = {}) { return ""; }

    // Feed audio and get current speaker
    virtual SpeakerSegment process_chunk(const std::string& stream_id,
                                         const std::vector<float>& samples, int sample_rate) {
        return {};
    }

    // Destroy stream
    virtual void destroy_stream(const std::string& stream_id) {}

    // Cancel processing
    virtual void cancel() = 0;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_DIARIZATION_CAPABILITY_H
