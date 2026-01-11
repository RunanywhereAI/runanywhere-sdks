#include "llamacpp_backend.h"

#include "common.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <string>

#include "../logger.h"

// Use the unified logging system
#define LOGI(...) RA_LOG_INFO("LLM.LlamaCpp", __VA_ARGS__)
#define LOGE(...) RA_LOG_ERROR("LLM.LlamaCpp", __VA_ARGS__)

namespace runanywhere {

// =============================================================================
// UTF-8 VALIDATION HELPER
// =============================================================================

static bool is_valid_utf8(const char* string) {
    if (!string)
        return true;

    const unsigned char* bytes = (const unsigned char*)string;
    int num;

    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) {
            num = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            num = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            num = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            num = 4;
        } else {
            return false;
        }

        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80)
                return false;
            bytes += 1;
        }
    }
    return true;
}

// =============================================================================
// LOG CALLBACK
// =============================================================================

static void llama_log_callback(ggml_log_level level, const char* fmt, void* data) {
    (void)data;

    // Strip trailing newlines from fmt for cleaner logging
    std::string msg(fmt ? fmt : "");
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
        msg.pop_back();
    }
    if (msg.empty())
        return;

    // Route llama.cpp logs through our unified logging system
    if (level == GGML_LOG_LEVEL_ERROR) {
        RA_LOG_ERROR("LLM.LlamaCpp.GGML", "%s", msg.c_str());
    } else if (level == GGML_LOG_LEVEL_WARN) {
        RA_LOG_WARNING("LLM.LlamaCpp.GGML", "%s", msg.c_str());
    } else if (level == GGML_LOG_LEVEL_INFO) {
        RA_LOG_DEBUG("LLM.LlamaCpp.GGML", "%s", msg.c_str());
    }
}

// =============================================================================
// LLAMACPP BACKEND IMPLEMENTATION
// =============================================================================

LlamaCppBackend::LlamaCppBackend() {
    LOGI("LlamaCppBackend created");
}

LlamaCppBackend::~LlamaCppBackend() {
    cleanup();
    LOGI("LlamaCppBackend destroyed");
}

BackendInfo LlamaCppBackend::get_info() const {
    BackendInfo info;
    info.name = "llamacpp";
    info.version = "1.0.0";
    info.description = "LLM inference via llama.cpp";
    info.supported_capabilities = {CapabilityType::TEXT_GENERATION};
    info.metadata = {{"llama_cpp_build", llama_print_system_info()}};
    return info;
}

bool LlamaCppBackend::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_) {
        LOGI("LlamaCppBackend already initialized");
        return true;
    }

    config_ = config;

    // Initialize llama.cpp backend
    llama_backend_init();
    llama_log_set(llama_log_callback, nullptr);

    // Get number of threads
    if (config.contains("num_threads")) {
        num_threads_ = config["num_threads"].get<int>();
    }

    if (num_threads_ <= 0) {
#ifdef _SC_NPROCESSORS_ONLN
        num_threads_ = std::max(1, std::min(8, (int)sysconf(_SC_NPROCESSORS_ONLN) - 2));
#else
        num_threads_ = 4;
#endif
    }

    LOGI("LlamaCppBackend initialized with %d threads", num_threads_);

    // Create capabilities
    create_capabilities();

    initialized_ = true;
    return true;
}

bool LlamaCppBackend::is_initialized() const {
    return initialized_;
}

void LlamaCppBackend::cleanup() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!initialized_) {
        return;
    }

    clear_capabilities();
    llama_backend_free();

    initialized_ = false;
    LOGI("LlamaCppBackend cleaned up");
}

ra_device_type LlamaCppBackend::get_device_type() const {
#if defined(GGML_USE_METAL)
    return RA_DEVICE_METAL;
#elif defined(GGML_USE_CUDA)
    return RA_DEVICE_CUDA;
#else
    return RA_DEVICE_CPU;
#endif
}

size_t LlamaCppBackend::get_memory_usage() const {
    // TODO: Track actual memory usage from llama.cpp
    return 0;
}

void LlamaCppBackend::create_capabilities() {
    // Register TEXT_GENERATION capability
    register_capability(CapabilityType::TEXT_GENERATION,
                        std::make_unique<LlamaCppTextGeneration>(this));
    LOGI("Registered TEXT_GENERATION capability");
}

