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
        llama_clear_adapter_lora(context_);
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

float LlamaCppTextGeneration::probe_confidence(const std::string& context,
                                               const std::string& query) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!is_ready()) {
        LOGE("probe_confidence: model not ready");
        return 0.5f;
    }

    const std::string probe_prompt =
        context + "\n" + query + "\nDoes this answer the question? (Yes/No):";

    LOGI("probe_confidence: prompt_len=%zu", probe_prompt.size());

    const auto probe_tokens = common_tokenize(context_, probe_prompt, false, false);

    if (probe_tokens.empty()) {
        LOGE("probe_confidence: tokenization produced no tokens");
        return 0.5f;
    }

    const int n_ctx = llama_n_ctx(context_);
    const int n_probe = static_cast<int>(probe_tokens.size());

    if (n_probe >= n_ctx) {
        LOGE("probe_confidence: probe prompt too long (%d tokens, ctx=%d)", n_probe, n_ctx);
        return 0.5f;
    }

    llama_memory_t mem = llama_get_memory(context_);
    const llama_pos probe_start_pos = mem
        ? (llama_memory_seq_pos_max(mem, 0) + 1)
        : 0;

    llama_batch batch = llama_batch_init(n_ctx, 0, 1);
    batch.n_tokens = 0;

    for (int i = 0; i < n_probe; ++i) {
        const bool need_logits = (i == n_probe - 1);
        common_batch_add(batch, probe_tokens[i], probe_start_pos + i, {0}, need_logits);
    }

    if (llama_decode(context_, batch) != 0) {
        LOGE("probe_confidence: llama_decode failed");
        llama_batch_free(batch);
        return 0.5f;
    }

    llama_batch_free(batch);

    float* logits = llama_get_logits_ith(context_, -1);
    if (!logits) {
        LOGE("probe_confidence: failed to get logits");
        if (mem) {
            llama_memory_seq_rm(mem, 0, probe_start_pos, -1);
        }
        return 0.5f;
    }

    const auto vocab = llama_model_get_vocab(model_);
    const int32_t n_vocab = llama_vocab_n_tokens(vocab);

    auto get_first_token = [&](const std::string& word) -> llama_token {
        std::vector<llama_token> toks(8);
        int n = llama_tokenize(vocab, word.c_str(), static_cast<int32_t>(word.size()),
                               toks.data(), static_cast<int32_t>(toks.size()),
                               false,  // add_special
                               false); // parse_special
        if (n > 0 && toks[0] >= 0 && toks[0] < n_vocab) return toks[0];
        return -1;
    };

    llama_token yes_token = get_first_token(" Yes");
    if (yes_token < 0) yes_token = get_first_token("Yes");

    llama_token no_token = get_first_token(" No");
    if (no_token < 0) no_token = get_first_token("No");

    float confidence = 0.5f;

    if (yes_token >= 0 && yes_token < n_vocab && no_token >= 0 && no_token < n_vocab) {
        const float logit_yes = logits[yes_token];
        const float logit_no  = logits[no_token];
        const float max_logit = std::max(logit_yes, logit_no);
        const float exp_yes   = std::exp(logit_yes - max_logit);
        const float exp_no    = std::exp(logit_no  - max_logit);
        confidence = exp_yes / (exp_yes + exp_no);
        LOGI("probe_confidence: yes_token=%d, no_token=%d, logit_yes=%.4f, logit_no=%.4f, confidence=%.4f",
             yes_token, no_token, logit_yes, logit_no, confidence);
    } else {
        LOGE("probe_confidence: could not find Yes/No tokens (yes=%d, no=%d)", yes_token, no_token);
    }

    if (mem) {
        llama_memory_seq_rm(mem, 0, probe_start_pos, -1);
        LOGI("probe_confidence: removed probe tokens from KV cache (pos %d onwards)", probe_start_pos);
    }

    return confidence;
}

