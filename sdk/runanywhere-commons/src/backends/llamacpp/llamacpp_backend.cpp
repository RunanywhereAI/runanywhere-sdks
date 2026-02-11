#include "llamacpp_backend.h"

#include "common.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <string>
#include <cstdlib>

#include "rac/core/rac_logger.h"

#ifdef __ANDROID__
#include <android/log.h>
#include <dlfcn.h>
#define GPU_LOG(...) __android_log_print(ANDROID_LOG_WARN, "RAC_GPU_STATUS", __VA_ARGS__)
#else
#define GPU_LOG(...) fprintf(stderr, __VA_ARGS__)
#endif

#define LOGI(...) RAC_LOG_INFO("LLM.LlamaCpp", __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR("LLM.LlamaCpp", __VA_ARGS__)

namespace runanywhere {

static bool is_valid_utf8(const char* string) {
    if (!string) return true;
    const unsigned char* bytes = (const unsigned char*)string;
    int num;
    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) { num = 1; }
        else if ((*bytes & 0xE0) == 0xC0) { num = 2; }
        else if ((*bytes & 0xF0) == 0xE0) { num = 3; }
        else if ((*bytes & 0xF8) == 0xF0) { num = 4; }
        else { return false; }
        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) return false;
            bytes += 1;
        }
    }
    return true;
}

static void llama_log_callback(ggml_log_level level, const char* fmt, void* data) {
    (void)data;
    std::string msg(fmt ? fmt : "");
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) { msg.pop_back(); }
    if (msg.empty()) return;
    if (level == GGML_LOG_LEVEL_ERROR) { RAC_LOG_ERROR("LLM.LlamaCpp.GGML", "%s", msg.c_str()); }
    else if (level == GGML_LOG_LEVEL_WARN) { RAC_LOG_WARNING("LLM.LlamaCpp.GGML", "%s", msg.c_str()); }
    else if (level == GGML_LOG_LEVEL_INFO) { RAC_LOG_DEBUG("LLM.LlamaCpp.GGML", "%s", msg.c_str()); }
}

// Probe if Vulkan is actually usable on this device
static bool probe_vulkan_safe() {
#ifdef __ANDROID__
    // Try to dlopen libvulkan.so and call vkEnumerateInstanceVersion
    void* vk_lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
    if (!vk_lib) {
        GPU_LOG("Vulkan probe: libvulkan.so not found");
        return false;
    }

    // Try vkEnumeratePhysicalDevices to see if there's actually a GPU
    typedef int (*PFN_vkCreateInstance)(const void*, const void*, void*);
    typedef void (*PFN_vkDestroyInstance)(void*, const void*);
    typedef int (*PFN_vkEnumeratePhysicalDevices)(void*, uint32_t*, void*);

    auto fn_create = (PFN_vkCreateInstance)dlsym(vk_lib, "vkCreateInstance");
    auto fn_destroy = (PFN_vkDestroyInstance)dlsym(vk_lib, "vkDestroyInstance");
    auto fn_enum = (PFN_vkEnumeratePhysicalDevices)dlsym(vk_lib, "vkEnumeratePhysicalDevices");

    if (!fn_create || !fn_destroy || !fn_enum) {
        GPU_LOG("Vulkan probe: missing symbols");
        dlclose(vk_lib);
        return false;
    }

    // Minimal VkApplicationInfo + VkInstanceCreateInfo (packed structs)
    struct { uint32_t sType; const void* pNext; const char* name; uint32_t ver; const char* ename; uint32_t ever; uint32_t api; } app_info = {0, nullptr, "probe", 1, "probe", 1, (1u << 22) | (0 << 12)};
    struct { uint32_t sType; const void* pNext; uint32_t flags; const void* pApp; uint32_t elc; const char* const* el; uint32_t exc; const char* const* ex; } create_info = {1, nullptr, 0, &app_info, 0, nullptr, 0, nullptr};

    void* instance = nullptr;
    int result = fn_create(&create_info, nullptr, &instance);
    if (result != 0 || !instance) {
        GPU_LOG("Vulkan probe: vkCreateInstance failed (%d)", result);
        dlclose(vk_lib);
        return false;
    }

    uint32_t gpu_count = 0;
    fn_enum(instance, &gpu_count, nullptr);
    fn_destroy(instance, nullptr);
    dlclose(vk_lib);

    if (gpu_count == 0) {
        GPU_LOG("Vulkan probe: no physical devices found");
        return false;
    }

    GPU_LOG("Vulkan probe: found %u GPU(s) - Vulkan OK", gpu_count);
    return true;
#else
    return true;  // On desktop, assume Vulkan works
#endif
}

