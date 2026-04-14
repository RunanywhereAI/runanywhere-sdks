#include "llamacpp_backend.h"

#include "common.h"

#include <algorithm>
#include <chrono>
#include <climits>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"

// =============================================================================
// NAMED CONSTANTS
// =============================================================================

namespace {

// Thread configuration
static constexpr int kMinThreads = 1;
static constexpr int kMaxThreads = 8;
static constexpr int kReservedCores = 2;
static constexpr int kDefaultThreads = 4;

// GPU layer limiting for large models on mobile devices
static constexpr int kLargeModelGpuLayers = 24;

// Model size thresholds (billions of parameters)
static constexpr double kLargeModelThresholdB = 7.0;
static constexpr double kMediumModelThresholdB = 3.0;
static constexpr double kSmallModelThresholdB = 1.0;

// Adaptive context sizes per model tier
static constexpr int kLargeModelContextSize = 2048;
static constexpr int kMediumModelContextSize = 4096;
static constexpr int kSmallModelContextSize = 2048;

// Generation parameters
static constexpr int kReservedEosTokens = 4;       // Tokens reserved for EOS at end of context
static constexpr int kRepeatPenaltyWindow = 64;     // Last-N tokens for repetition penalty

// Buffer sizes
static constexpr size_t kChatTemplateBufSize = 2048;
static constexpr size_t kFormattedPromptBufSize = 256 * 1024;

}  // namespace

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
    RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppBackend created");
}

LlamaCppBackend::~LlamaCppBackend() {
    cleanup();
    RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppBackend destroyed");
}

bool LlamaCppBackend::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_) {
        RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppBackend already initialized");
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
        num_threads_ = std::max(kMinThreads, std::min(kMaxThreads,
                                static_cast<int>(sysconf(_SC_NPROCESSORS_ONLN)) - kReservedCores));
#else
        num_threads_ = kDefaultThreads;
#endif
    }

    RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppBackend initialized with %d threads", num_threads_);

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
    RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppBackend cleaned up");
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
    RAC_LOG_INFO("LLM.LlamaCpp","Created text generation component");
}

// =============================================================================
// TEXT GENERATION IMPLEMENTATION
// =============================================================================

LlamaCppTextGeneration::LlamaCppTextGeneration(LlamaCppBackend* backend) : backend_(backend) {
    RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppTextGeneration created");
}

LlamaCppTextGeneration::~LlamaCppTextGeneration() {
    unload_model();
    RAC_LOG_INFO("LLM.LlamaCpp","LlamaCppTextGeneration destroyed");
}

bool LlamaCppTextGeneration::is_ready() const {
    return model_loaded_ && model_ != nullptr && context_ != nullptr;
}

