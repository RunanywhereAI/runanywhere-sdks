#ifndef RUNANYWHERE_LLAMACPP_BACKEND_H
#define RUNANYWHERE_LLAMACPP_BACKEND_H

/**
 * LlamaCPP Backend - Text Generation via llama.cpp
 *
 * This backend uses llama.cpp for on-device LLM inference with GGUF/GGML models.
 * Internal C++ implementation that is wrapped by the RAC API (rac_llm_llamacpp.cpp).
 */

#include <llama.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace runanywhere {

// =============================================================================
// DEVICE TYPES (internal use only)
// =============================================================================

enum class DeviceType {
    CPU = 0,
    GPU = 1,
    METAL = 3,
    CUDA = 4,
    WEBGPU = 5,
};

// =============================================================================
// TEXT GENERATION TYPES (internal use only)
// =============================================================================

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
};

struct TextGenerationResult {
    std::string text;
    int tokens_generated = 0;
    int prompt_tokens = 0;
    double inference_time_ms = 0.0;
    std::string finish_reason;  // "stop", "length", "cancelled"
};

// Streaming callback: receives token, returns false to cancel
using TextStreamCallback = std::function<bool(const std::string& token)>;

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class LlamaCppTextGeneration;

// =============================================================================
// LLAMACPP BACKEND
// =============================================================================

class LlamaCppBackend {
   public:
    LlamaCppBackend();
    ~LlamaCppBackend();

    // Initialize the backend
    bool initialize(const nlohmann::json& config = {});
    bool is_initialized() const;
    void cleanup();

    DeviceType get_device_type() const;
    size_t get_memory_usage() const;

    // Get number of threads to use
    int get_num_threads() const { return num_threads_; }

    // Get text generation capability
    LlamaCppTextGeneration* get_text_generation() { return text_gen_.get(); }

   private:
    void create_text_generation();

    bool initialized_ = false;
    nlohmann::json config_;
    int num_threads_ = 0;
    std::unique_ptr<LlamaCppTextGeneration> text_gen_;
    mutable std::mutex mutex_;
};

// =============================================================================
// TEXT GENERATION IMPLEMENTATION
// =============================================================================

class LlamaCppTextGeneration {
   public:
    explicit LlamaCppTextGeneration(LlamaCppBackend* backend);
    ~LlamaCppTextGeneration();

    bool is_ready() const;
    bool load_model(const std::string& model_path, const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();

    TextGenerationResult generate(const TextGenerationRequest& request);
    bool generate_stream(const TextGenerationRequest& request, TextStreamCallback callback) {
        return generate_stream(request, callback, nullptr);
    }
    bool generate_stream(const TextGenerationRequest& request, TextStreamCallback callback,
                         int* out_prompt_tokens);
    void cancel();
    nlohmann::json get_model_info() const;

   private:
    bool unload_model_internal();
    std::string build_prompt(const TextGenerationRequest& request);
    std::string apply_chat_template(const std::vector<std::pair<std::string, std::string>>& messages,
                                    const std::string& system_prompt, bool add_assistant_token);

    LlamaCppBackend* backend_;
    llama_model* model_ = nullptr;
    llama_context* context_ = nullptr;
    llama_sampler* sampler_ = nullptr;

    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    std::atomic<bool> decode_failed_{false};

    std::string model_path_;
    nlohmann::json model_config_;

    int context_size_ = 0;
    int max_default_context_ = 8192;

    mutable std::mutex mutex_;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_LLAMACPP_BACKEND_H
