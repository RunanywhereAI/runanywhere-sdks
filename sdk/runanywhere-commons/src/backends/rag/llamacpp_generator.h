/**
 * @file llamacpp_generator.h
 * @brief LlamaCPP-based text generator implementation
 */

#ifndef RUNANYWHERE_LLAMACPP_GENERATOR_H
#define RUNANYWHERE_LLAMACPP_GENERATOR_H

#include "inference_provider.h"
#include <memory>

// Forward declarations
namespace runanywhere {
class LlamaCppBackend;
}

namespace runanywhere {
namespace rag {

/**
 * @brief LlamaCPP implementation of text generator
 * 
 * Uses llama.cpp for efficient LLM inference with GGUF models.
 * Not thread-safe - create separate instances for concurrent inference.
 */
class LlamaCppGenerator final : public ITextGenerator {
public:
    /**
     * @brief Construct LlamaCPP generator
     * 
     * @param model_path Path to GGUF model
     * @param config_json Optional JSON configuration
     * @throws std::runtime_error if model loading fails
     */
    explicit LlamaCppGenerator(
        const std::string& model_path,
        const std::string& config_json = ""
    );

    ~LlamaCppGenerator() override;

    // Disable copy, allow move
    LlamaCppGenerator(const LlamaCppGenerator&) = delete;
    LlamaCppGenerator& operator=(const LlamaCppGenerator&) = delete;
    LlamaCppGenerator(LlamaCppGenerator&&) noexcept;
    LlamaCppGenerator& operator=(LlamaCppGenerator&&) noexcept;

    // ITextGenerator interface
    GenerationResult generate(
        const std::string& prompt,
        const GenerationOptions& options
    ) override;

    bool is_ready() const noexcept override;
    const char* name() const noexcept override;
    int context_size() const noexcept override;

    // Adaptive query loop methods
    bool inject_system_prompt(const std::string& prompt) override;
    bool append_context(const std::string& text) override;
    float probe_confidence(const std::string& context, const std::string& query) override;
    GenerationResult generate_from_context(const std::string& query, const GenerationOptions& options = GenerationOptions{}) override;
    void clear_context() override;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_LLAMACPP_GENERATOR_H