bool LlamaCppTextGeneration::load_model(const std::string& model_path,
                                        const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (model_loaded_) {
        RAC_LOG_INFO("LLM.LlamaCpp","Unloading previous model before loading new one");
        unload_model_internal();
    }

    RAC_LOG_INFO("LLM.LlamaCpp","Loading model from: %s", model_path.c_str());

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

    // If llama_params_fit aborts, use the user-provided value
    int user_gpu_layers = -1;  // -1 = not set by user
    if (config.contains("gpu_layers")) {
        user_gpu_layers = config["gpu_layers"].get<int>();
        RAC_LOG_INFO("LLM.LlamaCpp", "User-provided GPU layers: %d (will apply after fit)", user_gpu_layers);
    }

    // Set up context params early for llama_params_fit
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 0;
    ctx_params.n_threads = backend_->get_num_threads();
    ctx_params.n_threads_batch = backend_->get_num_threads();
    ctx_params.no_perf = true;

    if (user_context_size > 0) {
        ctx_params.n_ctx = user_context_size;
        RAC_LOG_INFO("LLM.LlamaCpp", "User-provided context size: %d", user_context_size);
    }

    size_t n_devices = llama_max_devices();
    size_t n_overrides = llama_max_tensor_buft_overrides();

    std::vector<float> tensor_split(n_devices, 0.0f);
    // llama.cpp iterates tensor_buft_overrides until it hits a zero-valued
    // sentinel entry (pattern == nullptr). Value-initializing the vector to
    // all zeros means the first element is already that sentinel, so an
    // empty vector is interpreted as "no tensor buft overrides."
    std::vector<llama_model_tensor_buft_override> tensor_buft_overrides(n_overrides);
    std::vector<size_t> margins(n_devices, 0);

    size_t margin_mib = 1024;  // Configurable parameter
    if (config.contains("fit_margin_mib")) {
        margin_mib = config["fit_margin_mib"].get<size_t>();
    }
    for (size_t i = 0; i < n_devices; ++i) {
        margins[i] = margin_mib * 1024 * 1024;
    }

    uint32_t n_ctx_min = 2048;  // Configurable parameter
    if (config.contains("n_ctx_min")) {
        n_ctx_min = config["n_ctx_min"].get<uint32_t>();
    }

    RAC_LOG_INFO("LLM.LlamaCpp", "Calling llama_params_fit (margin=%zuMiB, n_ctx_min=%u, n_devices=%zu)",
         margin_mib, n_ctx_min, n_devices);

    llama_params_fit_status fit_status = llama_params_fit(
        model_path.c_str(),
        &model_params,
        &ctx_params,
        tensor_split.data(),
        tensor_buft_overrides.data(),
        margins.data(),
        n_ctx_min,
        GGML_LOG_LEVEL_INFO
    );

    switch (fit_status) {
        case LLAMA_PARAMS_FIT_STATUS_SUCCESS:
            RAC_LOG_INFO("LLM.LlamaCpp", "llama_params_fit SUCCESS: n_gpu_layers=%d, n_ctx=%u",
                 model_params.n_gpu_layers, ctx_params.n_ctx);
            break;
        case LLAMA_PARAMS_FIT_STATUS_FAILURE:
            RAC_LOG_INFO("LLM.LlamaCpp", "llama_params_fit FAILURE: could not fit model to device memory. "
                 "Proceeding with conservative CPU-only defaults.");
            model_params.n_gpu_layers = 0;
            if (user_context_size > 0 && user_context_size > 2048) {
                RAC_LOG_INFO("LLM.LlamaCpp", "Capping user-requested context_size=%d to 2048 after fit FAILURE",
                     user_context_size);
            }
            if (ctx_params.n_ctx == 0 || ctx_params.n_ctx > 2048) {
                ctx_params.n_ctx = 2048;
            }
            break;
        case LLAMA_PARAMS_FIT_STATUS_ERROR:
            RAC_LOG_ERROR("LLM.LlamaCpp", "llama_params_fit ERROR for model: %s. "
                 "Falling back to conservative CPU-only defaults.", model_path.c_str());
            model_params.n_gpu_layers = 0;
            if (user_context_size > 0 && user_context_size > 2048) {
                RAC_LOG_INFO("LLM.LlamaCpp", "Capping user-requested context_size=%d to 2048 after fit ERROR",
                     user_context_size);
            }
            if (ctx_params.n_ctx == 0 || ctx_params.n_ctx > 2048) {
                ctx_params.n_ctx = 2048;
            }
            break;
    }

    // Apply user gpu_layers override after fit, respecting the CPU-only build constraint.
    // llama_params_fit does not yet account for host memory in CPU-only builds
    // (upstream PR: https://github.com/ggml-org/llama.cpp/pull/19711).
#if !defined(GGML_USE_METAL) && !defined(GGML_USE_CUDA) && !defined(GGML_USE_WEBGPU)
    if (fit_status == LLAMA_PARAMS_FIT_STATUS_SUCCESS) {
        RAC_LOG_INFO("LLM.LlamaCpp", "CPU-only build: llama_params_fit fitted to GPU memory but no GPU backend active. "
             "Applying conservative CPU defaults.");
    }
    if (user_gpu_layers > 0) {
        RAC_LOG_INFO("LLM.LlamaCpp", "CPU-only build: ignoring user gpu_layers=%d (no GPU backend available)",
             user_gpu_layers);
    }
    model_params.n_gpu_layers = 0;
    if (ctx_params.n_ctx == 0 || ctx_params.n_ctx > 4096) {
        ctx_params.n_ctx = 4096;
        RAC_LOG_INFO("LLM.LlamaCpp", "CPU-only: capping context to %u", ctx_params.n_ctx);
    }
#else
    if (user_gpu_layers >= 0) {
        // llama_params_fit fell back to n_gpu_layers=0 for non-SUCCESS outcomes;
        // honouring the user override here reinstates the OOM risk the fit call
        // was supposed to prevent. Log a warning so it's visible in the event of
        // a subsequent crash/OOM, but keep honouring the user's explicit request.
        if (fit_status != LLAMA_PARAMS_FIT_STATUS_SUCCESS) {
            const char* fit_label =
                fit_status == LLAMA_PARAMS_FIT_STATUS_FAILURE ? "FAILURE" : "ERROR";
            RAC_LOG_WARNING("LLM.LlamaCpp",
                "Applying user gpu_layers=%d override despite llama_params_fit %s — risk of OOM",
                user_gpu_layers, fit_label);
        }
        model_params.n_gpu_layers = user_gpu_layers;
        RAC_LOG_INFO("LLM.LlamaCpp", "Applying user GPU layers override: %d", user_gpu_layers);
    }
#endif

    RAC_LOG_INFO("LLM.LlamaCpp", "Loading model with n_gpu_layers=%d", model_params.n_gpu_layers);

    model_ = llama_model_load_from_file(model_path.c_str(), model_params);

    if (!model_) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Failed to load model from: %s", model_path.c_str());
        return false;
    }

    int model_train_ctx = llama_model_n_ctx_train(model_);
    uint64_t n_params = llama_model_n_params(model_);
    double params_billions = static_cast<double>(n_params) / 1e9;
    RAC_LOG_INFO("LLM.LlamaCpp", "Model loaded: %.2fB params, training context=%d", params_billions, model_train_ctx);

    if (ctx_params.n_ctx == 0) {
        ctx_params.n_ctx = std::min(model_train_ctx, max_default_context_);
    }
    // ctx_params.n_ctx is uint32_t; clamp to INT_MAX before converting to int so
    // a pathological fitted/user value above ~2.1B can't wrap to a negative
    // number that `std::min` would then pick as the "smallest" context size.
    const int fitted_ctx = static_cast<int>(
        std::min(ctx_params.n_ctx, static_cast<uint32_t>(INT_MAX)));
    context_size_ = std::min({fitted_ctx, model_train_ctx, max_default_context_});

    RAC_LOG_INFO("LLM.LlamaCpp", "Final context size: %d (fitted=%u, train=%d, cap=%d)",
         context_size_, ctx_params.n_ctx, model_train_ctx, max_default_context_);

    static constexpr int MAX_BATCH_SIZE = 2048;
    static constexpr int MAX_UBATCH_SIZE = 512;
    batch_size_ = std::min(context_size_, MAX_BATCH_SIZE);

    ctx_params.n_ctx = context_size_;
    ctx_params.n_batch = batch_size_;
    ctx_params.n_ubatch = std::min(batch_size_, MAX_UBATCH_SIZE);

    RAC_LOG_INFO("LLM.LlamaCpp", "Context params: n_ctx=%d, n_batch=%d, n_ubatch=%d",
         ctx_params.n_ctx, ctx_params.n_batch, ctx_params.n_ubatch);

    context_ = llama_init_from_model(model_, ctx_params);

    if (!context_) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Failed to create context");
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
    RAC_LOG_INFO("LLM.LlamaCpp","Model loaded successfully: context_size=%d", context_size_);

    return true;
}

