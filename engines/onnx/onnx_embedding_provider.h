/**
 * @file onnx_embedding_provider.h
 * @brief ONNX-based embedding provider implementation
 *
 * Standalone embedding provider using ONNX Runtime for sentence-transformer
 * models. Engine-owned: lives in engines/onnx/ and is wrapped by
 * the sibling rac_onnx_embeddings_register.cpp to expose via the embeddings
 * service vtable slot on the onnx engine plugin.
 */

#ifndef RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H
#define RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H

#include <memory>
#include <string>
#include <vector>

namespace runanywhere {
namespace rag {

/**
 * @brief ONNX embedding provider for sentence-transformer models
 *
 * Includes a built-in WordPiece tokenizer for BERT-style models (e.g.
 * all-MiniLM-L6-v2). Thread-safe after initialization.
 */
class ONNXEmbeddingProvider {
   public:
    explicit ONNXEmbeddingProvider(const std::string& model_path,
                                   const std::string& config_json = "");

    ~ONNXEmbeddingProvider();

    ONNXEmbeddingProvider(const ONNXEmbeddingProvider&) = delete;
    ONNXEmbeddingProvider& operator=(const ONNXEmbeddingProvider&) = delete;
    ONNXEmbeddingProvider(ONNXEmbeddingProvider&&) noexcept;
    ONNXEmbeddingProvider& operator=(ONNXEmbeddingProvider&&) noexcept;

    /**
     * @brief Computes embedding vector for a single input text.
     *
     * @param text Input text to embed.
     * @param out_total_tokens Optional pointer to receive non-padding token count.
     * @param normalize True to L2-normalize to unit vector, false to return raw pooled vector.
     * @return Float vector of embedding dimensions, or empty on failure.
     */
    std::vector<float> embed(const std::string& text, size_t* out_total_tokens = nullptr,
                             bool normalize = true);

    /**
     * @brief Computes embedding vectors for a batch of input texts.
     *
     * @param texts List of input texts to embed.
     * @param out_total_tokens Optional pointer to receive total token count.
     * @param normalize True to L2-normalize to unit vectors, false to return raw pooled vectors.
     * @return List of float vectors corresponding to input texts.
     */
    std::vector<std::vector<float>> embed_batch(const std::vector<std::string>& texts,
                                                size_t* out_total_tokens = nullptr,
                                                bool normalize = true);

    /**
     * @brief Returns the output embedding vector dimension.
     *
     * @return Number of dimensions in the embedding vector.
     */
    size_t dimension() const noexcept;

    /**
     * @brief Checks if the ONNX runtime model session is loaded and ready for inference.
     *
     * @return True if model is loaded and ready.
     */
    bool is_ready() const noexcept;

    /**
     * @brief Returns the provider backend name identifier.
     *
     * @return Human-readable provider name string.
     */
    const char* name() const noexcept;

   private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace rag
}  // namespace runanywhere

#endif  // RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H
