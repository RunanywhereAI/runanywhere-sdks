/**
 * @file inference_provider.h
 * @brief Abstract interfaces for RAG inference providers
 *
 * Strategy pattern interfaces for embedding and text generation.
 * Allows RAG backend to work with any implementation (ONNX, LlamaCPP, etc.)
 */

#ifndef RUNANYWHERE_INFERENCE_PROVIDER_H
#define RUNANYWHERE_INFERENCE_PROVIDER_H

#include <string>
#include <vector>
#include <memory>

#include <nlohmann/json.hpp>

namespace runanywhere {
namespace rag {

// =============================================================================
// EMBEDDING PROVIDER INTERFACE
// =============================================================================

/**
 * @brief Abstract interface for text embedding generation
 * 
 * Implementations should be thread-safe for concurrent embeddings.
 */
class IEmbeddingProvider {
public:
    virtual ~IEmbeddingProvider() = default;

    /**
     * @brief Generate embedding vector for text
     * 
     * @param text Input text to embed
     * @return Embedding vector (caller should check size matches expected dimension)
     * @throws std::runtime_error on inference failure
     */
    virtual std::vector<float> embed(const std::string& text) = 0;

    /**
     * @brief Get embedding dimension
     * 
     * @return Vector dimension (e.g., 384 for all-MiniLM-L6-v2)
     */
    virtual size_t dimension() const noexcept = 0;

    /**
     * @brief Check if provider is ready for inference
     * 
     * @return true if initialized and ready, false otherwise
     */
    virtual bool is_ready() const noexcept = 0;

    /**
     * @brief Get provider name for logging/debugging
     * 
     * @return Provider identifier (e.g., "ONNX-MiniLM")
     */
    virtual const char* name() const noexcept = 0;
};

// =============================================================================
// TEXT GENERATION INTERFACE
// =============================================================================

/**
 * @brief Generation options
 */
struct GenerationOptions {
    int max_tokens = 1024;
    float temperature = 0.7f;
    float top_p = 0.9f;
    int top_k = 40;
    bool use_sampling = true;
    
    // Stop sequences
    std::vector<std::string> stop_sequences;
};

/**
 * @brief Generation result with metadata
 */
struct GenerationResult {
    std::string text;
    int tokens_generated = 0;
    int prompt_tokens = 0;
    double inference_time_ms = 0.0;
    bool finished = false;
    std::string stop_reason;  // "stop", "length", "cancelled", "error"
    
    // RAG-specific metadata
    nlohmann::json metadata;  // For storing sources, chunk info, etc.
    bool success = true;      // False on errors
};

/**
 * @brief Abstract interface for text generation
 * 
 * Implementations should be thread-safe or provide per-instance isolation.
 */
class ITextGenerator {
public:
    virtual ~ITextGenerator() = default;

    /**
     * @brief Generate text from prompt
     * 
     * @param prompt Input prompt (can include context)
     * @param options Generation parameters
     * @return Generation result with text and metadata
     * @throws std::runtime_error on inference failure
     */
    virtual GenerationResult generate(
        const std::string& prompt,
        const GenerationOptions& options = GenerationOptions{}
    ) = 0;

    /**
     * @brief Check if generator is ready for inference
     * 
     * @return true if initialized and ready, false otherwise
     */
    virtual bool is_ready() const noexcept = 0;

    /**
     * @brief Get generator name for logging/debugging
     * 
     * @return Generator identifier (e.g., "LlamaCPP-Phi3")
     */
    virtual const char* name() const noexcept = 0;

    /**
     * @brief Get maximum context size in tokens
     *
     * @return Context window size
     */
    virtual int context_size() const noexcept = 0;

    /**
     * @brief Inject a system prompt into the KV cache at position 0.
     * Called once at the start of an adaptive query loop.
     * Default: no-op (returns false).
     */
    virtual bool inject_system_prompt(const std::string& prompt) { (void)prompt; return false; }

    /**
     * @brief Append text to the KV cache after current content.
     * Used to incrementally add sentences during the adaptive loop.
     * Default: no-op (returns false).
     */
    virtual bool append_context(const std::string& text) { (void)text; return false; }

    /**
     * @brief Check confidence that accumulated context answers the query.
     * Default: returns 0.5 (neutral — loop continues).
     */
    virtual float probe_confidence(const std::string& context, const std::string& query) {
        (void)context; (void)query; return 0.5f;
    }

    /**
     * @brief Generate response using accumulated KV cache state.
     * Unlike generate(), does NOT clear the KV cache first.
     * Default: falls back to generate(prompt, options).
     */
    virtual GenerationResult generate_from_context(const std::string& query, const GenerationOptions& options = GenerationOptions{}) {
        return generate(query, options);
    }

    /**
     * @brief Clear all KV cache state.
     * Default: no-op.
     */
    virtual void clear_context() {}
};

// =============================================================================
// FACTORY FUNCTIONS (implemented by concrete providers)
// =============================================================================

/**
 * @brief Create ONNX embedding provider
 * 
 * @param model_path Path to ONNX model file
 * @param config_json Optional configuration JSON
 * @return Unique pointer to embedding provider
 * @throws std::runtime_error if model loading fails
 */
std::unique_ptr<IEmbeddingProvider> create_onnx_embedding_provider(
    const std::string& model_path,
    const std::string& config_json = ""
);

/**
 * @brief Create LlamaCPP text generator
 * 
 * @param model_path Path to GGUF model file
 * @param config_json Optional configuration JSON
 * @return Unique pointer to text generator
 * @throws std::runtime_error if model loading fails
 */
std::unique_ptr<ITextGenerator> create_llamacpp_generator(
    const std::string& model_path,
    const std::string& config_json = ""
);

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_INFERENCE_PROVIDER_H
