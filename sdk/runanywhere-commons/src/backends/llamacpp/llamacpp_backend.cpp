#include "llamacpp_backend.h"

#include "common.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"

// Use the RAC logging system
#define LOGI(...) RAC_LOG_INFO("LLM.LlamaCpp", __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR("LLM.LlamaCpp", __VA_ARGS__)

namespace runanywhere {

// UTF-8 STATE MACHINE (DFA)

struct Utf8State {

    uint32_t state = 0;

    // Bjoern Hoehrmann LUT
    bool process(uint8_t byte) {
        static const uint8_t utf8d[] = {
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
            1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
            7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
            8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
            0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
            0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
            0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1, // s0..s0
            1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1, // s1..s2
            1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1, // s3..s4
            1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1, // s5..s6
            1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1, // s7..s8
        };

        uint32_t type = utf8d[byte];
        state = utf8d[256 + state * 16 + type];
        return (state == 0);
    }

    void reset() { state = 0; }
};

// =============================================================================
// LOG CALLBACK
// =============================================================================

static void llama_log_callback(ggml_log_level level, const char* fmt, void* data) {
    (void)data;

    std::string msg(fmt ? fmt : "");
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
        msg.pop_back();
    }
    if (msg.empty())
        return;

    if (level == GGML_LOG_LEVEL_ERROR) {
        RAC_LOG_ERROR("LLM.LlamaCpp.GGML", "%s", msg.c_str());
    } else if (level == GGML_LOG_LEVEL_WARN) {
        RAC_LOG_WARNING("LLM.LlamaCpp.GGML", "%s", msg.c_str());
    } else if (level == GGML_LOG_LEVEL_INFO) {
        RAC_LOG_DEBUG("LLM.LlamaCpp.GGML", "%s", msg.c_str());
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

bool LlamaCppBackend::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_) {
        LOGI("LlamaCppBackend already initialized");
        return true;
    }

    config_ = config;

    llama_backend_init();
    llama_log_set(llama_log_callback, nullptr);

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

    create_text_generation();

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

    text_gen_.reset();
    llama_backend_free();

    initialized_ = false;
    LOGI("LlamaCppBackend cleaned up");
}

DeviceType LlamaCppBackend::get_device_type() const {
#if defined(GGML_USE_METAL)
    return DeviceType::METAL;
#elif defined(GGML_USE_CUDA)
    return DeviceType::CUDA;
#elif defined(GGML_USE_WEBGPU)
    return DeviceType::WEBGPU;
#else
    return DeviceType::CPU;
#endif
}

size_t LlamaCppBackend::get_memory_usage() const {
    return 0;
}

void LlamaCppBackend::create_text_generation() {
    text_gen_ = std::make_unique<LlamaCppTextGeneration>(this);
    LOGI("Created text generation component");
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
        unload_model_internal();
    }

    LOGI("Loading model from: %s", model_path.c_str());

    int user_context_size = 0;
    if (config.contains("context_size")) {
        user_context_size = config["context_size"].get<int>();
    }
    if (config.contains("max_context_size")) {
        max_default_context_ = config["max_context_size"].get<int>();
    }

    model_config_ = config;
    model_path_ = model_path;

    llama_model_params model_params = llama_model_default_params();

#ifdef __EMSCRIPTEN__
    // CRITICAL: Disable mmap for WebAssembly builds.
    // Emscripten's mmap goes through a JS trampoline (_mmap_js).
    // JSPI can only suspend WASM frames, not JS frames, so mmap
    // during model loading causes "trying to suspend JS frames".
    // With mmap disabled, llama.cpp falls back to fread (pure WASM).
    model_params.use_mmap = false;
