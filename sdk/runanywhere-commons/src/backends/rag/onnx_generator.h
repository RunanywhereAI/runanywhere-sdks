/**
 * @file onnx_generator.h
 * @brief ONNX-based text generator implementation
 */

#ifndef RUNANYWHERE_ONNX_GENERATOR_H
#define RUNANYWHERE_ONNX_GENERATOR_H

#include "inference_provider.h"
#include <memory>

namespace runanywhere {
namespace rag {

/**
 * @brief ONNX implementation of text generator
 * 
 * Uses ONNX Runtime for efficient LLM inference with ONNX models.
 * Optimized for mobile devices with better battery efficiency.
 * 
 * **Memory Management**: Uses PIMPL pattern with std::unique_ptr for
 * automatic resource cleanup and minimal header dependencies.
 * 
 * **Thread Safety**: Not thread-safe - create separate instances for
 * concurrent inference or add external synchronization.
 * 
 * **Performance**: Zero-copy where possible, move semantics enabled.
 */
class ONNXGenerator final : public ITextGenerator {
public:
    /**
     * @brief Construct ONNX generator
     * 
     * @param model_path Path to ONNX model file
     * @param config_json Optional JSON configuration
     * @throws std::runtime_error if model loading fails
     */
    explicit ONNXGenerator(
        const std::string& model_path,
        const std::string& config_json = ""
    );

    ~ONNXGenerator() override;

    // ITextGenerator interface
    GenerationResult generate(
        const std::string& prompt,
        const GenerationOptions& options = GenerationOptions{}
    ) override;

    bool is_ready() const noexcept override;
    const char* name() const noexcept override;
    int context_size() const noexcept override;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

// Factory function
std::unique_ptr<ITextGenerator> create_onnx_generator(
    const std::string& model_path,
    const std::string& config_json = ""
);

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_ONNX_GENERATOR_H
