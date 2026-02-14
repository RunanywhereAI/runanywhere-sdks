/**
 * @file onnx_embedding_provider.h
 * @brief ONNX-based embedding provider implementation
 */

#ifndef RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H
#define RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H

#include "inference_provider.h"
#include <memory>

// Forward declarations to avoid including ONNX backend headers
namespace runanywhere {
class ONNXBackendNew;
}

namespace runanywhere {
namespace rag {

/**
 * @brief ONNX implementation of embedding provider
 * 
 * Uses ONNX Runtime for efficient text embedding generation.
 * Thread-safe after initialization.
 */
class ONNXEmbeddingProvider final : public IEmbeddingProvider {
public:
    /**
     * @brief Construct ONNX embedding provider
     * 
     * @param model_path Path to ONNX model
     * @param config_json Optional JSON configuration
     * @throws std::runtime_error if model loading fails
     */
    explicit ONNXEmbeddingProvider(
        const std::string& model_path,
        const std::string& config_json = ""
    );

    ~ONNXEmbeddingProvider() override;

    // Disable copy, allow move
    ONNXEmbeddingProvider(const ONNXEmbeddingProvider&) = delete;
    ONNXEmbeddingProvider& operator=(const ONNXEmbeddingProvider&) = delete;
    ONNXEmbeddingProvider(ONNXEmbeddingProvider&&) noexcept;
    ONNXEmbeddingProvider& operator=(ONNXEmbeddingProvider&&) noexcept;

    // IEmbeddingProvider interface
    std::vector<float> embed(const std::string& text) override;
    size_t dimension() const noexcept override;
    bool is_ready() const noexcept override;
    const char* name() const noexcept override;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_ONNX_EMBEDDING_PROVIDER_H