#endif

    // Detect model size from filename to set appropriate GPU layers BEFORE loading
    // This prevents OOM crashes on mobile devices with limited GPU memory
    // Note: We use filename heuristics here because we can't know param count until after loading
    std::string path_lower = model_path;
    std::transform(path_lower.begin(), path_lower.end(), path_lower.begin(), ::tolower);

    int gpu_layers = -1;  // Default: all layers to GPU

    // Check for large model indicators in filename using word boundary detection
    // Patterns like "7b", "8b", "13b" should match at word boundaries to avoid
    // false positives like "/backup7b/" or "/2017beta/"
    auto is_model_size_marker = [&path_lower](const char* marker) {
        size_t pos = path_lower.find(marker);
        while (pos != std::string::npos) {
            // Check for word boundary before (start of string, or non-alphanumeric)
            bool valid_start = (pos == 0) || !std::isalnum(path_lower[pos - 1]);
            // Check for word boundary after (end of string, or non-alphanumeric except digits for patterns like "7b-q4")
            size_t end_pos = pos + strlen(marker);
            bool valid_end = (end_pos >= path_lower.size()) ||
                            (!std::isalpha(path_lower[end_pos]) || path_lower[end_pos] == '-' || path_lower[end_pos] == '_');

            if (valid_start && valid_end) {
                return true;
            }
            pos = path_lower.find(marker, pos + 1);
        }
        return false;
    };

    // Detect large models (7B+) that may need GPU layer limiting on mobile
    // First check for config-based override (for custom-named models)
    bool is_large_model = false;
    if (config.contains("expected_params_billions")) {
        double expected_params = config["expected_params_billions"].get<double>();
        is_large_model = (expected_params >= 7.0);
        if (is_large_model) {
            LOGI("Large model detected from config (%.1fB expected params)", expected_params);
        }
    }

    // Fall back to filename heuristics if no config provided
    if (!is_large_model) {
        is_large_model = is_model_size_marker("7b") ||
                         is_model_size_marker("8b") ||
                         is_model_size_marker("9b") ||
                         is_model_size_marker("13b") ||
                         is_model_size_marker("70b");
    }

    if (is_large_model) {
        // For 7B+ models on mobile: limit GPU layers to prevent OOM
        // Most 7B models have 32 layers, offload ~24 to GPU, rest to CPU
        gpu_layers = 24;
        LOGI("Large model detected, limiting GPU layers to %d to prevent OOM", gpu_layers);
    }

    // Allow user override via config
    if (config.contains("gpu_layers")) {
        gpu_layers = config["gpu_layers"].get<int>();
        LOGI("Using user-provided GPU layers: %d", gpu_layers);
    }

    model_params.n_gpu_layers = gpu_layers;
    LOGI("Loading model with n_gpu_layers=%d", gpu_layers);

    model_ = llama_model_load_from_file(model_path.c_str(), model_params);

    if (!model_) {
        LOGE("Failed to load model from: %s", model_path.c_str());
        return false;
    }

    int model_train_ctx = llama_model_n_ctx_train(model_);
    LOGI("Model training context size: %d", model_train_ctx);

    // Get model parameter count to determine appropriate context size
    // Large models (7B+) need smaller context on mobile to fit in memory
    uint64_t n_params = llama_model_n_params(model_);
    double params_billions = static_cast<double>(n_params) / 1e9;
    LOGI("Model parameters: %.2fB", params_billions);

    // Post-load verification: warn if actual param count differs from filename heuristic
    bool actual_is_large = (params_billions >= 7.0);
    if (actual_is_large && !is_large_model) {
        LOGI("WARNING: Model has %.1fB params but filename didn't indicate large model. "
             "Consider using gpu_layers config for optimal performance.", params_billions);
    } else if (!actual_is_large && is_large_model) {
        LOGI("NOTE: Filename suggested large model but actual params are %.1fB. "
             "GPU layer limiting may be conservative.", params_billions);
    }

    // Adaptive context size based on model size for mobile devices
    int adaptive_max_context;
    if (params_billions >= 7.0) {
        // 7B+ models: use 2048 context to fit in ~6GB GPU memory
        adaptive_max_context = 2048;
        LOGI("Large model detected (%.1fB params), limiting context to %d for memory", params_billions, adaptive_max_context);
    } else if (params_billions >= 3.0) {
        // 3-7B models: use 4096 context
        adaptive_max_context = 4096;
        LOGI("Medium model detected (%.1fB params), limiting context to %d", params_billions, adaptive_max_context);
    } else if (params_billions >= 1.0) {
        // 1-3B models: use 2048 context (higher values OOM on mobile, especially with LoRA)
        adaptive_max_context = 2048;
        LOGI("Small-medium model detected (%.1fB params), limiting context to %d", params_billions, adaptive_max_context);
    } else {
        // Tiny models (<1B): can use larger context
        adaptive_max_context = max_default_context_;
    }

    if (user_context_size > 0) {
        context_size_ = std::min(user_context_size, model_train_ctx);
        LOGI("Using user-provided context size: %d (requested: %d, model max: %d)", context_size_,
             user_context_size, model_train_ctx);
    } else {
        context_size_ = std::min({model_train_ctx, max_default_context_, adaptive_max_context});
        LOGI("Auto-detected context size: %d (model: %d, cap: %d, adaptive: %d)", context_size_,
             model_train_ctx, max_default_context_, adaptive_max_context);
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size_;
    ctx_params.n_batch = context_size_;   // Allow processing full prompt at once
    ctx_params.n_ubatch = context_size_;  // Physical batch size must also match
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

    // Note: Sampler chain is rebuilt per-request in generate_stream() using request parameters
    // This initial sampler is not used for actual generation
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler_ = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());

    model_loaded_ = true;
    LOGI("Model loaded successfully: context_size=%d", context_size_);

    return true;
}

