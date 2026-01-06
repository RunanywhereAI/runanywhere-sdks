#ifndef RUNANYWHERE_TTS_CAPABILITY_H
#define RUNANYWHERE_TTS_CAPABILITY_H

#include "capability.h"

#include <cstdint>
#include <functional>

namespace runanywhere {

// TTS model types
enum class TTSModelType {
    PIPER,   // Piper VITS models
    COQUI,   // Coqui TTS models
    BARK,    // Suno Bark (multilingual)
    ESPEAK,  // eSpeak-NG
    CUSTOM   // Other ONNX TTS models
};

// Voice information
struct VoiceInfo {
    std::string id;
    std::string name;
    std::string language;  // ISO 639-1 code
    std::string gender;    // "male", "female", "neutral"
    std::string description;
    int sample_rate = 22050;
    nlohmann::json metadata;
};

// TTS synthesis request
struct TTSRequest {
    std::string text;
    std::string voice_id;
    std::string language;      // Override language if different from voice
    float speed_rate = 1.0f;   // 0.5 = half speed, 2.0 = double speed
    float pitch_shift = 0.0f;  // Semitones: -12 to +12
    float volume = 1.0f;       // 0.0 to 1.0
    int sample_rate = 22050;   // Output sample rate
    bool enable_ssml = false;  // Parse SSML tags
    nlohmann::json extra_params;
};

// TTS synthesis result
struct TTSResult {
    std::vector<float> audio_samples;  // Float32 samples [-1.0, 1.0]
    std::vector<int16_t> audio_pcm16;  // PCM16 samples (optional)
    int sample_rate = 22050;
    int channels = 1;
    double duration_ms = 0.0;
    double inference_time_ms = 0.0;
    nlohmann::json metadata;

    nlohmann::json to_json() const {
        return {{"sample_rate", sample_rate},
                {"channels", channels},
                {"duration_ms", duration_ms},
                {"inference_time_ms", inference_time_ms},
                {"audio_samples_count", audio_samples.size()},
                {"metadata", metadata}};
    }
};

// Streaming TTS callback: receives audio chunk, returns false to cancel
using TTSStreamCallback = std::function<bool(const std::vector<float>& audio_chunk, bool is_final)>;

// Text-to-Speech Capability Interface
class ITTS : public ICapability {
   public:
    CapabilityType type() const override { return CapabilityType::TTS; }

    // Load TTS model
    virtual bool load_model(const std::string& model_path,
                            TTSModelType model_type = TTSModelType::PIPER,
                            const nlohmann::json& config = {}) = 0;

    // Check if model is loaded
    virtual bool is_model_loaded() const = 0;

    // Unload model
    virtual bool unload_model() = 0;

    // Get model type
    virtual TTSModelType get_model_type() const = 0;

    // Batch synthesis (full text at once)
    virtual TTSResult synthesize(const TTSRequest& request) = 0;

    // Streaming synthesis
    virtual bool synthesize_stream(const TTSRequest& request, TTSStreamCallback callback) {
        return false;
    }

    // Check if streaming is supported
    virtual bool supports_streaming() const { return false; }

    // Cancel ongoing synthesis
    virtual void cancel() = 0;

    // Get available voices
    virtual std::vector<VoiceInfo> get_voices() const { return {}; }

    // Get default voice for language
    virtual std::string get_default_voice(const std::string& language) const { return ""; }

    // Utility: Convert float samples to PCM16
    static std::vector<int16_t> float_to_pcm16(const std::vector<float>& samples) {
        std::vector<int16_t> pcm16(samples.size());
        for (size_t i = 0; i < samples.size(); ++i) {
            float clamped = std::max(-1.0f, std::min(1.0f, samples[i]));
            pcm16[i] = static_cast<int16_t>(clamped * 32767.0f);
        }
        return pcm16;
    }

    // Utility: Convert PCM16 to float samples
    static std::vector<float> pcm16_to_float(const int16_t* samples, size_t count) {
        std::vector<float> float_samples(count);
        for (size_t i = 0; i < count; ++i) {
            float_samples[i] = static_cast<float>(samples[i]) / 32768.0f;
        }
        return float_samples;
    }
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_TTS_CAPABILITY_H