// =============================================================================
// TEXT GENERATION IMPLEMENTATION
// =============================================================================

LlamaCppTextGeneration::LlamaCppTextGeneration(LlamaCppBackend* backend) : backend_(backend) {
    LOGI("LlamaCppTextGeneration created");
}

LlamaCppTextGeneration::~LlamaCppTextGeneration() {
    unload_model();
    LOGI("LlamaCppTextGeneration destroyed");
}

bool LlamaCppTextGeneration::is_ready() const {
    return model_loaded_ && model_ != nullptr && context_ != nullptr;
}

bool LlamaCppTextGeneration::load_model(const std::string& model_path,
                                        const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (model_loaded_) {
        LOGI("Unloading previous model before loading new one");
        unload_model_internal();  // Use internal method - no unlock/relock needed
    }

    LOGI("Loading model from: %s", model_path.c_str());

    // Parse config (context_size handled after model load)
    int user_context_size = 0;  // 0 means auto-detect
    if (config.contains("context_size")) {
        user_context_size = config["context_size"].get<int>();
    }
    if (config.contains("max_context_size")) {
        max_default_context_ = config["max_context_size"].get<int>();
    }
    if (config.contains("temperature")) {
        temperature_ = config["temperature"].get<float>();
    }
    if (config.contains("min_p")) {
        min_p_ = config["min_p"].get<float>();
    }
    if (config.contains("top_p")) {
        top_p_ = config["top_p"].get<float>();
    }
    if (config.contains("top_k")) {
        top_k_ = config["top_k"].get<int>();
    }

    model_config_ = config;
    model_path_ = model_path;

    // Load model first (needed to query training context)
    llama_model_params model_params = llama_model_default_params();
    model_ = llama_model_load_from_file(model_path.c_str(), model_params);

    if (!model_) {
        LOGE("Failed to load model from: %s", model_path.c_str());
        return false;
    }

    // Query model's training context size (like LLM.swift does)
    int model_train_ctx = llama_model_n_ctx_train(model_);
    LOGI("Model training context size: %d", model_train_ctx);

    // Determine final context size:
    // 1. If user provided context_size in config, use min(user_provided, model_train_ctx)
    // 2. Otherwise, use model's training context (capped at max_default_context_ to avoid OOM)
    if (user_context_size > 0) {
        // User explicitly requested a context size - respect it but cap at model's training context
        context_size_ = std::min(user_context_size, model_train_ctx);
        LOGI("Using user-provided context size: %d (requested: %d, model max: %d)", context_size_,
             user_context_size, model_train_ctx);
    } else {
        // Auto-detect: use model's training context, capped at max_default_context_
        context_size_ = std::min(model_train_ctx, max_default_context_);
        LOGI("Auto-detected context size: %d (model: %d, cap: %d)", context_size_, model_train_ctx,
             max_default_context_);
    }

    // Create context with determined size
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size_;
    // Batch size: use context_size but cap at 512 for memory efficiency on mobile
    ctx_params.n_batch = std::min(context_size_, 512);
    ctx_params.n_threads = backend_->get_num_threads();
    ctx_params.n_threads_batch = backend_->get_num_threads();
    ctx_params.no_perf = true;

    context_ = llama_init_from_model(model_, ctx_params);

    if (!context_) {
        LOGE("Failed to create context");
        llama_model_free(model_);
        model_ = nullptr;
        return false;
    }

    // Create sampler chain (order matters! LLM.swift does: penalties -> top_k -> top_p -> temp ->
    // dist)
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler_ = llama_sampler_chain_init(sparams);

    if (temperature_ > 0.0f) {
        // 1. CRITICAL: Add repetition penalty FIRST (prevents infinite loops like Qwen)
        // Parameters: last_n tokens to check (64), repeat_penalty (1.2), freq_penalty (0),
        // presence_penalty (0)
        llama_sampler_chain_add(sampler_, llama_sampler_init_penalties(64, 1.2f, 0.0f, 0.0f));

        // 2. Top-K sampling
        if (top_k_ > 0) {
            llama_sampler_chain_add(sampler_, llama_sampler_init_top_k(top_k_));
        }

        // 3. Top-P (nucleus) sampling - matches LLM.swift's default of 0.95
        llama_sampler_chain_add(sampler_, llama_sampler_init_top_p(top_p_, 1));

        // 4. Temperature
        llama_sampler_chain_add(sampler_, llama_sampler_init_temp(temperature_));

        // 5. Distribution sampler (final selection)
        llama_sampler_chain_add(sampler_, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    } else {
        // Greedy sampling (no randomness)
        llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());
    }

    LOGI("Sampler chain: penalties(64,1.2) -> top_k(%d) -> top_p(%.2f) -> temp(%.2f) -> dist",
         top_k_, top_p_, temperature_);

    model_loaded_ = true;
    LOGI("Model loaded successfully: context_size=%d, temp=%.2f", context_size_, temperature_);

    return true;
}