LlamaCppBackend::LlamaCppBackend() { LOGI("LlamaCppBackend created"); }

LlamaCppBackend::~LlamaCppBackend() { cleanup(); LOGI("LlamaCppBackend destroyed"); }

bool LlamaCppBackend::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (initialized_) { LOGI("LlamaCppBackend already initialized"); return true; }
    config_ = config;

    // Set log callback first
    llama_log_set(llama_log_callback, nullptr);

    // If GPU was already disabled (e.g., by fallback retry), skip Vulkan probe
#ifdef GGML_USE_VULKAN
    if (!use_gpu_) {
        GPU_LOG("GPU pre-disabled - skipping Vulkan, CPU only mode");
    } else {
        bool vulkan_ok = probe_vulkan_safe();
        if (!vulkan_ok) {
            GPU_LOG("Vulkan probe FAILED - will use CPU");
            use_gpu_ = false;
        } else {
            GPU_LOG("Vulkan probe OK");
        }
    }
#endif

    // This may throw a Vulkan exception - let it propagate to caller
    llama_backend_init();
    GPU_LOG("llama_backend_init() completed successfully");

    if (config.contains("num_threads")) { num_threads_ = config["num_threads"].get<int>(); }
    if (num_threads_ <= 0) {
#ifdef _SC_NPROCESSORS_ONLN
        num_threads_ = std::max(1, std::min(8, (int)sysconf(_SC_NPROCESSORS_ONLN) - 2));
#else
        num_threads_ = 4;
#endif
    }
    LOGI("LlamaCppBackend initialized with %d threads", num_threads_);
    GPU_LOG("LlamaCppBackend initialized with %d threads", num_threads_);
    detect_gpu_capabilities();
    create_text_generation();
    initialized_ = true;
    return true;
}

void LlamaCppBackend::detect_gpu_capabilities() {
    GPU_LOG("Detecting GPU capabilities...");
#ifdef GGML_USE_VULKAN
    if (!use_gpu_) {
        // Already disabled by probe
        GPU_LOG("VULKAN COMPILED IN but disabled (probe failed) - CPU only");
        LOGI("Vulkan disabled by probe - using CPU backend");
        return;
    }
    use_gpu_ = true;
    gpu_device_name_ = "Vulkan GPU";
    GPU_LOG("VULKAN COMPILED IN - GPU ENABLED (n_gpu_layers=999 at model load)");
    LOGI("Vulkan compiled in - GPU acceleration enabled");
#else
    use_gpu_ = false;
    GPU_LOG("VULKAN NOT COMPILED IN - CPU only");
    LOGI("Vulkan not compiled in, using CPU backend");
#endif
}

bool LlamaCppBackend::is_initialized() const { return initialized_; }

void LlamaCppBackend::cleanup() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_) return;
    text_gen_.reset();
    llama_backend_free();
    initialized_ = false;
    LOGI("LlamaCppBackend cleaned up");
}

DeviceType LlamaCppBackend::get_device_type() const {
    if (use_gpu_) return DeviceType::GPU;
#if defined(GGML_USE_METAL)
    return DeviceType::METAL;
#elif defined(GGML_USE_CUDA)
    return DeviceType::CUDA;
#else
    return DeviceType::CPU;
#endif
}

size_t LlamaCppBackend::get_memory_usage() const { return 0; }

void LlamaCppBackend::create_text_generation() {
    text_gen_ = std::make_unique<LlamaCppTextGeneration>(this);
    LOGI("Created text generation component");
}

LlamaCppTextGeneration::LlamaCppTextGeneration(LlamaCppBackend* backend) : backend_(backend) { LOGI("LlamaCppTextGeneration created"); }

LlamaCppTextGeneration::~LlamaCppTextGeneration() { unload_model(); LOGI("LlamaCppTextGeneration destroyed"); }

bool LlamaCppTextGeneration::is_ready() const { return model_loaded_ && model_ != nullptr && context_ != nullptr; }

