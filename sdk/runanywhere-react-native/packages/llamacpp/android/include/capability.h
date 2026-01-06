#ifndef RUNANYWHERE_CAPABILITY_H
#define RUNANYWHERE_CAPABILITY_H

#include "types.h"

#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace runanywhere {

// Capability identifiers
enum class CapabilityType {
    TEXT_GENERATION,  // LLM text generation
    EMBEDDINGS,       // Text/image embeddings
    STT,              // Speech-to-text (ASR)
    TTS,              // Text-to-speech
    VAD,              // Voice activity detection
    DIARIZATION,      // Speaker diarization
    VISION            // Image classification/detection
};

// Convert capability type to string for debugging/logging
inline const char* capability_to_string(CapabilityType type) {
    switch (type) {
        case CapabilityType::TEXT_GENERATION:
            return "text_generation";
        case CapabilityType::EMBEDDINGS:
            return "embeddings";
        case CapabilityType::STT:
            return "stt";
        case CapabilityType::TTS:
            return "tts";
        case CapabilityType::VAD:
            return "vad";
        case CapabilityType::DIARIZATION:
            return "diarization";
        case CapabilityType::VISION:
            return "vision";
        default:
            return "unknown";
    }
}

// Base capability interface - all capabilities inherit from this
class ICapability {
   public:
    virtual ~ICapability() = default;

    // Get the type of this capability
    virtual CapabilityType type() const = 0;

    // Check if capability is ready to use
    virtual bool is_ready() const = 0;

    // Get capability-specific configuration as JSON
    virtual nlohmann::json get_config() const { return {}; }

    // Configure capability with JSON
    virtual bool configure(const nlohmann::json& config) { return true; }
};

// Capability factory function type
using CapabilityFactory = std::unique_ptr<ICapability> (*)();

}  // namespace runanywhere

#endif  // RUNANYWHERE_CAPABILITY_H