bool LlamaCppTextGeneration::is_model_loaded() const {
    return model_loaded_;
}

bool LlamaCppTextGeneration::unload_model_internal() {
    // Internal method - caller must hold mutex_
    if (!model_loaded_) {
        return true;
    }

    LOGI("Unloading model");

    if (sampler_) {
        llama_sampler_free(sampler_);
        sampler_ = nullptr;
    }

    if (context_) {
        llama_free(context_);
        context_ = nullptr;
    }

    if (model_) {
        llama_model_free(model_);
        model_ = nullptr;
    }

    model_loaded_ = false;
    model_path_.clear();

    LOGI("Model unloaded");
    return true;
}

bool LlamaCppTextGeneration::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);
    return unload_model_internal();
}

std::string LlamaCppTextGeneration::build_prompt(const TextGenerationRequest& request) {
    // ALWAYS apply chat template for proper model behavior
    // Models like Qwen and LFM2 are trained on ChatML format and REQUIRE it
    // Without proper chat template, models produce nonsense or infinite loops

    std::vector<std::pair<std::string, std::string>> messages;

    if (!request.messages.empty()) {
        // Use provided messages
        messages = request.messages;
    } else if (!request.prompt.empty()) {
        // Convert single prompt to a user message for chat template
        // This is CRITICAL for models trained on chat formats (Qwen, LFM2, etc.)
        messages.push_back({"user", request.prompt});
        LOGI("Converted prompt to user message for chat template");
    } else {
        LOGE("No prompt or messages provided");
        return "";
    }

    // Apply chat template (reads model's tokenizer.chat_template from GGUF metadata)
    std::string formatted = apply_chat_template(messages, request.system_prompt, true);
    LOGI("Applied chat template, formatted prompt length: %zu", formatted.length());

    return formatted;
}

std::string LlamaCppTextGeneration::apply_chat_template(
    const std::vector<std::pair<std::string, std::string>>& messages,
    const std::string& system_prompt, bool add_assistant_token) {
    std::vector<llama_chat_message> chat_messages;

    // Store transformed strings to extend their lifetime until after llama_chat_apply_template
    // returns This fixes potential dangling pointer issues with temporary strings
    std::vector<std::string> role_storage;
    role_storage.reserve(messages.size());

    // Add system prompt if provided
    if (!system_prompt.empty()) {
        chat_messages.push_back({"system", system_prompt.c_str()});
    }

    // Add messages
    for (const auto& [role, content] : messages) {
        std::string role_lower = role;
        std::transform(role_lower.begin(), role_lower.end(), role_lower.begin(), ::tolower);
        role_storage.push_back(std::move(role_lower));
        chat_messages.push_back({role_storage.back().c_str(), content.c_str()});
    }

    // Get chat template from model metadata
    std::string model_template;
    model_template.resize(2048);
    int32_t template_len = llama_model_meta_val_str(model_, "tokenizer.chat_template",
                                                    model_template.data(), model_template.size());

    const char* tmpl_to_use = nullptr;
    if (template_len > 0) {
        model_template.resize(template_len);
        tmpl_to_use = model_template.c_str();
    }

    // Apply template
    std::string formatted;
    formatted.resize(1024 * 256);  // 256KB buffer

    int32_t result =
        llama_chat_apply_template(tmpl_to_use, chat_messages.data(), chat_messages.size(),
                                  add_assistant_token, formatted.data(), formatted.size());

    if (result < 0) {
        LOGE("llama_chat_apply_template failed: %d", result);
        // Fallback to simple concatenation
        std::string fallback;
        for (const auto& msg : chat_messages) {
            fallback += std::string(msg.role) + ": " + msg.content + "\n";
        }
        if (add_assistant_token) {
            fallback += "assistant: ";
        }
        return fallback;
    }

    if (result > (int32_t)formatted.size()) {
        // Resize and retry
        formatted.resize(result + 1024);
        result = llama_chat_apply_template(tmpl_to_use, chat_messages.data(), chat_messages.size(),
                                           add_assistant_token, formatted.data(), formatted.size());
    }

    if (result > 0) {
        formatted.resize(result);
    }

    return formatted;
}