bool LlamaCppTextGeneration::is_model_loaded() const {
    return model_loaded_;
}

bool LlamaCppTextGeneration::unload_model_internal() {
    if (!model_loaded_) {
        return true;
    }

    LOGI("Unloading model");

    // Clear LoRA adapters from context before freeing
    // (adapter memory is freed automatically with the model per llama.cpp API)
    if (context_ && !lora_adapters_.empty()) {
        llama_set_adapters_lora(context_, nullptr, 0, nullptr);
    }
    lora_adapters_.clear();

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
    std::vector<std::pair<std::string, std::string>> messages;

    if (!request.messages.empty()) {
        messages = request.messages;
    } else if (!request.prompt.empty()) {
        messages.push_back({"user", request.prompt});
        LOGI("Converted prompt to user message for chat template");
    } else {
        LOGE("No prompt or messages provided");
        return "";
    }

    std::string formatted = apply_chat_template(messages, request.system_prompt, true);
    LOGI("Applied chat template, formatted prompt length: %zu", formatted.length());

    return formatted;
}

std::string LlamaCppTextGeneration::apply_chat_template(
    const std::vector<std::pair<std::string, std::string>>& messages,
    const std::string& system_prompt, bool add_assistant_token) {
    std::vector<llama_chat_message> chat_messages;

    std::vector<std::string> role_storage;
    role_storage.reserve(messages.size());

    if (!system_prompt.empty()) {
        chat_messages.push_back({"system", system_prompt.c_str()});
    }

    for (const auto& [role, content] : messages) {
        std::string role_lower = role;
        std::transform(role_lower.begin(), role_lower.end(), role_lower.begin(), ::tolower);
        role_storage.push_back(std::move(role_lower));
        chat_messages.push_back({role_storage.back().c_str(), content.c_str()});
    }

    std::string model_template;
    model_template.resize(2048);
    int32_t template_len = llama_model_meta_val_str(model_, "tokenizer.chat_template",
                                                    model_template.data(), model_template.size());

    const char* tmpl_to_use = nullptr;
    if (template_len > 0) {
        model_template.resize(template_len);
        tmpl_to_use = model_template.c_str();
    }

    std::string formatted;
    formatted.resize(1024 * 256);

    // llama_chat_apply_template may throw C++ exceptions for unsupported Jinja
    // template features (e.g. certain model chat templates use advanced Jinja syntax
    // that llama.cpp's minja parser cannot handle). We catch any exception and fall
    // back to a simple prompt format so generation can still proceed.
    int32_t result = -1;
    try {
        result =
            llama_chat_apply_template(tmpl_to_use, chat_messages.data(), chat_messages.size(),
                                      add_assistant_token, formatted.data(), formatted.size());
    } catch (const std::exception& e) {
        LOGE("llama_chat_apply_template threw exception: %s", e.what());
        result = -1;
    } catch (...) {
        LOGE("llama_chat_apply_template threw unknown exception");
        result = -1;
    }

    if (result < 0) {
        LOGI("Chat template failed (result=%d), using simple fallback format", result);
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
        formatted.resize(result + 1024);
        try {
            result = llama_chat_apply_template(tmpl_to_use, chat_messages.data(), chat_messages.size(),
                                               add_assistant_token, formatted.data(), formatted.size());
        } catch (...) {
            LOGE("llama_chat_apply_template threw exception on retry");
            std::string fallback;
            for (const auto& msg : chat_messages) {
                fallback += std::string(msg.role) + ": " + msg.content + "\n";
            }
            if (add_assistant_token) {
                fallback += "assistant: ";
            }
            return fallback;
        }
    }

    if (result > 0) {
        formatted.resize(result);
    }

    return formatted;
}