bool LlamaCppTextGeneration::is_model_loaded() const {
    return model_loaded_;
}

bool LlamaCppTextGeneration::unload_model_internal() {
    if (!model_loaded_) {
        return true;
    }

    RAC_LOG_INFO("LLM.LlamaCpp","Unloading model");

    // Clear LoRA adapters from context before freeing
    // (adapter memory is freed automatically with the model per llama.cpp API)
    // Best-effort during teardown: log but don't fail unload on error.
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

    RAC_LOG_INFO("LLM.LlamaCpp","Model unloaded");
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
        RAC_LOG_INFO("LLM.LlamaCpp","Converted prompt to user message for chat template");
    } else {
        RAC_LOG_ERROR("LLM.LlamaCpp","No prompt or messages provided");
        return "";
    }

    std::string formatted = apply_chat_template(messages, request.system_prompt, true);
    RAC_LOG_INFO("LLM.LlamaCpp","Applied chat template, formatted prompt length: %zu", formatted.length());

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
    model_template.resize(kChatTemplateBufSize);
    int32_t template_len = llama_model_meta_val_str(model_, "tokenizer.chat_template",
                                                    model_template.data(), model_template.size());

    const char* tmpl_to_use = nullptr;
    if (template_len > 0) {
        model_template.resize(template_len);
        tmpl_to_use = model_template.c_str();
    }

    std::string formatted;
    formatted.resize(kFormattedPromptBufSize);

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
        RAC_LOG_ERROR("LLM.LlamaCpp","llama_chat_apply_template threw exception: %s", e.what());
        result = -1;
    } catch (...) {
        RAC_LOG_ERROR("LLM.LlamaCpp","llama_chat_apply_template threw unknown exception");
        result = -1;
    }

    if (result < 0) {
        RAC_LOG_INFO("LLM.LlamaCpp","Chat template failed (result=%d), using simple fallback format", result);
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
            RAC_LOG_ERROR("LLM.LlamaCpp","llama_chat_apply_template threw exception on retry");
            result = -1;
        }

        if (result <= 0) {
            RAC_LOG_INFO("LLM.LlamaCpp","Chat template retry failed (result=%d), using simple fallback format", result);
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
    RAC_LOG_INFO("LLM.LlamaCpp","generate() START: max_tokens=%d, temp=%.2f, prompt_len=%zu",
         request.max_tokens, request.temperature, request.prompt.length());

    TextGenerationResult result;
    result.finish_reason = "error";

    std::string generated_text;
    int tokens_generated = 0;
    int prompt_tokens = 0;

    auto start_time = std::chrono::high_resolution_clock::now();

    RAC_LOG_INFO("LLM.LlamaCpp","generate(): calling generate_stream...");
    bool success = generate_stream(
        request,
        [&](const std::string& token) -> bool {
            generated_text += token;
            tokens_generated++;
            return !cancel_requested_.load();
        },
        &prompt_tokens);
    RAC_LOG_INFO("LLM.LlamaCpp","generate(): generate_stream returned success=%d, tokens=%d", success, tokens_generated);

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
        RAC_LOG_ERROR("LLM.LlamaCpp","Model not ready for generation");
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
    RAC_LOG_INFO("LLM.LlamaCpp","Generating with prompt length: %zu", prompt.length());

    const auto tokens_list = common_tokenize(context_, prompt, true, true);

    const int n_ctx = llama_n_ctx(context_);
    const int prompt_tokens = static_cast<int>(tokens_list.size());

    if (out_prompt_tokens) {
        *out_prompt_tokens = prompt_tokens;
    }

    const int available_tokens = n_ctx - prompt_tokens - kReservedEosTokens;

    if (available_tokens <= 0) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Prompt too long: %d tokens, context size: %d", prompt_tokens, n_ctx);
        return false;
    }

    const int effective_max_tokens = std::min(request.max_tokens, available_tokens);
    RAC_LOG_INFO("LLM.LlamaCpp","Generation: prompt_tokens=%d, max_tokens=%d, context=%d",
         prompt_tokens, effective_max_tokens, n_ctx);

    const int n_batch = batch_size_ > 0 ? batch_size_ : n_ctx;
    RAC_LOG_INFO("LLM.LlamaCpp", "generate_stream: processing %d prompt tokens in chunks of %d", prompt_tokens, n_batch);
    llama_batch batch = llama_batch_init(n_batch, 0, 1);

    for (int chunk_start = 0; chunk_start < prompt_tokens; chunk_start += n_batch) {
        batch.n_tokens = 0;
        int chunk_end = std::min(chunk_start + n_batch, prompt_tokens);
        bool is_last_chunk = (chunk_end == prompt_tokens);

        for (int i = chunk_start; i < chunk_end; i++) {
            bool need_logits = is_last_chunk && (i == chunk_end - 1);
            common_batch_add(batch, tokens_list[i], i, {0}, need_logits);
        }

        if (llama_decode(context_, batch) != 0) {
            RAC_LOG_ERROR("LLM.LlamaCpp", "llama_decode failed for prompt chunk [%d..%d)", chunk_start, chunk_end);
            llama_batch_free(batch);
            return false;
        }
    }
    RAC_LOG_INFO("LLM.LlamaCpp", "generate_stream: prompt decoded successfully");

    // Configure sampler with request parameters — skip rebuild if params unchanged
    {
        const bool params_match = sampler_ &&
            cached_temperature_ == request.temperature &&
            cached_top_p_ == request.top_p &&
            cached_top_k_ == request.top_k &&
            cached_repetition_penalty_ == request.repetition_penalty;

        if (!params_match) {
            if (sampler_) {
                llama_sampler_free(sampler_);
            }

            auto sparams = llama_sampler_chain_default_params();
            sparams.no_perf = true;
            sampler_ = llama_sampler_chain_init(sparams);

            if (request.temperature > 0.0f) {
                llama_sampler_chain_add(sampler_,
                                        llama_sampler_init_penalties(kRepeatPenaltyWindow, request.repetition_penalty, 0.0f, 0.0f));

                if (request.top_k > 0) {
                    llama_sampler_chain_add(sampler_, llama_sampler_init_top_k(request.top_k));
                }

                llama_sampler_chain_add(sampler_, llama_sampler_init_top_p(request.top_p, 1));
                llama_sampler_chain_add(sampler_, llama_sampler_init_temp(request.temperature));
                llama_sampler_chain_add(sampler_, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
            } else {
                llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());
            }

            cached_temperature_ = request.temperature;
            cached_top_p_ = request.top_p;
            cached_top_k_ = request.top_k;
            cached_repetition_penalty_ = request.repetition_penalty;
        }
    }

    // Log generation parameters
    RAC_LOG_INFO("LLM.LlamaCpp","[PARAMS] LLM generate_stream (per-request options): temperature=%.4f, top_p=%.4f, top_k=%d, "
         "max_tokens=%d (effective=%d), repetition_penalty=%.4f, "
         "system_prompt_len=%zu",
         request.temperature, request.top_p, request.top_k,
         request.max_tokens, effective_max_tokens, request.repetition_penalty,
         request.system_prompt.length());

    const auto* const vocab = llama_model_get_vocab(model_);

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

    // Persist UTF-8 scanner across iterations to avoid re-scanning partial bytes
    Utf8State utf8_scanner;

    int n_cur = batch.n_tokens;
    int tokens_generated = 0;
    bool stop_sequence_hit = false;

    while (tokens_generated < effective_max_tokens && !cancel_requested_.load()) {
        const llama_token new_token_id = llama_sampler_sample(sampler_, context_, -1);

        llama_sampler_accept(sampler_, new_token_id);

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            RAC_LOG_INFO("LLM.LlamaCpp","End of generation token received");
            break;
        }

        const std::string new_token_chars =
            common_token_to_piece(context_, new_token_id);

        // Only scan newly appended bytes — scanner state persists from prior iterations
        const size_t scan_start = partial_utf8_buffer.size();
        partial_utf8_buffer.append(new_token_chars);

        size_t valid_upto = 0;
        for (size_t i = scan_start; i < partial_utf8_buffer.size(); ++i) {
            utf8_scanner.process(static_cast<uint8_t>(partial_utf8_buffer[i]));
            if (utf8_scanner.state == 0) {
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
                RAC_LOG_INFO("LLM.LlamaCpp","Stop sequence detected");
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
                // Walk safe_len back to a UTF-8 code-point boundary so we never
                // emit a partial multi-byte sequence (continuation bytes have 10xxxxxx pattern).
                while (safe_len > 0 && (stop_window[safe_len] & 0xC0) == 0x80) {
                    safe_len--;
                }
                if (safe_len > 0) {
                    if (!callback(stop_window.substr(0, safe_len))) {
                        RAC_LOG_INFO("LLM.LlamaCpp", "Generation cancelled by callback");
                        cancel_requested_.store(true);
                        break;
                    }
                    stop_window.erase(0, safe_len);
                }
            }
        }

        batch.n_tokens = 0;
        common_batch_add(batch, new_token_id, n_cur, {0}, true);

        n_cur++;
        tokens_generated++;

        if (llama_decode(context_, batch) != 0) {
            RAC_LOG_ERROR("LLM.LlamaCpp","llama_decode failed during generation");
            decode_failed_ = true;
            break;
        }
    }

    // Flush any remaining partial UTF-8 bytes (e.g. trailing multi-byte char at end of generation)
    if (!cancel_requested_.load() && !stop_sequence_hit && !partial_utf8_buffer.empty()) {
        stop_window.append(partial_utf8_buffer);
    }

    if (!cancel_requested_.load() && !stop_sequence_hit && !stop_window.empty()) {
        callback(stop_window);
    }

    if (llama_memory_t post_mem = llama_get_memory(context_)) {
        llama_memory_clear(post_mem, true);
    }

    llama_batch_free(batch);

    RAC_LOG_INFO("LLM.LlamaCpp","Generation complete: %d tokens", tokens_generated);
    return !cancel_requested_.load();
}