bool LlamaCppTextGeneration::inject_system_prompt(const std::string& prompt) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!is_ready()) {
        LOGE("inject_system_prompt: model not ready");
        return false;
    }

    llama_memory_t mem = llama_get_memory(context_);
    if (mem) {
        llama_memory_clear(mem, true);
    }

    const auto tokens = common_tokenize(context_, prompt, true, true);
    const int n_tokens = static_cast<int>(tokens.size());

    if (n_tokens <= 0) {
        LOGE("inject_system_prompt: tokenization produced no tokens");
        return false;
    }

    const int n_ctx = llama_n_ctx(context_);
    if (n_tokens >= n_ctx) {
        LOGE("inject_system_prompt: prompt too long (%d tokens, ctx=%d)", n_tokens, n_ctx);
        return false;
    }

    llama_batch batch = llama_batch_init(n_ctx, 0, 1);
    batch.n_tokens = 0;

    for (int i = 0; i < n_tokens; ++i) {
        common_batch_add(batch, tokens[i], i, {0}, false);
    }

    if (llama_decode(context_, batch) != 0) {
        LOGE("inject_system_prompt: llama_decode failed");
        llama_batch_free(batch);
        return false;
    }

    llama_batch_free(batch);
    LOGI("inject_system_prompt: injected %d tokens into KV cache", n_tokens);
    return true;
}

bool LlamaCppTextGeneration::append_context(const std::string& text) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!is_ready()) {
        LOGE("append_context: model not ready");
        return false;
    }

    llama_memory_t mem = llama_get_memory(context_);
    const llama_pos start_pos = mem ? (llama_memory_seq_pos_max(mem, 0) + 1) : 0;

    const auto tokens = common_tokenize(context_, text, false, false);
    const int n_tokens = static_cast<int>(tokens.size());

    if (n_tokens <= 0) {
        return true;
    }

    const int n_ctx = llama_n_ctx(context_);
    if (start_pos + n_tokens >= n_ctx) {
        LOGE("append_context: context full (pos=%d, tokens=%d, ctx=%d)", start_pos, n_tokens, n_ctx);
        return false;
    }

    llama_batch batch = llama_batch_init(n_ctx, 0, 1);
    batch.n_tokens = 0;

    for (int i = 0; i < n_tokens; ++i) {
        common_batch_add(batch, tokens[i], start_pos + i, {0}, false);
    }

    if (llama_decode(context_, batch) != 0) {
        LOGE("append_context: llama_decode failed");
        llama_batch_free(batch);
        return false;
    }

    llama_batch_free(batch);
    LOGI("append_context: appended %d tokens at pos %d", n_tokens, start_pos);
    return true;
}