TextGenerationResult LlamaCppTextGeneration::generate(const TextGenerationRequest& request) {
    TextGenerationResult result;
    result.finish_reason = "error";

    std::string generated_text;
    int tokens_generated = 0;
    int prompt_tokens = 0;

    auto start_time = std::chrono::high_resolution_clock::now();

    bool success = generate_stream(
        request,
        [&](const std::string& token) -> bool {
            generated_text += token;
            tokens_generated++;
            return !cancel_requested_.load();
        },
        &prompt_tokens);

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    result.text = generated_text;
    result.tokens_generated = tokens_generated;
    result.prompt_tokens = prompt_tokens;
    result.inference_time_ms = duration.count();

    if (cancel_requested_.load()) {
        result.finish_reason = "cancelled";
    } else if (success) {
        result.finish_reason = tokens_generated >= request.max_tokens ? "length" : "stop";
    }

    return result;
}

bool LlamaCppTextGeneration::generate_stream(const TextGenerationRequest& request,
                                             TextStreamCallback callback,
                                             int* out_prompt_tokens) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!is_ready()) {
        LOGE("Model not ready for generation");
        return false;
    }

    cancel_requested_.store(false);

    // Build the prompt
    std::string prompt = build_prompt(request);
    LOGI("Generating with prompt length: %zu", prompt.length());

    // Tokenize
    const auto tokens_list = common_tokenize(context_, prompt, true, true);

    int n_ctx = llama_n_ctx(context_);
    int prompt_tokens = static_cast<int>(tokens_list.size());

    // Output prompt tokens count if requested
    if (out_prompt_tokens) {
        *out_prompt_tokens = prompt_tokens;
    }

    // Calculate available space for generation (leave small buffer for safety)
    int available_tokens = n_ctx - prompt_tokens - 4;  // -4 for EOS/BOS margin

    if (available_tokens <= 0) {
        LOGE("Prompt too long: %d tokens, context size: %d", prompt_tokens, n_ctx);
        return false;
    }

    // Cap max_tokens to available space (like LLM.swift does)
    int effective_max_tokens = std::min(request.max_tokens, available_tokens);
    if (effective_max_tokens < request.max_tokens) {
        LOGI("Capping max_tokens: %d → %d (context=%d, prompt=%d tokens)", request.max_tokens,
             effective_max_tokens, n_ctx, prompt_tokens);
    }
    LOGI("Generation: prompt_tokens=%d, max_tokens=%d, context=%d", prompt_tokens,
         effective_max_tokens, n_ctx);

    // Create batch
    llama_batch batch = llama_batch_init(n_ctx, 0, 1);

    // Clear batch and add prompt tokens
    batch.n_tokens = 0;
    for (size_t i = 0; i < tokens_list.size(); i++) {
        common_batch_add(batch, tokens_list[i], i, {0}, false);
    }
    batch.logits[batch.n_tokens - 1] = true;

    // Evaluate prompt
    if (llama_decode(context_, batch) != 0) {
        LOGE("llama_decode failed for prompt");
        llama_batch_free(batch);
        return false;
    }

    // CRITICAL: Reset sampler state before generation (like LLM.swift does)
    // This clears any accumulated state from previous generations
    llama_sampler_reset(sampler_);

    const auto vocab = llama_model_get_vocab(model_);
    std::string cached_token_chars;
    std::string accumulated_text;  // For stop sequence detection
    int n_cur = batch.n_tokens;
    int tokens_generated = 0;

    // Generation loop (use effective_max_tokens which is capped to available context)
    while (tokens_generated < effective_max_tokens && !cancel_requested_.load()) {
        // Sample next token
        const llama_token new_token_id = llama_sampler_sample(sampler_, context_, -1);

        // CRITICAL: Tell sampler about this token (for repetition penalty tracking)
        // Without this, the repetition penalty can't track what tokens have been generated
        llama_sampler_accept(sampler_, new_token_id);

        // Check for end of generation
        if (llama_vocab_is_eog(vocab, new_token_id)) {
            LOGI("End of generation token received");
            break;
        }

        // Convert token to text
        auto new_token_chars = common_token_to_piece(context_, new_token_id);
        cached_token_chars += new_token_chars;
        accumulated_text += new_token_chars;

        // Check for stop sequences (common chat template end tokens)
        // These are model-specific sequences that indicate end of assistant response
        static const std::vector<std::string> stop_sequences = {
            "<|im_end|>",     // Qwen/ChatML format
            "<|eot_id|>",     // Llama 3 format
            "</s>",           // Common end of sequence
            "<|end|>",        // Phi format
            "<|endoftext|>",  // GPT format
            "\n\nUser:",      // Some instruct formats
            "\n\nHuman:",     // Claude-style format
        };

        bool hit_stop_sequence = false;
        for (const auto& stop_seq : stop_sequences) {
            // Check if stop sequence appears in accumulated text
            size_t pos = accumulated_text.find(stop_seq);
            if (pos != std::string::npos) {
                LOGI("Stop sequence detected: %s", stop_seq.c_str());
                // Emit any text before the stop sequence that hasn't been emitted yet
                // (This handles partial token accumulation)
                hit_stop_sequence = true;
                break;
            }
        }

        if (hit_stop_sequence) {
            break;
        }

        // Emit token if valid UTF-8
        if (is_valid_utf8(cached_token_chars.c_str())) {
            if (!callback(cached_token_chars)) {
                LOGI("Generation cancelled by callback");
                cancel_requested_.store(true);
                break;
            }
            cached_token_chars.clear();
        }

        // Prepare next batch
        batch.n_tokens = 0;
        common_batch_add(batch, new_token_id, n_cur, {0}, true);

        n_cur++;
        tokens_generated++;

        // Decode
        if (llama_decode(context_, batch) != 0) {
            LOGE("llama_decode failed during generation");
            break;
        }
    }

    // Emit any remaining cached characters
    if (!cached_token_chars.empty() && is_valid_utf8(cached_token_chars.c_str())) {
        callback(cached_token_chars);
    }

    // Clear KV cache for next generation (new API in llama.cpp b7199+)
    llama_memory_clear(llama_get_memory(context_), true);

    llama_batch_free(batch);

    LOGI("Generation complete: %d tokens", tokens_generated);
    return !cancel_requested_.load();
}