void LlamaCppTextGeneration::cancel() {
    cancel_requested_.store(true);
    RAC_LOG_INFO("LLM.LlamaCpp","Generation cancel requested");
}


bool LlamaCppTextGeneration::inject_system_prompt(const std::string& prompt) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!is_ready()) {
        RAC_LOG_ERROR("LLM.LlamaCpp","inject_system_prompt: model not ready");
        return false;
    }

    llama_memory_t mem = llama_get_memory(context_);
    if (mem) {
        llama_memory_clear(mem, true);
    }

    const auto tokens = common_tokenize(context_, prompt, true, true);
    const int n_tokens = static_cast<int>(tokens.size());

    if (n_tokens <= 0) {
        RAC_LOG_ERROR("LLM.LlamaCpp","inject_system_prompt: tokenization produced no tokens");
        return false;
    }

    const int n_ctx = llama_n_ctx(context_);
    if (n_tokens >= n_ctx) {
        RAC_LOG_ERROR("LLM.LlamaCpp","inject_system_prompt: prompt too long (%d tokens, ctx=%d)", n_tokens, n_ctx);
        return false;
    }

    const int n_batch_lim = batch_size_ > 0 ? batch_size_ : n_ctx;
    llama_batch batch = llama_batch_init(n_batch_lim, 0, 1);

    for (int chunk_start = 0; chunk_start < n_tokens; chunk_start += n_batch_lim) {
        batch.n_tokens = 0;
        int chunk_end = std::min(chunk_start + n_batch_lim, n_tokens);

        for (int i = chunk_start; i < chunk_end; ++i) {
            common_batch_add(batch, tokens[i], i, {0}, false);
        }

        if (llama_decode(context_, batch) != 0) {
            RAC_LOG_ERROR("LLM.LlamaCpp","inject_system_prompt: llama_decode failed at chunk [%d..%d)", chunk_start, chunk_end);
            llama_batch_free(batch);
            return false;
        }
    }

    llama_batch_free(batch);
    RAC_LOG_INFO("LLM.LlamaCpp","inject_system_prompt: injected %d tokens into KV cache", n_tokens);
    return true;
}

