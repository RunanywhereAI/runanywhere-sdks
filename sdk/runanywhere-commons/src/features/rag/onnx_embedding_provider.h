/**
 * @file onnx_embedding_provider.h
 * @brief ONNX-based embedding provider implementation
 *
 * Standalone embedding provider using ONNX Runtime for sentence-transformer models.
 * Wrapped by rac_onnx_embeddings_register.cpp to expose via the embeddings service vtable.
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
 * Includes a built-in WordPiece tokenizer for BERT-style models (e.g. all-MiniLM-L6-v2).
 * Thread-safe after initialization.
 */
class ONNXEmbeddingProvider {
public:
    explicit ONNXEmbeddingProvider(
        const std::string& model_path,
        const std::string& config_json = ""
    );

    ~ONNXEmbeddingProvider();

    ONNXEmbeddingProvider(const ONNXEmbeddingProvider&) = delete;
    ONNXEmbeddingProvider& operator=(const ONNXEmbeddingProvider&) = delete;
    ONNXEmbeddingProvider(ONNXEmbeddingProvider&&) noexcept;
    ONNXEmbeddingProvider& operator=(ONNXEmbeddingProvider&&) noexcept;

    std::vector<float> embed(const std::string& text);
    size_t dimension() const noexcept;
    bool is_ready() const noexcept;
    const char* name() const noexcept;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H