void LlamaCppTextGeneration::cancel() {
    cancel_requested_.store(true);
    LOGI("Generation cancel requested");
}

nlohmann::json LlamaCppTextGeneration::get_model_info() const {
    if (!model_loaded_ || !model_) {
        return {};
    }

    nlohmann::json info;
    info["path"] = model_path_;
    info["context_size"] = context_size_;
    info["model_training_context"] = llama_model_n_ctx_train(model_);  // Expose to SDK
    info["max_default_context"] = max_default_context_;
    info["temperature"] = temperature_;
    info["top_k"] = top_k_;
    info["top_p"] = top_p_;
    info["min_p"] = min_p_;

    // Get model metadata
    char buf[256];
    if (llama_model_meta_val_str(model_, "general.name", buf, sizeof(buf)) > 0) {
        info["name"] = std::string(buf);
    }
    if (llama_model_meta_val_str(model_, "general.architecture", buf, sizeof(buf)) > 0) {
        info["architecture"] = std::string(buf);
    }

    return info;
}

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

// Factory function - creates a new LlamaCPP backend instance
// This is exported and called by the bridge to avoid singleton issues across shared libraries
std::unique_ptr<Backend> create_llamacpp_backend() {
    return std::make_unique<LlamaCppBackend>();
}

// Registration function - for static library builds (iOS)
// NOTE: For shared library builds (Android), the bridge calls create_llamacpp_backend()
// directly and registers it to avoid singleton issues
void register_llamacpp_backend() {
    static bool registered = false;
    if (registered) {
        return;
    }

    BackendRegistry::instance().register_backend("llamacpp", create_llamacpp_backend);
    LOGI("LlamaCPP backend registered");
    registered = true;
}

}  // namespace runanywhere