TextGenerationResult LlamaCppTextGeneration::generate(const TextGenerationRequest& request) {
    LOGI("generate() START: max_tokens=%d, temp=%.2f, prompt_len=%zu",
         request.max_tokens, request.temperature, request.prompt.length());

    TextGenerationResult result;
    result.finish_reason = "error";

    std::string generated_text;
    int tokens_generated = 0;
    int prompt_tokens = 0;

    auto start_time = std::chrono::high_resolution_clock::now();

    LOGI("generate(): calling generate_stream...");
    bool success = generate_stream(
        request,
        [&](const std::string& token) -> bool {
            generated_text += token;
            tokens_generated++;
            return !cancel_requested_.load();
        },
        &prompt_tokens);
    LOGI("generate(): generate_stream returned success=%d, tokens=%d", success, tokens_generated);

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    result.text = generated_text;
    result.tokens_generated = tokens_generated;
    result.prompt_tokens = prompt_tokens;
    result.inference_time_ms = duration.count();

    if (decode_failed_) {
        result.finish_reason = "error";
    } else if (cancel_requested_.load()) {
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

    // Clear KV cache before each new generation to avoid position conflicts on
    // sequential calls (fixes #356: SIGABRT on second decode on Android arm64).
    llama_memory_t mem = llama_get_memory(context_);
    if (mem) {
        llama_memory_clear(mem, true);
    }

    cancel_requested_.store(false);
    decode_failed_ = false;

    std::string prompt = build_prompt(request);
    LOGI("Generating with prompt length: %zu", prompt.length());

    const auto tokens_list = common_tokenize(context_, prompt, true, true);

    int n_ctx = llama_n_ctx(context_);
    int prompt_tokens = static_cast<int>(tokens_list.size());

    if (out_prompt_tokens) {
        *out_prompt_tokens = prompt_tokens;
    }

    int available_tokens = n_ctx - prompt_tokens - 4;

    if (available_tokens <= 0) {
        LOGE("Prompt too long: %d tokens, context size: %d", prompt_tokens, n_ctx);
        return false;
    }

    int effective_max_tokens = std::min(request.max_tokens, available_tokens);
    LOGI("Generation: prompt_tokens=%d, max_tokens=%d, context=%d",
         prompt_tokens, effective_max_tokens, n_ctx);

    LOGI("generate_stream: creating batch with n_ctx=%d", n_ctx);
    llama_batch batch = llama_batch_init(n_ctx, 0, 1);
    LOGI("generate_stream: batch created, adding %zu tokens", tokens_list.size());

    batch.n_tokens = 0;
    for (size_t i = 0; i < tokens_list.size(); i++) {
        common_batch_add(batch, tokens_list[i], i, {0}, false);
    }
    batch.logits[batch.n_tokens - 1] = true;
    LOGI("generate_stream: tokens added, n_tokens=%d", batch.n_tokens);

    LOGI("generate_stream: calling llama_decode...");
    if (llama_decode(context_, batch) != 0) {
        LOGE("llama_decode failed for prompt");
        llama_batch_free(batch);
        return false;
    }
    LOGI("generate_stream: llama_decode succeeded");

    // Configure sampler with request parameters
    if (sampler_) {
        llama_sampler_free(sampler_);
    }

    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler_ = llama_sampler_chain_init(sparams);

    if (request.temperature > 0.0f) {
        // Use default penalties (1.2f repetition) or request params if added later
        llama_sampler_chain_add(sampler_,
                                llama_sampler_init_penalties(64, request.repetition_penalty, 0.0f, 0.0f));

        if (request.top_k > 0) {
            llama_sampler_chain_add(sampler_, llama_sampler_init_top_k(request.top_k));
        }

        llama_sampler_chain_add(sampler_, llama_sampler_init_top_p(request.top_p, 1));
        llama_sampler_chain_add(sampler_, llama_sampler_init_temp(request.temperature));
        llama_sampler_chain_add(sampler_, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    } else {
        llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());
    }

    // Log generation parameters
    LOGI("[PARAMS] LLM generate_stream (per-request options): temperature=%.4f, top_p=%.4f, top_k=%d, "
         "max_tokens=%d (effective=%d), repetition_penalty=%.4f, "
         "system_prompt_len=%zu",
         request.temperature, request.top_p, request.top_k,
         request.max_tokens, effective_max_tokens, request.repetition_penalty,
         request.system_prompt.length());

    const auto vocab = llama_model_get_vocab(model_);

    static const std::vector<std::string> STOP_SEQUENCES = {
        "<|im_end|>", "<|eot_id|>", "</s>", "<|end|>", "<|endoftext|>",
        "\n\nUser:", "\n\nHuman:",
    };

    static const size_t MAX_STOP_LEN = []{
        size_t m = 0;
        for (const auto& s : STOP_SEQUENCES) m = std::max(m, s.size());
        return m;
    }();

    std::string stop_window;
    stop_window.reserve(MAX_STOP_LEN * 2);

    std::string partial_utf8_buffer;
    partial_utf8_buffer.reserve(8);

    int n_cur = batch.n_tokens;
    int tokens_generated = 0;
    bool stop_sequence_hit = false;

    while (tokens_generated < effective_max_tokens && !cancel_requested_.load()) {
        const llama_token new_token_id = llama_sampler_sample(sampler_, context_, -1);

        llama_sampler_accept(sampler_, new_token_id);

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            LOGI("End of generation token received");
            break;
        }

        const std::string new_token_chars =
            common_token_to_piece(context_, new_token_id);

        partial_utf8_buffer.append(new_token_chars);

        Utf8State scanner_state;
        size_t valid_upto = 0;
        for (size_t i = 0; i < partial_utf8_buffer.size(); ++i) {
            scanner_state.process(static_cast<uint8_t>(partial_utf8_buffer[i]));
            if (scanner_state.state == 0) {
                valid_upto = i + 1;
            }
        }

        if (valid_upto > 0) {
            std::string valid_chunk = partial_utf8_buffer.substr(0, valid_upto);
            stop_window.append(valid_chunk);
            partial_utf8_buffer.erase(0, valid_upto);

            size_t found_stop_pos = std::string::npos;
            for (const auto& stop_seq : STOP_SEQUENCES) {
                size_t pos = stop_window.find(stop_seq);
                if (pos != std::string::npos) {
                    if (found_stop_pos == std::string::npos || pos < found_stop_pos) {
                        found_stop_pos = pos;
                    }
                }
            }

            if (found_stop_pos != std::string::npos) {
                LOGI("Stop sequence detected");
                stop_sequence_hit = true;
                if (found_stop_pos > 0) {
                    if (!callback(stop_window.substr(0, found_stop_pos))) {
                        cancel_requested_.store(true);
                    }
                }
                break;
            }

            if (stop_window.size() > MAX_STOP_LEN) {
                size_t safe_len = stop_window.size() - MAX_STOP_LEN;
                if (!callback(stop_window.substr(0, safe_len))) {
                    LOGI("Generation cancelled by callback");
                    cancel_requested_.store(true);
                    break;
                }
                stop_window.erase(0, safe_len);
            }
        }

        batch.n_tokens = 0;
        common_batch_add(batch, new_token_id, n_cur, {0}, true);

        n_cur++;
        tokens_generated++;

        if (llama_decode(context_, batch) != 0) {
            LOGE("llama_decode failed during generation");
            decode_failed_ = true;
            break;
        }
    }

    if (!cancel_requested_.load() && !stop_sequence_hit && !stop_window.empty()) {
        callback(stop_window);
    }

    if (llama_memory_t post_mem = llama_get_memory(context_)) {
        llama_memory_clear(post_mem, true);
    }

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
    info["model_training_context"] = llama_model_n_ctx_train(model_);
    info["max_default_context"] = max_default_context_;

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
// LORA ADAPTER MANAGEMENT
// =============================================================================

bool LlamaCppTextGeneration::recreate_context() {
    LOGI("Recreating context to accommodate LoRA adapters");

    // Free existing sampler and context
    if (sampler_) {
        llama_sampler_free(sampler_);
        sampler_ = nullptr;
    }

    if (context_) {
        llama_free(context_);
        context_ = nullptr;
    }

    // Create new context (adapters are now visible to it)
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size_;
    ctx_params.n_batch = context_size_;
    ctx_params.n_ubatch = context_size_;
    ctx_params.n_threads = backend_->get_num_threads();
    ctx_params.n_threads_batch = backend_->get_num_threads();
    ctx_params.no_perf = true;

    context_ = llama_init_from_model(model_, ctx_params);
    if (!context_) {
        LOGE("Failed to recreate context after LoRA adapter load");
        return false;
    }

    // Rebuild sampler chain
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler_ = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());

    LOGI("Context recreated successfully");
    return true;
}