bool LlamaCppTextGeneration::append_context(const std::string& text) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!is_ready()) {
        RAC_LOG_ERROR("LLM.LlamaCpp","append_context: model not ready");
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
        RAC_LOG_ERROR("LLM.LlamaCpp","append_context: context full (pos=%d, tokens=%d, ctx=%d)", start_pos, n_tokens, n_ctx);
        return false;
    }

    const int n_batch_lim = batch_size_ > 0 ? batch_size_ : n_ctx;
    llama_batch batch = llama_batch_init(n_batch_lim, 0, 1);

    for (int chunk_start = 0; chunk_start < n_tokens; chunk_start += n_batch_lim) {
        batch.n_tokens = 0;
        int chunk_end = std::min(chunk_start + n_batch_lim, n_tokens);

        for (int i = chunk_start; i < chunk_end; ++i) {
            common_batch_add(batch, tokens[i], start_pos + i, {0}, false);
        }

        if (llama_decode(context_, batch) != 0) {
            RAC_LOG_ERROR("LLM.LlamaCpp","append_context: llama_decode failed at chunk [%d..%d)", chunk_start, chunk_end);
            llama_batch_free(batch);
            return false;
        }
    }

    llama_batch_free(batch);
    RAC_LOG_INFO("LLM.LlamaCpp","append_context: appended %d tokens at pos %d", n_tokens, start_pos);
    return true;
}