bool LlamaCppTextGeneration::load_model(const std::string& model_path, const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (model_loaded_) { LOGI("Unloading previous model"); unload_model_internal(); }
    LOGI("Loading model from: %s", model_path.c_str());
    GPU_LOG("Loading model from: %s", model_path.c_str());

    int user_context_size = 0;
    if (config.contains("context_size")) { user_context_size = config["context_size"].get<int>(); }
    if (config.contains("max_context_size")) { max_default_context_ = config["max_context_size"].get<int>(); }
    if (config.contains("temperature")) { temperature_ = config["temperature"].get<float>(); }
    if (config.contains("min_p")) { min_p_ = config["min_p"].get<float>(); }
    if (config.contains("top_p")) { top_p_ = config["top_p"].get<float>(); }
    if (config.contains("top_k")) { top_k_ = config["top_k"].get<int>(); }
    model_config_ = config;
    model_path_ = model_path;

    llama_model_params model_params = llama_model_default_params();
    bool gpu_attempted = false;
    
    // CRITICAL FIX: Force CPU mode on Android to avoid Vulkan crash
    // Mali-G76 MC4 and other mobile GPUs have buggy Vulkan drivers
#ifdef __ANDROID__
    GPU_LOG("Android detected - forcing CPU mode (n_gpu_layers=0) to avoid Vulkan crash");
    model_params.n_gpu_layers = 0;
    LOGI("Loading model with CPU backend (Android Vulkan workaround)");
#else
    if (backend_->is_using_gpu()) {
        gpu_attempted = true;
        model_params.n_gpu_layers = 999;
        GPU_LOG("LOADING MODEL WITH GPU: n_gpu_layers=999, device=%s", backend_->get_gpu_device_name().c_str());
        LOGI("Attempting GPU acceleration, device=%s, layers=ALL(999)", backend_->get_gpu_device_name().c_str());
    } else {
        model_params.n_gpu_layers = 0;
        GPU_LOG("LOADING MODEL WITH CPU ONLY: n_gpu_layers=0");
        LOGI("Loading model with CPU backend");
    }
#endif

    GPU_LOG("About to call llama_model_load_from_file with n_gpu_layers=%d", model_params.n_gpu_layers);
    
    try {
        model_ = llama_model_load_from_file(model_path.c_str(), model_params);
    } catch (const std::exception& e) {
        GPU_LOG("EXCEPTION during model load: %s", e.what());
        LOGE("Model load exception: %s", e.what());
        model_ = nullptr;
    } catch (...) {
        GPU_LOG("UNKNOWN EXCEPTION during model load");
        LOGE("Unknown exception during model load");
        model_ = nullptr;
    }
    
    GPU_LOG("llama_model_load_from_file returned, model=%p", (void*)model_);
    
    if (!model_ && gpu_attempted) {
        GPU_LOG("GPU LOAD FAILED - falling back to CPU");
        LOGE("GPU model loading failed, falling back to CPU");
        model_params.n_gpu_layers = 0;
        backend_->disable_gpu();
        model_ = llama_model_load_from_file(model_path.c_str(), model_params);
    }
    if (!model_) { GPU_LOG("MODEL LOAD FAILED"); LOGE("Failed to load model from: %s", model_path.c_str()); return false; }

    int model_train_ctx = llama_model_n_ctx_train(model_);
    LOGI("Model training context size: %d", model_train_ctx);
    if (user_context_size > 0) {
        context_size_ = std::min(user_context_size, model_train_ctx);
    } else {
        context_size_ = std::min(model_train_ctx, max_default_context_);
    }
    LOGI("Context size: %d", context_size_);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size_;
    ctx_params.n_batch = std::min(context_size_, 512);
    ctx_params.n_threads = backend_->get_num_threads();
    ctx_params.n_threads_batch = backend_->get_num_threads();
    ctx_params.no_perf = true;
    context_ = llama_init_from_model(model_, ctx_params);
    if (!context_) { LOGE("Failed to create context"); llama_model_free(model_); model_ = nullptr; return false; }

    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler_ = llama_sampler_chain_init(sparams);
    if (temperature_ > 0.0f) {
        llama_sampler_chain_add(sampler_, llama_sampler_init_penalties(64, 1.2f, 0.0f, 0.0f));
        if (top_k_ > 0) { llama_sampler_chain_add(sampler_, llama_sampler_init_top_k(top_k_)); }
        llama_sampler_chain_add(sampler_, llama_sampler_init_top_p(top_p_, 1));
        llama_sampler_chain_add(sampler_, llama_sampler_init_temp(temperature_));
        llama_sampler_chain_add(sampler_, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    } else {
        llama_sampler_chain_add(sampler_, llama_sampler_init_greedy());
    }

    model_loaded_ = true;
    GPU_LOG("MODEL LOADED: context=%d, gpu=%s, temp=%.2f", context_size_, gpu_attempted ? "YES(999)" : "NO(CPU)", temperature_);
    LOGI("Model loaded: context=%d, temp=%.2f", context_size_, temperature_);
    return true;
}

bool LlamaCppTextGeneration::is_model_loaded() const { return model_loaded_; }

bool LlamaCppTextGeneration::unload_model_internal() {
    if (!model_loaded_) return true;
    LOGI("Unloading model");
    if (sampler_) { llama_sampler_free(sampler_); sampler_ = nullptr; }
    if (context_) { llama_free(context_); context_ = nullptr; }
    if (model_) { llama_model_free(model_); model_ = nullptr; }
    model_loaded_ = false;
    model_path_.clear();
    LOGI("Model unloaded");
    return true;
}

bool LlamaCppTextGeneration::unload_model() { std::lock_guard<std::mutex> lock(mutex_); return unload_model_internal(); }

std::string LlamaCppTextGeneration::build_prompt(const TextGenerationRequest& request) {
    std::vector<std::pair<std::string, std::string>> messages;
    if (!request.messages.empty()) { messages = request.messages; }
    else if (!request.prompt.empty()) { messages.push_back({"user", request.prompt}); }
    else { LOGE("No prompt or messages provided"); return ""; }
    std::string formatted = apply_chat_template(messages, request.system_prompt, true);
    LOGI("Applied chat template, length: %zu", formatted.length());
    return formatted;
}

std::string LlamaCppTextGeneration::apply_chat_template(
    const std::vector<std::pair<std::string, std::string>>& messages,
    const std::string& system_prompt, bool add_assistant_token) {
    std::vector<llama_chat_message> chat_messages;
    std::vector<std::string> role_storage;
    role_storage.reserve(messages.size());
    if (!system_prompt.empty()) { chat_messages.push_back({"system", system_prompt.c_str()}); }
    for (const auto& [role, content] : messages) {
        std::string role_lower = role;
        std::transform(role_lower.begin(), role_lower.end(), role_lower.begin(), ::tolower);
        role_storage.push_back(std::move(role_lower));
        chat_messages.push_back({role_storage.back().c_str(), content.c_str()});
    }
    std::string model_template;
    model_template.resize(2048);
    int32_t template_len = llama_model_meta_val_str(model_, "tokenizer.chat_template", model_template.data(), model_template.size());
    const char* tmpl_to_use = nullptr;
    if (template_len > 0) { model_template.resize(template_len); tmpl_to_use = model_template.c_str(); }
    std::string formatted;
    formatted.resize(1024 * 256);
    int32_t result = llama_chat_apply_template(tmpl_to_use, chat_messages.data(), chat_messages.size(), add_assistant_token, formatted.data(), formatted.size());
    if (result < 0) {
        LOGE("llama_chat_apply_template failed: %d", result);
        std::string fallback;
        for (const auto& msg : chat_messages) { fallback += std::string(msg.role) + ": " + msg.content + "\n"; }
        if (add_assistant_token) { fallback += "assistant: "; }
        return fallback;
    }
    if (result > (int32_t)formatted.size()) {
        formatted.resize(result + 1024);
        result = llama_chat_apply_template(tmpl_to_use, chat_messages.data(), chat_messages.size(), add_assistant_token, formatted.data(), formatted.size());
    }
    if (result > 0) { formatted.resize(result); }
    return formatted;
}

TextGenerationResult LlamaCppTextGeneration::generate(const TextGenerationRequest& request) {
    TextGenerationResult result;
    result.finish_reason = "error";
    std::string generated_text;
    int tokens_generated = 0;
    int prompt_tokens = 0;
    auto start_time = std::chrono::high_resolution_clock::now();
    bool success = generate_stream(request, [&](const std::string& token) -> bool {
        generated_text += token;
        tokens_generated++;
        return !cancel_requested_.load();
    }, &prompt_tokens);
    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    result.text = generated_text;
    result.tokens_generated = tokens_generated;
    result.prompt_tokens = prompt_tokens;
    result.inference_time_ms = duration.count();
    if (cancel_requested_.load()) { result.finish_reason = "cancelled"; }
    else if (success) { result.finish_reason = tokens_generated >= request.max_tokens ? "length" : "stop"; }
    return result;
}

bool LlamaCppTextGeneration::generate_stream(const TextGenerationRequest& request, TextStreamCallback callback, int* out_prompt_tokens) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!is_ready()) { LOGE("Model not ready for generation"); return false; }
    cancel_requested_.store(false);
    std::string prompt = build_prompt(request);
    LOGI("Generating with prompt length: %zu", prompt.length());
    const auto tokens_list = common_tokenize(context_, prompt, true, true);
    int n_ctx = llama_n_ctx(context_);
    int prompt_tokens = static_cast<int>(tokens_list.size());
    if (out_prompt_tokens) { *out_prompt_tokens = prompt_tokens; }
    int available_tokens = n_ctx - prompt_tokens - 4;
    if (available_tokens <= 0) { LOGE("Prompt too long: %d tokens, context: %d", prompt_tokens, n_ctx); return false; }
    int effective_max_tokens = std::min(request.max_tokens, available_tokens);
    LOGI("Generation: prompt=%d, max=%d, context=%d", prompt_tokens, effective_max_tokens, n_ctx);

    llama_batch batch = llama_batch_init(n_ctx, 0, 1);
    batch.n_tokens = 0;
    for (size_t i = 0; i < tokens_list.size(); i++) { common_batch_add(batch, tokens_list[i], i, {0}, false); }
    batch.logits[batch.n_tokens - 1] = true;
    if (llama_decode(context_, batch) != 0) { LOGE("llama_decode failed for prompt"); llama_batch_free(batch); return false; }
    llama_sampler_reset(sampler_);

    const auto vocab = llama_model_get_vocab(model_);
    std::string cached_token_chars;
    std::string accumulated_text;
    int n_cur = batch.n_tokens;
    int tokens_generated = 0;

    while (tokens_generated < effective_max_tokens && !cancel_requested_.load()) {
        const llama_token new_token_id = llama_sampler_sample(sampler_, context_, -1);
        llama_sampler_accept(sampler_, new_token_id);
        if (llama_vocab_is_eog(vocab, new_token_id)) { LOGI("End of generation token"); break; }
        auto new_token_chars = common_token_to_piece(context_, new_token_id);
        cached_token_chars += new_token_chars;
        accumulated_text += new_token_chars;

        static const std::vector<std::string> stop_sequences = {"<|im_end|>", "<|end|>", "<|eot_id|>", "</s>"};
        
        bool should_stop = false;
        for (const auto& stop_seq : stop_sequences) {
            if (accumulated_text.find(stop_seq) != std::string::npos) {
                LOGI("Stop sequence detected: %s", stop_seq.c_str());
                should_stop = true;
                break;
            }
        }
        if (should_stop) break;

        if (is_valid_utf8(cached_token_chars.c_str())) {
            if (!callback(cached_token_chars)) { LOGI("Generation cancelled by callback"); break; }
            cached_token_chars.clear();
        }

        common_batch_clear(batch);
        common_batch_add(batch, new_token_id, n_cur, {0}, true);
        n_cur++;
        if (llama_decode(context_, batch) != 0) { LOGE("llama_decode failed during generation"); llama_batch_free(batch); return false; }
        tokens_generated++;
    }

    if (!cached_token_chars.empty() && is_valid_utf8(cached_token_chars.c_str())) { callback(cached_token_chars); }
    llama_batch_free(batch);
    LOGI("Generation complete: %d tokens", tokens_generated);
    return true;
}

void LlamaCppTextGeneration::cancel() { cancel_requested_.store(true); LOGI("Generation cancellation requested"); }

nlohmann::json LlamaCppTextGeneration::get_model_info() const {
    if (!model_loaded_ || !model_) return nlohmann::json::object();
    nlohmann::json info;
    info["model_path"] = model_path_;
    info["context_size"] = context_size_;
    info["temperature"] = temperature_;
    info["top_p"] = top_p_;
    info["top_k"] = top_k_;
    info["min_p"] = min_p_;
    return info;
}

}  // namespace runanywhere
