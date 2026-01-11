#ifndef RUNANYWHERE_LLAMACPP_BACKEND_H
#define RUNANYWHERE_LLAMACPP_BACKEND_H

/**
 * LlamaCPP Backend - Text Generation via llama.cpp
 *
 * This backend uses llama.cpp for on-device LLM inference with GGUF/GGML models.
 *
 * Supported Capabilities:
 * - TEXT_GENERATION: Via llama.cpp with streaming support
 */

#include <llama.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include "capabilities/backend.h"
#include "capabilities/types.h"

namespace runanywhere {

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class LlamaCppTextGeneration;

// =============================================================================
// LLAMACPP BACKEND
// =============================================================================

class LlamaCppBackend : public Backend {
   public:
    LlamaCppBackend();
    ~LlamaCppBackend() override;

    // Backend interface
    BackendInfo get_info() const override;
    bool initialize(const nlohmann::json& config = {}) override;
    bool is_initialized() const override;
    void cleanup() override;

    ra_device_type get_device_type() const override;
    size_t get_memory_usage() const override;

    // Get number of threads to use
    int get_num_threads() const { return num_threads_; }

   private:
    void create_capabilities();

    bool initialized_ = false;
    nlohmann::json config_;
    int num_threads_ = 0;
    mutable std::mutex mutex_;
};

// =============================================================================
// TEXT GENERATION CAPABILITY
// =============================================================================

class LlamaCppTextGeneration : public ITextGeneration {
   public:
    explicit LlamaCppTextGeneration(LlamaCppBackend* backend);
    ~LlamaCppTextGeneration() override;

    bool is_ready() const override;
    bool load_model(const std::string& model_path, const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;

    TextGenerationResult generate(const TextGenerationRequest& request) override;
    bool generate_stream(const TextGenerationRequest& request,
                         TextStreamCallback callback) override {
        // Default implementation without prompt token output
        return generate_stream(request, callback, nullptr);
    }
    bool generate_stream(const TextGenerationRequest& request, TextStreamCallback callback,
                         int* out_prompt_tokens);
    void cancel() override;
    nlohmann::json get_model_info() const override;

   private:
    // Internal unload without locking (caller must hold mutex_)
    bool unload_model_internal();

    // Internal helper to build prompt from messages
    std::string build_prompt(const TextGenerationRequest& request);

    // Apply chat template if available
    std::string
    apply_chat_template(const std::vector<std::pair<std::string, std::string>>& messages,
                        const std::string& system_prompt, bool add_assistant_token);

    LlamaCppBackend* backend_;
    llama_model* model_ = nullptr;
    llama_context* context_ = nullptr;
    llama_sampler* sampler_ = nullptr;

    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};

    std::string model_path_;
    nlohmann::json model_config_;

    // Model parameters
    // Note: context_size_ is dynamically determined after model load:
    // 1. If user provides "context_size" in config, use min(user_provided, model_training_ctx)
    // 2. Otherwise, use model's training context (capped at max_default_context_)
    int context_size_ = 0;            // 0 = auto-detect from model
    int max_default_context_ = 8192;  // Cap for auto-detected context to avoid OOM

    // Sampling parameters (matched to LLM.swift defaults for quality)
    float temperature_ = 0.8f;  // LLM.swift default (was 0.7)
    float top_p_ = 0.95f;       // Nucleus sampling (LLM.swift default)
    float min_p_ = 0.05f;       // Minimum probability threshold
    int top_k_ = 40;            // Top-K sampling

    mutable std::mutex mutex_;
};

// =============================================================================
// BACKEND FACTORY & REGISTRATION
// =============================================================================

// Export macro for shared library builds (needed for Android)
#if defined(_WIN32)
#define RA_LLAMACPP_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RA_LLAMACPP_EXPORT __attribute__((visibility("default")))
#else
#define RA_LLAMACPP_EXPORT
#endif

/**
 * Creates a new LlamaCPP backend instance.
 *
 * This factory function is called by the bridge to create backend instances.
 * The registration is done by the bridge itself to avoid singleton issues
 * across shared libraries.
 */
RA_LLAMACPP_EXPORT std::unique_ptr<Backend> create_llamacpp_backend();

/**
 * Explicitly registers the LlamaCPP backend with the BackendRegistry.
 *
 * NOTE: For shared library builds (Android), prefer calling create_llamacpp_backend()
 * from the bridge and letting the bridge register it. This function calls
 * BackendRegistry::instance() which may create a separate singleton in each .so.
 *
 * For static library builds (iOS), this function works correctly.
 */
RA_LLAMACPP_EXPORT void register_llamacpp_backend();

}  // namespace runanywhere

#endif  // RUNANYWHERE_LLAMACPP_BACKEND_H
