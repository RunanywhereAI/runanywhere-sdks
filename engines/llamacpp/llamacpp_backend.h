#ifndef RUNANYWHERE_LLAMACPP_BACKEND_H
#define RUNANYWHERE_LLAMACPP_BACKEND_H

/**
 * LlamaCPP Backend - Text Generation via llama.cpp
 *
 * This backend uses llama.cpp for on-device LLM inference with GGUF/GGML
 * models. Internal C++ implementation that is wrapped by the RAC API
 * (rac_llm_llamacpp.cpp).
 */

#include <llama.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <type_traits>
#include <vector>

#include "common/rac_engine_device_type.h"
#include "rac/core/rac_benchmark.h"

namespace runanywhere {

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
    // Additional proto-exposed sampling knobs threaded through
    // rac_llm_options_t. 0.0 / 0 / empty = disabled (apply only when set).
    float frequency_penalty = 0.0f;
    float presence_penalty = 0.0f;
    float min_p = 0.0f;
    int64_t seed = 0;        // 0 = LLAMA_DEFAULT_SEED
    int n_threads = 0;       // 0 = backend default (model-load thread count)
    std::string grammar;     // GBNF rule text; empty = unconstrained
    std::vector<std::string> stop_sequences;
};

struct TextGenerationResult {
    std::string text;
    int tokens_generated = 0;
    int prompt_tokens = 0;
    double inference_time_ms = 0.0;
    // Time to the first produced token (~= prompt-eval / prefill time). The
    // decode phase is everything after, so decode_time_ms isolates generation
    // throughput from prefill. Mirrors the VLM backend timing split.
    double time_to_first_token_ms = 0.0;
    double decode_time_ms = 0.0;
    std::string finish_reason;  // "stop", "length", "cancelled"
};

// Verify request struct size — allocated per generate() call.
// If this fires, review whether new fields should be passed by reference
// instead.
static_assert(sizeof(TextGenerationRequest) <= 256,
              "TextGenerationRequest grew — consider passing by reference or "
              "reducing members");

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

// =============================================================================
// LORA ADAPTER ENTRY
// =============================================================================

struct LoraAdapterEntry {
    LoraAdapterEntry() = default;
    LoraAdapterEntry(const LoraAdapterEntry&) = delete;
    LoraAdapterEntry& operator=(const LoraAdapterEntry&) = delete;
    LoraAdapterEntry(LoraAdapterEntry&&) noexcept = default;
    LoraAdapterEntry& operator=(LoraAdapterEntry&&) noexcept = default;

    llama_adapter_lora* adapter = nullptr;
    std::string path;
    float scale = 1.0f;
    bool applied = false;
};

static_assert(!std::is_copy_constructible_v<LoraAdapterEntry>);
static_assert(std::is_move_constructible_v<LoraAdapterEntry>);

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

    /**
     * Generate text with streaming and optional prompt-token output.
     *
     * @param request           Generation request.
     * @param callback          Streaming callback; return false to cancel.
     * @param out_prompt_tokens Optional: tokenized prompt length (may be NULL).
     */
    bool generate_stream(const TextGenerationRequest& request, TextStreamCallback callback,
                         int* out_prompt_tokens = nullptr);

    void cancel();

    /**
     * @brief Inject a system prompt into the KV cache at position 0.
     * Clears existing KV cache first, then decodes the prompt tokens.
     * @return true on success, false on error.
     */
    bool inject_system_prompt(const std::string& prompt);

    /**
     * @brief Append text to the KV cache after current content.
     * Does not clear existing KV cache — adds at current position.
     * @return true on success, false on error.
     */
    bool append_context(const std::string& text);

    /**
     * @brief Generate a response from accumulated KV cache state.
     * Unlike generate(), does NOT clear the KV cache first.
     * @return TextGenerationResult with generated text.
     */
    TextGenerationResult generate_from_context(const TextGenerationRequest& request);

    /**
     * @brief Clear all KV cache state.
     */
    void clear_context();

    nlohmann::json get_model_info() const;

    // LoRA adapter management
    bool load_lora_adapter(const std::string& adapter_path, float scale);
    bool remove_lora_adapter(const std::string& adapter_path);
    void clear_lora_adapters();
    nlohmann::json get_lora_info() const;

   private:
    // Read model_loaded_/model_/context_ without locking; caller MUST already
    // hold mutex_. Used by internal paths (generate_stream, inject_system_prompt,
    // append_context, generate_from_context) that already lock for the
    // surrounding operation. Public is_ready() / is_model_loaded() acquire the
    // lock themselves.
    bool is_ready_locked() const;
    bool unload_model_internal();
    bool recreate_context();
    bool apply_lora_adapters();
    std::string build_prompt(const TextGenerationRequest& request);
    std::string
    apply_chat_template(const std::vector<std::pair<std::string, std::string>>& messages,
                        const std::string& system_prompt, bool add_assistant_token);

    // Shared token-decode loop used by both generate_stream() and
    // generate_from_context(). Runs the sample → EOG-check → UTF-8 assembly →
    // built-in stop-window detection → KV-decode step loop, emitting completed
    // UTF-8 chunks through @p sink (return false to cancel; sets
    // cancel_requested_). Whatever genuinely differs between the two callers is
    // passed in: the prepared sampler, the prefilled batch, the starting KV
    // position, the effective token budget, and the sink (streaming callback vs
    // accumulator). On return, KV/sampler ownership stays with the caller.
    //
    // Caller MUST already hold mutex_ and have prefilled the prompt into @p
    // batch's sequence. On return, KV/sampler ownership stays with the caller.
    //
    // @return number of output tokens generated (excludes the prompt).
    int run_decode_loop(llama_sampler* sampler, llama_batch& batch, int start_n_cur,
                        int effective_max_tokens, const TextStreamCallback& sink);

    LlamaCppBackend* backend_;
    llama_model* model_ = nullptr;
    llama_context* context_ = nullptr;
    llama_sampler* sampler_ = nullptr;

    // Cached sampler parameters — skip rebuild when unchanged
    float cached_temperature_ = -1.0f;
    float cached_top_p_ = -1.0f;
    int cached_top_k_ = -1;
    float cached_repetition_penalty_ = -1.0f;
    // Cache the extended sampling knobs too so a request that
    // changes only a penalty / min_p / seed / grammar still rebuilds the chain.
    float cached_frequency_penalty_ = -1.0f;
    float cached_presence_penalty_ = -1.0f;
    float cached_min_p_ = -1.0f;
    int64_t cached_seed_ = -1;
    std::string cached_grammar_ = "\x01";  // sentinel that no real grammar matches

    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    std::atomic<bool> decode_failed_{false};

    std::string model_path_;
    nlohmann::json model_config_;

    int context_size_ = 0;
    // Raised from 1024 to 2048 so small
    // base models like SmolLM2-360M get enough room for a chat-template
    // system+user+assistant turn (~600-900 tokens of template scaffolding
    // alone) on Web/CPU builds where common_fit_params is not used. The
    // model's own train context (e.g. 8192 for SmolLM2) is still the upper
    // ceiling — this only raises the SDK's default cap.
    int max_default_context_ = 2048;
    int batch_size_ = 0;

    std::vector<LoraAdapterEntry> lora_adapters_;

    mutable std::mutex mutex_;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_LLAMACPP_BACKEND_H
