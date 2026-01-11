#ifndef RUNANYWHERE_EMBEDDINGS_CAPABILITY_H
#define RUNANYWHERE_EMBEDDINGS_CAPABILITY_H

#include "capability.h"

namespace runanywhere {

// Embedding input types
enum class EmbeddingInputType { TEXT, IMAGE, AUDIO };

// Embedding request
struct EmbeddingRequest {
    EmbeddingInputType input_type = EmbeddingInputType::TEXT;
    std::string text;                 // For text embeddings
    std::vector<uint8_t> image_data;  // For image embeddings (raw bytes)
    std::vector<float> audio_data;    // For audio embeddings
    bool normalize = true;            // L2 normalize output
    nlohmann::json extra_params;
};

// Embedding result
struct EmbeddingResult {
    std::vector<float> embedding;
    int dimensions = 0;
    double inference_time_ms = 0.0;
    nlohmann::json metadata;

    nlohmann::json to_json() const {
        return {{"dimensions", dimensions},
                {"inference_time_ms", inference_time_ms},
                {"embedding_size", embedding.size()},
                {"metadata", metadata}};
    }
};

// Batch embedding result
struct BatchEmbeddingResult {
    std::vector<std::vector<float>> embeddings;
    int dimensions = 0;
    double inference_time_ms = 0.0;
    nlohmann::json metadata;
};

// Embeddings Capability Interface
class IEmbeddings : public ICapability {
   public:
    CapabilityType type() const override { return CapabilityType::EMBEDDINGS; }

    // Load embedding model
    virtual bool load_model(const std::string& model_path, const nlohmann::json& config = {}) = 0;

    // Check if model is loaded
    virtual bool is_model_loaded() const = 0;

    // Unload model
    virtual bool unload_model() = 0;

    // Generate embedding for single input
    virtual EmbeddingResult embed(const EmbeddingRequest& request) = 0;

    // Batch embedding for multiple texts
    virtual BatchEmbeddingResult embed_batch(const std::vector<std::string>& texts) = 0;

    // Get embedding dimensions
    virtual int get_dimensions() const = 0;

    // Calculate cosine similarity between two embeddings
    static float cosine_similarity(const std::vector<float>& a, const std::vector<float>& b) {
        if (a.size() != b.size() || a.empty())
            return 0.0f;
        float dot = 0.0f, norm_a = 0.0f, norm_b = 0.0f;
        for (size_t i = 0; i < a.size(); ++i) {
            dot += a[i] * b[i];
            norm_a += a[i] * a[i];
            norm_b += b[i] * b[i];
        }
        return dot / (std::sqrt(norm_a) * std::sqrt(norm_b) + 1e-9f);
    }
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_EMBEDDINGS_CAPABILITY_H
