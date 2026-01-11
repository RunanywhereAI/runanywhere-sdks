#ifndef RUNANYWHERE_TEXT_GENERATION_CAPABILITY_H
#define RUNANYWHERE_TEXT_GENERATION_CAPABILITY_H

#include "capability.h"

#include <functional>

namespace runanywhere {

// Text generation request parameters
struct TextGenerationRequest {
    std::string prompt;
    std::string system_prompt;
    std::vector<std::pair<std::string, std::string>> messages;  // role, content pairs
    int max_tokens = 256;
    float temperature = 0.7f;
    float top_p = 0.9f;
    int top_k = 40;
    float repetition_penalty = 1.1f;
    std::vector<std::string> stop_sequences;
    nlohmann::json extra_params;
};

// Text generation result
struct TextGenerationResult {
    std::string text;
    int tokens_generated = 0;
    int prompt_tokens = 0;
    double inference_time_ms = 0.0;
    std::string finish_reason;  // "stop", "length", "cancelled"
    nlohmann::json metadata;

    nlohmann::json to_json() const {
        return {{"text", text},
                {"tokens_generated", tokens_generated},
                {"prompt_tokens", prompt_tokens},
                {"inference_time_ms", inference_time_ms},
                {"finish_reason", finish_reason},
                {"metadata", metadata}};
    }
};

// Streaming callback: receives token, returns false to cancel
using TextStreamCallback = std::function<bool(const std::string& token)>;

// Text Generation Capability Interface
class ITextGeneration : public ICapability {
   public:
    CapabilityType type() const override { return CapabilityType::TEXT_GENERATION; }

    // Load a text generation model
    virtual bool load_model(const std::string& model_path, const nlohmann::json& config = {}) = 0;

    // Check if model is loaded
    virtual bool is_model_loaded() const = 0;

    // Unload current model
    virtual bool unload_model() = 0;

    // Synchronous generation
    virtual TextGenerationResult generate(const TextGenerationRequest& request) = 0;

    // Streaming generation with callback
    virtual bool generate_stream(const TextGenerationRequest& request,
                                 TextStreamCallback callback) = 0;

    // Cancel ongoing generation
    virtual void cancel() = 0;

    // Get model info
    virtual nlohmann::json get_model_info() const { return {}; }
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_TEXT_GENERATION_CAPABILITY_H