bool LlamaCppTextGeneration::apply_lora_adapters() {
    if (lora_adapters_.empty()) {
        return true;
    }

    std::vector<llama_adapter_lora*> adapters;
    std::vector<float> scales;
    adapters.reserve(lora_adapters_.size());
    scales.reserve(lora_adapters_.size());

    for (auto& entry : lora_adapters_) {
        adapters.push_back(entry.adapter);
        scales.push_back(entry.scale);
    }

    int32_t result = llama_set_adapters_lora(context_, adapters.data(),
                                             adapters.size(), scales.data());
    if (result != 0) {
        LOGE("Failed to apply LoRA adapters (error=%d)", result);
        for (auto& entry : lora_adapters_) { entry.applied = false; }
        return false;
    }

    for (auto& entry : lora_adapters_) {
        entry.applied = true;
        LOGI("Applied LoRA adapter: %s (scale=%.2f)", entry.path.c_str(), entry.scale);
    }
    return true;
}

bool LlamaCppTextGeneration::load_lora_adapter(const std::string& adapter_path, float scale) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_loaded_ || !model_) {
        LOGE("Cannot load LoRA adapter: model not loaded");
        return false;
    }

    // Check if adapter already loaded
    for (const auto& entry : lora_adapters_) {
        if (entry.path == adapter_path) {
            LOGE("LoRA adapter already loaded: %s", adapter_path.c_str());
            return false;
        }
    }

    LOGI("Loading LoRA adapter: %s (scale=%.2f)", adapter_path.c_str(), scale);

    // Load adapter against model
    llama_adapter_lora* adapter = llama_adapter_lora_init(model_, adapter_path.c_str());
    if (!adapter) {
        LOGE("Failed to load LoRA adapter from: %s", adapter_path.c_str());
        return false;
    }

    // Store adapter entry
    LoraAdapterEntry entry;
    entry.adapter = adapter;
    entry.path = adapter_path;
    entry.scale = scale;
    entry.applied = false;
    lora_adapters_.push_back(std::move(entry));

    // Recreate context so the new adapter is visible
    if (!recreate_context()) {
        // Remove the adapter entry we just added on failure
        lora_adapters_.pop_back();
        return false;
    }

    // Apply all loaded adapters to the new context
    if (!apply_lora_adapters()) {
        lora_adapters_.pop_back();
        return false;
    }

    // Clear KV cache after adapter changes
    llama_memory_clear(llama_get_memory(context_), true);

    LOGI("LoRA adapter loaded and applied: %s (%zu total adapters)",
         adapter_path.c_str(), lora_adapters_.size());
    return true;
}