TextGenerationResult LlamaCppTextGeneration::generate_from_context(const TextGenerationRequest& request) {
    std::lock_guard<std::mutex> lock(mutex_);

    TextGenerationResult result;
    result.finish_reason = "error";

    if (!is_ready()) {
        LOGE("generate_from_context: model not ready");
        return result;
    }

    cancel_requested_.store(false);
    decode_failed_ = false;

    const std::string prompt = build_prompt(request);

    const auto tokens = common_tokenize(context_, prompt, false, false);
    const int n_prompt = static_cast<int>(tokens.size());

    if (n_prompt <= 0) {
        LOGE("generate_from_context: failed to tokenize prompt");
        return result;
    }

    llama_memory_t mem = llama_get_memory(context_);
    const llama_pos current_pos = mem ? (llama_memory_seq_pos_max(mem, 0) + 1) : 0;

    const int n_ctx = llama_n_ctx(context_);
    const int available_tokens = n_ctx - static_cast<int>(current_pos) - n_prompt - 4;

    if (available_tokens <= 0) {
        LOGE("generate_from_context: no space for generation (pos=%d, prompt=%d, ctx=%d)",
             static_cast<int>(current_pos), n_prompt, n_ctx);
        return result;
    }

    const int effective_max_tokens = std::min(request.max_tokens, available_tokens);
    LOGI("generate_from_context: pos=%d, prompt_tokens=%d, max_tokens=%d",
         static_cast<int>(current_pos), n_prompt, effective_max_tokens);

    llama_batch batch = llama_batch_init(n_ctx, 0, 1);
    batch.n_tokens = 0;

    for (int i = 0; i < n_prompt; ++i) {
        const bool need_logits = (i == n_prompt - 1);
        common_batch_add(batch, tokens[i], current_pos + i, {0}, need_logits);
    }

    if (llama_decode(context_, batch) != 0) {
        LOGE("generate_from_context: llama_decode failed for prompt");
        llama_batch_free(batch);
        return result;
    }

    llama_sampler* sampler = nullptr;
    {
        auto sparams = llama_sampler_chain_default_params();
        sparams.no_perf = true;
        sampler = llama_sampler_chain_init(sparams);

        if (request.temperature > 0.0f) {
            llama_sampler_chain_add(sampler,
                llama_sampler_init_penalties(64, request.repetition_penalty, 0.0f, 0.0f));
            if (request.top_k > 0) {
                llama_sampler_chain_add(sampler, llama_sampler_init_top_k(request.top_k));
            }
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(request.top_p, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(request.temperature));
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
        }
    }

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

    std::string generated_text;
    int n_cur = static_cast<int>(current_pos) + n_prompt;
    int tokens_generated = 0;
    bool stop_sequence_hit = false;

    while (tokens_generated < effective_max_tokens && !cancel_requested_.load()) {
        const llama_token new_token_id = llama_sampler_sample(sampler, context_, -1);
        llama_sampler_accept(sampler, new_token_id);

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        const std::string new_token_chars = common_token_to_piece(context_, new_token_id);
        partial_utf8_buffer.append(new_token_chars);

        struct Utf8Check {
            static size_t valid_upto(const std::string& buf) {
                static const uint8_t utf8d[] = {
                    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
                    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
                    8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
                    0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3,
                    0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,
                    0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1,
                    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1,
                    1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,
                    1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1,
                    1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                };
                uint32_t state = 0;
                size_t upto = 0;
                for (size_t i = 0; i < buf.size(); ++i) {
                    uint32_t type = utf8d[static_cast<uint8_t>(buf[i])];
                    state = utf8d[256 + state * 16 + type];
                    if (state == 0) upto = i + 1;
                }
                return upto;
            }
        };

        const size_t valid_upto = Utf8Check::valid_upto(partial_utf8_buffer);
        if (valid_upto > 0) {
            std::string valid_chunk = partial_utf8_buffer.substr(0, valid_upto);
            stop_window.append(valid_chunk);
            partial_utf8_buffer.erase(0, valid_upto);

            size_t found_stop_pos = std::string::npos;
            for (const auto& stop_seq : STOP_SEQUENCES) {
                const size_t pos = stop_window.find(stop_seq);
                if (pos != std::string::npos &&
                    (found_stop_pos == std::string::npos || pos < found_stop_pos)) {
                    found_stop_pos = pos;
                }
            }

            if (found_stop_pos != std::string::npos) {
                stop_sequence_hit = true;
                if (found_stop_pos > 0) {
                    generated_text += stop_window.substr(0, found_stop_pos);
                }
                break;
            }

            if (stop_window.size() > MAX_STOP_LEN) {
                const size_t safe_len = stop_window.size() - MAX_STOP_LEN;
                generated_text += stop_window.substr(0, safe_len);
                stop_window.erase(0, safe_len);
            }
        }

        batch.n_tokens = 0;
        common_batch_add(batch, new_token_id, n_cur, {0}, true);
        n_cur++;
        tokens_generated++;

        if (llama_decode(context_, batch) != 0) {
            LOGE("generate_from_context: llama_decode failed during generation");
            decode_failed_ = true;
            break;
        }
    }

    if (!cancel_requested_.load() && !stop_sequence_hit && !stop_window.empty()) {
        generated_text += stop_window;
    }

    llama_batch_free(batch);
    llama_sampler_free(sampler);


    result.text = generated_text;
    result.tokens_generated = tokens_generated;
    result.prompt_tokens = n_prompt;

    if (decode_failed_) {
        result.finish_reason = "error";
    } else if (cancel_requested_.load()) {
        result.finish_reason = "cancelled";
    } else {
        result.finish_reason = tokens_generated >= effective_max_tokens ? "length" : "stop";
    }

    LOGI("generate_from_context: complete, tokens=%d, reason=%s",
         tokens_generated, result.finish_reason.c_str());
    return result;
}

void LlamaCppTextGeneration::clear_context() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (context_) {
        llama_memory_t mem = llama_get_memory(context_);
        if (mem) {
            llama_memory_clear(mem, true);
        }
        LOGI("clear_context: KV cache cleared");
    }
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
    for (auto& entry : lora_adapters_) {
        int32_t result = llama_set_adapter_lora(context_, entry.adapter, entry.scale);
        if (result != 0) {
            LOGE("Failed to apply LoRA adapter: %s (error=%d)", entry.path.c_str(), result);
            entry.applied = false;
            return false;
        }
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

    // Remove from context
    int32_t result = llama_rm_adapter_lora(context_, it->adapter);
    if (result != 0) {
        LOGE("Failed to remove LoRA adapter from context: %s (error=%d)", adapter_path.c_str(), result);
        return false;
    }

    // Remove from tracking (adapter memory is freed automatically with the model
    // per llama.cpp API — llama_adapter_lora_free is deprecated since b8011)
    lora_adapters_.erase(it);

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
        llama_clear_adapter_lora(context_);
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