TextGenerationResult LlamaCppTextGeneration::generate_from_context(const TextGenerationRequest& request) {
    std::lock_guard<std::mutex> lock(mutex_);

    TextGenerationResult result;
    result.finish_reason = "error";

    if (!is_ready()) {
        RAC_LOG_ERROR("LLM.LlamaCpp","generate_from_context: model not ready");
        return result;
    }

    cancel_requested_.store(false);
    decode_failed_ = false;

    const std::string prompt = build_prompt(request);

    const auto tokens = common_tokenize(context_, prompt, false, false);
    const int n_prompt = static_cast<int>(tokens.size());

    if (n_prompt <= 0) {
        RAC_LOG_ERROR("LLM.LlamaCpp","generate_from_context: failed to tokenize prompt");
        return result;
    }

    llama_memory_t mem = llama_get_memory(context_);
    const llama_pos current_pos = mem ? (llama_memory_seq_pos_max(mem, 0) + 1) : 0;

    const int n_ctx = llama_n_ctx(context_);
    const int available_tokens = n_ctx - static_cast<int>(current_pos) - n_prompt - 4;

    if (available_tokens <= 0) {
        RAC_LOG_ERROR("LLM.LlamaCpp","generate_from_context: no space for generation (pos=%d, prompt=%d, ctx=%d)",
             static_cast<int>(current_pos), n_prompt, n_ctx);
        return result;
    }

    const int effective_max_tokens = std::min(request.max_tokens, available_tokens);
    RAC_LOG_INFO("LLM.LlamaCpp","generate_from_context: pos=%d, prompt_tokens=%d, max_tokens=%d",
         static_cast<int>(current_pos), n_prompt, effective_max_tokens);

    const int n_batch_lim = batch_size_ > 0 ? batch_size_ : n_ctx;
    llama_batch batch = llama_batch_init(n_batch_lim, 0, 1);

    for (int chunk_start = 0; chunk_start < n_prompt; chunk_start += n_batch_lim) {
        batch.n_tokens = 0;
        int chunk_end = std::min(chunk_start + n_batch_lim, n_prompt);
        bool is_last_chunk = (chunk_end == n_prompt);

        for (int i = chunk_start; i < chunk_end; ++i) {
            bool need_logits = is_last_chunk && (i == chunk_end - 1);
            common_batch_add(batch, tokens[i], current_pos + i, {0}, need_logits);
        }

        if (llama_decode(context_, batch) != 0) {
            RAC_LOG_ERROR("LLM.LlamaCpp","generate_from_context: llama_decode failed at chunk [%d..%d)", chunk_start, chunk_end);
            llama_batch_free(batch);
            return result;
        }
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

    Utf8State scanner_state;

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
        const size_t old_partial_size = partial_utf8_buffer.size();
        partial_utf8_buffer.append(new_token_chars);

        size_t valid_upto = 0;
        for (size_t i = old_partial_size; i < partial_utf8_buffer.size(); ++i) {
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
                size_t safe_len = stop_window.size() - MAX_STOP_LEN;
                while (safe_len > 0 && (stop_window[safe_len] & 0xC0) == 0x80) {
                    safe_len--;
                }
                if (safe_len > 0) {
                    generated_text += stop_window.substr(0, safe_len);
                    stop_window.erase(0, safe_len);
                }
            }
        }

        batch.n_tokens = 0;
        common_batch_add(batch, new_token_id, n_cur, {0}, true);
        n_cur++;
        tokens_generated++;

        if (llama_decode(context_, batch) != 0) {
            RAC_LOG_ERROR("LLM.LlamaCpp","generate_from_context: llama_decode failed during generation");
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

    RAC_LOG_INFO("LLM.LlamaCpp","generate_from_context: complete, tokens=%d, reason=%s",
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
        RAC_LOG_INFO("LLM.LlamaCpp","clear_context: KV cache cleared");
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
    RAC_LOG_INFO("LLM.LlamaCpp","Recreating context to accommodate LoRA adapters");

    // Free existing sampler and context
    if (sampler_) {
        llama_sampler_free(sampler_);
        sampler_ = nullptr;
    }

    if (context_) {
        llama_free(context_);
        context_ = nullptr;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size_;
    ctx_params.n_batch = batch_size_;
    ctx_params.n_ubatch = std::min(batch_size_, 512);
    ctx_params.n_threads = backend_->get_num_threads();
    ctx_params.n_threads_batch = backend_->get_num_threads();
    ctx_params.no_perf = true;

    context_ = llama_init_from_model(model_, ctx_params);
    if (!context_) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Failed to recreate context after LoRA adapter load");
        return false;
    }

    // Rebuild sampler chain (greedy placeholder — real sampler built on first generate_stream)
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler_ = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());

    // Invalidate cached params so the next generate_stream() rebuilds with real params
    cached_temperature_ = -1.0f;
    cached_top_p_ = -1.0f;
    cached_top_k_ = -1;
    cached_repetition_penalty_ = -1.0f;

    RAC_LOG_INFO("LLM.LlamaCpp","Context recreated successfully");
    return true;
}

bool LlamaCppTextGeneration::apply_lora_adapters() {
    if (lora_adapters_.empty()) {
        llama_set_adapters_lora(context_, nullptr, 0, nullptr);
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

    int32_t result = llama_set_adapters_lora(context_, adapters.data(), adapters.size(), scales.data());
    if (result != 0) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Failed to apply LoRA adapters (error=%d)", result);
        for (auto& entry : lora_adapters_) {
            entry.applied = false;
        }
        return false;
    }

    for (auto& entry : lora_adapters_) {
        entry.applied = true;
        RAC_LOG_INFO("LLM.LlamaCpp","Applied LoRA adapter: %s (scale=%.2f)", entry.path.c_str(), entry.scale);
    }
    return true;
}

bool LlamaCppTextGeneration::load_lora_adapter(const std::string& adapter_path, float scale) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_loaded_ || !model_) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Cannot load LoRA adapter: model not loaded");
        return false;
    }

    // Check if adapter already loaded
    for (const auto& entry : lora_adapters_) {
        if (entry.path == adapter_path) {
            RAC_LOG_ERROR("LLM.LlamaCpp","LoRA adapter already loaded: %s", adapter_path.c_str());
            return false;
        }
    }

    RAC_LOG_INFO("LLM.LlamaCpp","Loading LoRA adapter: %s (scale=%.2f)", adapter_path.c_str(), scale);

    // Load adapter against model
    llama_adapter_lora* adapter = llama_adapter_lora_init(model_, adapter_path.c_str());
    if (!adapter) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Failed to load LoRA adapter from: %s", adapter_path.c_str());
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

    RAC_LOG_INFO("LLM.LlamaCpp","LoRA adapter loaded and applied: %s (%zu total adapters)",
         adapter_path.c_str(), lora_adapters_.size());
    return true;
}

bool LlamaCppTextGeneration::remove_lora_adapter(const std::string& adapter_path) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_loaded_ || !context_) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Cannot remove LoRA adapter: model not loaded");
        return false;
    }

    auto it = std::find_if(lora_adapters_.begin(), lora_adapters_.end(),
                           [&adapter_path](const LoraAdapterEntry& e) { return e.path == adapter_path; });

    if (it == lora_adapters_.end()) {
        RAC_LOG_ERROR("LLM.LlamaCpp","LoRA adapter not found: %s", adapter_path.c_str());
        return false;
    }

    lora_adapters_.erase(it);

    // Re-apply remaining adapters (or clear if none left)
    if (!apply_lora_adapters()) {
        RAC_LOG_ERROR("LLM.LlamaCpp","Failed to re-apply remaining LoRA adapters after removal");
        return false;
    }

    // Clear KV cache after adapter changes
    llama_memory_clear(llama_get_memory(context_), true);

    RAC_LOG_INFO("LLM.LlamaCpp","LoRA adapter removed: %s (%zu remaining)", adapter_path.c_str(), lora_adapters_.size());
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
    RAC_LOG_INFO("LLM.LlamaCpp","All LoRA adapters cleared");
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