bool LlamaCppTextGeneration::remove_lora_adapter(const std::string& adapter_path) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_loaded_ || !context_) {
        LOGE("Cannot remove LoRA adapter: model not loaded");
        return false;
    }

    auto it = std::find_if(lora_adapters_.begin(), lora_adapters_.end(),
                           [&adapter_path](const LoraAdapterEntry& e) { return e.path == adapter_path; });

    if (it == lora_adapters_.end()) {
        LOGE("LoRA adapter not found: %s", adapter_path.c_str());
        return false;
    }

    // Remove from tracking and re-apply remaining adapters
    lora_adapters_.erase(it);

    // Re-apply remaining adapters (or clear if none left)
    std::vector<llama_adapter_lora*> adapters;
    std::vector<float> scales;
    for (auto& entry : lora_adapters_) {
        adapters.push_back(entry.adapter);
        scales.push_back(entry.scale);
    }
    llama_set_adapters_lora(context_, adapters.empty() ? nullptr : adapters.data(),
                            adapters.size(), adapters.empty() ? nullptr : scales.data());

    // Clear KV cache after adapter changes
    llama_memory_clear(llama_get_memory(context_), true);

    LOGI("LoRA adapter removed: %s (%zu remaining)", adapter_path.c_str(), lora_adapters_.size());
    return true;
}

void LlamaCppTextGeneration::clear_lora_adapters() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (lora_adapters_.empty()) {
        return;
    }

    if (context_) {
        llama_set_adapters_lora(context_, nullptr, 0, nullptr);
        llama_memory_clear(llama_get_memory(context_), true);
    }

    lora_adapters_.clear();
    LOGI("All LoRA adapters cleared");
}

nlohmann::json LlamaCppTextGeneration::get_lora_info() const {
    std::lock_guard<std::mutex> lock(mutex_);

    nlohmann::json adapters = nlohmann::json::array();
    for (const auto& entry : lora_adapters_) {
        nlohmann::json adapter_info;
        adapter_info["path"] = entry.path;
        adapter_info["scale"] = entry.scale;
        adapter_info["applied"] = entry.applied;
        adapters.push_back(adapter_info);
    }
    return adapters;
}

}  // namespace runanywhere
