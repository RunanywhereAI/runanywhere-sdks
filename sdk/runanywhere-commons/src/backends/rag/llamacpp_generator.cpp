/**
 * @file llamacpp_generator.cpp
 * @brief LlamaCPP Text Generator Implementation for RAG
 * 
 * Provides a self-contained LlamaCpp text generator for RAG pipeline.
 * Follows separation of concern: RAG can load and use GGUF models independently.
 * Integrates directly with llama.cpp library for inference.
 * Similar to how ONNX embedding provider works independently from ONNX backend.
 */

#include "llamacpp_generator.h"
#include <rac/core/rac_logger.h>
#include <llama.h>
#include <chrono>
#include <memory>
#include <fstream>
#include <mutex>
#include <atomic>
#include <nlohmann/json.hpp>

#define LOG_TAG "RAG.LlamaCppGenerator"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#define LOGW(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

// =============================================================================
// LLAMA LOG CALLBACK
// =============================================================================

static void llama_log_callback(ggml_log_level level, const char* fmt, void* data) {
    (void)data;

    std::string msg(fmt ? fmt : "");
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
        msg.pop_back();
    }
    if (msg.empty()) {
        return;
    }

    if (level == GGML_LOG_LEVEL_ERROR) {
        RAC_LOG_ERROR("RAG.LlamaCpp.GGML", "%s", msg.c_str());
    } else if (level == GGML_LOG_LEVEL_WARN) {
        RAC_LOG_WARNING("RAG.LlamaCpp.GGML", "%s", msg.c_str());
    } else {
        RAC_LOG_DEBUG("RAG.LlamaCpp.GGML", "%s", msg.c_str());
    }
}

// =============================================================================
// PIMPL IMPLEMENTATION
// =============================================================================

class LlamaCppGenerator::Impl {
public:
    llama_model* model = nullptr;
    llama_context* context = nullptr;
    
    std::string model_path;
    int context_size = 2048;
    int batch_size = 64;
    float temperature = 0.7f;
    float top_p = 0.95f;
    int top_k = 40;
    bool ready = false;
    std::mutex mutex;
    std::atomic<bool> cancel_requested{false};
    
    ~Impl() {
        cleanup();
    }
    
    void cleanup() {
        if (context) {
            llama_free(context);
            context = nullptr;
        }
        if (model) {
            llama_model_free(model);
            model = nullptr;
        }
    }
    
    // Create a fresh sampler for each generation call
    llama_sampler* create_sampler() const {
        auto sampler_params = llama_sampler_chain_default_params();
        sampler_params.no_perf = true;
        llama_sampler* sampler = llama_sampler_chain_init(sampler_params);
        
        if (!sampler) {
            return nullptr;
        }
        
        // Build sampler chain in the correct order
        // Temperature first (affects logit scaling)
        if (temperature > 0.0f) {
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        }
        
        // Then apply top-k and top-p filters
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
        
        // Finally, select a random token (minstd PRNG)
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(1234));
        
        return sampler;
    }
    
    bool initialize(const std::string& path, const std::string& config_json) {
        std::lock_guard<std::mutex> lock(mutex);

        // Ensure llama backend is initialized and logging is enabled
        static std::once_flag llama_init_once;
        std::call_once(llama_init_once, []() {
            llama_backend_init();
            llama_log_set(llama_log_callback, nullptr);
        });
        
        model_path = path;
        
        // Verify model file exists
        std::ifstream file(path);
        if (!file.good()) {
            LOGE("Model file not found: %s", path.c_str());
            return false;
        }
        file.close();
        
        // Parse config if provided
        if (!config_json.empty()) {
            try {
                auto config = nlohmann::json::parse(config_json);
                if (config.contains("context_size")) {
                    context_size = config["context_size"].get<int>();
                }
                if (config.contains("temperature")) {
                    temperature = config["temperature"].get<float>();
                }
                if (config.contains("top_p")) {
                    top_p = config["top_p"].get<float>();
                }
                if (config.contains("top_k")) {
                    top_k = config["top_k"].get<int>();
                }
            } catch (const std::exception& e) {
                LOGW("Failed to parse config JSON: %s", e.what());
            }
        }
        
        // Load model using llama.cpp
        llama_model_params model_params = llama_model_default_params();
        model = llama_model_load_from_file(path.c_str(), model_params);
        
        if (!model) {
            LOGE("Failed to load LlamaCpp model: %s", path.c_str());
            return false;
        }
        
        // Get model info
        int model_train_ctx = llama_model_n_ctx_train(model);
        LOGI("Model training context size: %d", model_train_ctx);
        
        // Cap context size to model training context
        context_size = std::min(context_size, model_train_ctx);
        
        // Create context with safe defaults for ARM64/embedded platforms
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = context_size;
        ctx_params.n_batch = 64;                               // Very conservative batch size
        ctx_params.n_ubatch = 64;                              // Very conservative micro-batch size
        ctx_params.n_seq_max = 1;                              // Single sequence only
        ctx_params.n_threads = 1;                              // Single-threaded for safety
        ctx_params.n_threads_batch = 1;
        ctx_params.type_k = GGML_TYPE_F16;                     // Force F16 for KV cache (no quantization)
        ctx_params.type_v = GGML_TYPE_F16;                     // Force F16 for KV cache (no quantization)
        ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
        ctx_params.offload_kqv = false;
        ctx_params.op_offload = false;
        ctx_params.kv_unified = false;
        ctx_params.no_perf = true;
        
        context = llama_init_from_model(model, ctx_params);
        
        if (!context) {
            LOGE("Failed to create llama.cpp context");
            llama_model_free(model);
            model = nullptr;
            return false;
        }
        
        LOGI("LlamaCPP generator initialized successfully for: %s", path.c_str());
        LOGI("Context size: %d, Temperature: %.2f, Top-P: %.2f, Top-K: %d", 
             context_size, temperature, top_p, top_k);
           batch_size = ctx_params.n_batch;
        ready = true;
        return true;
    }
    
    GenerationResult generate(const std::string& prompt, const GenerationOptions& options) {
        GenerationResult result;
        result.success = false;
        
        std::lock_guard<std::mutex> lock(mutex);

        const auto start_time = std::chrono::steady_clock::now();
        auto finalize = [&](GenerationResult& res) -> GenerationResult {
            const auto end_time = std::chrono::steady_clock::now();
            res.inference_time_ms = std::chrono::duration<double, std::milli>(
                end_time - start_time
            ).count();
            return res;
        };
        
        if (!model || !context) {
            result.text = "Error: LlamaCpp model not initialized";
            return finalize(result);
        }
        
        cancel_requested.store(false);

        // Clear KV cache so each query starts from position 0
        llama_memory_clear(llama_get_memory(context), true);
        
        // Create a fresh sampler for this generation call
        llama_sampler* sampler = create_sampler();
        if (!sampler) {
            result.text = "Error: Failed to create sampler";
            return finalize(result);
        }
        
        const llama_vocab* vocab = llama_model_get_vocab(model);

        // Tokenize prompt
        int32_t n_prompt_tokens = llama_tokenize(
            vocab,
            prompt.c_str(),
            static_cast<int32_t>(prompt.length()),
            nullptr,
            0,
            true,  // add_special
            true   // parse_special
        );
        if (n_prompt_tokens < 0) {
            n_prompt_tokens = -n_prompt_tokens;
        }
        if (n_prompt_tokens <= 0) {
            LOGE("Failed to tokenize prompt");
            result.text = "Error: Failed to tokenize prompt";
            llama_sampler_free(sampler);
            return finalize(result);
        }

        std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt_tokens));
        int32_t n_prompt_tokens_actual = llama_tokenize(
            vocab,
            prompt.c_str(),
            static_cast<int32_t>(prompt.length()),
            prompt_tokens.data(),
            n_prompt_tokens,
            true,
            true
        );
        if (n_prompt_tokens_actual < 0) {
            LOGE("Failed to tokenize prompt (second pass)");
            result.text = "Error: Failed to tokenize prompt";
            llama_sampler_free(sampler);
            return finalize(result);
        }
        prompt_tokens.resize(static_cast<size_t>(n_prompt_tokens_actual));
        
        int n_ctx = llama_n_ctx(context);
        int n_prompt = static_cast<int>(prompt_tokens.size());
        int available_tokens = n_ctx - n_prompt - 4;
        
        if (available_tokens <= 0) {
            LOGE("Prompt too long: %d tokens, context: %d", n_prompt, n_ctx);
            result.text = "Error: Prompt exceeds maximum context length";
            llama_sampler_free(sampler);
            return finalize(result);
        }
        
        int max_tokens = options.max_tokens > 0 ? options.max_tokens : 512;
        int n_max_tokens = std::min(max_tokens, available_tokens);
        
        LOGI("Generation: prompt_tokens=%d, max_tokens=%d, context=%d", 
             n_prompt, n_max_tokens, n_ctx);
        
        // Allocate ONE batch for entire generation (like working llamacpp backend)
        llama_batch batch = llama_batch_init(n_ctx, 0, 1);
        
        if (batch.token == nullptr) {
            LOGE("Failed to allocate batch");
            result.text = "Error: Memory allocation failed";
            llama_sampler_free(sampler);
            return finalize(result);
        }
        
        // Decode prompt in chunks that respect n_batch to avoid out-of-bounds writes
        int prompt_offset = 0;
        while (prompt_offset < n_prompt) {
            const int chunk = std::min(batch_size, n_prompt - prompt_offset);
            batch.n_tokens = 0;

            for (int i = 0; i < chunk; i++) {
                const int token_index = prompt_offset + i;
                batch.token[i] = prompt_tokens[token_index];
                batch.pos[i] = token_index;
                batch.n_seq_id[i] = 1;
                batch.seq_id[i][0] = 0;  // Sequence ID 0
                batch.logits[i] = false;
                batch.n_tokens++;
            }

            if (prompt_offset + chunk == n_prompt) {
                batch.logits[batch.n_tokens - 1] = true;  // Only compute logits for last token
            }

            if (llama_decode(context, batch) != 0) {
                LOGE("llama_decode failed for prompt at offset %d", prompt_offset);
                llama_batch_free(batch);
                llama_sampler_free(sampler);
                result.text = "Error: Failed to decode prompt";
                return finalize(result);
            }

            prompt_offset += chunk;
        }
        
        llama_sampler_reset(sampler);  // Reset sampler after prompt
        
        std::string generated_text;
        generated_text.reserve(n_max_tokens * 4);  // Reserve space for efficiency
        int n_tokens_generated = 0;
        int n_cur = n_prompt;  // Current position (continue after full prompt)
        
        // Generation loop - reuse same batch
        while (n_tokens_generated < n_max_tokens && !cancel_requested.load()) {
            // Sample next token using sampler
            const llama_token new_token = llama_sampler_sample(sampler, context, -1);
            llama_sampler_accept(sampler, new_token);
            
            // Check for end-of-sequence token
            if (llama_vocab_is_eog(vocab, new_token)) {
                LOGI("End of generation token encountered");
                break;
            }
            
            // Decode token to text
            char buf[128];
            int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
            if (n > 0) {
                generated_text.append(buf, n);
            }
            
            // Prepare batch for next token (REUSE same batch like working backend)
            batch.n_tokens = 0;
            batch.token[0] = new_token;
            batch.pos[0] = n_cur;
            batch.n_seq_id[0] = 1;
            batch.seq_id[0][0] = 0;  // Sequence ID 0
            batch.logits[0] = true;
            batch.n_tokens = 1;
            
            n_cur++;
            
            // Decode next position
            if (llama_decode(context, batch) != 0) {
                LOGE("llama_decode failed during generation at token %d", n_tokens_generated);
                break;
            }

            n_tokens_generated++;
            if (n_tokens_generated % 10 == 0) {
                LOGI("Generated %d tokens so far...", n_tokens_generated);
            }
        }
        
        llama_batch_free(batch);
        llama_sampler_free(sampler);  // Clean up sampler created for this call
        
        result.success = true;
        result.text = generated_text;
        result.tokens_generated = n_tokens_generated;
        result.prompt_tokens = n_prompt;
        result.finished = !cancel_requested.load();
        result.stop_reason = cancel_requested.load() ? "cancelled" : 
                           n_tokens_generated >= n_max_tokens ? "length" : "stop";
        
        LOGI("Generation complete: %d/%d tokens, reason: %s", 
             n_tokens_generated, n_max_tokens, result.stop_reason.c_str());

           return finalize(result);
    }
};

// =============================================================================
// PUBLIC API
// =============================================================================

LlamaCppGenerator::LlamaCppGenerator(const std::string& model_path, const std::string& config_json)
    : impl_(std::make_unique<Impl>()) {
    impl_->initialize(model_path, config_json);
}

LlamaCppGenerator::~LlamaCppGenerator() = default;

// Move semantics
LlamaCppGenerator::LlamaCppGenerator(LlamaCppGenerator&&) noexcept = default;
LlamaCppGenerator& LlamaCppGenerator::operator=(LlamaCppGenerator&&) noexcept = default;

GenerationResult LlamaCppGenerator::generate(
    const std::string& prompt,
    const GenerationOptions& options
) {
    return impl_->generate(prompt, options);
}

bool LlamaCppGenerator::is_ready() const noexcept {
    return impl_ && impl_->ready;
}

const char* LlamaCppGenerator::name() const noexcept {
    return "LlamaCPP";
}

int LlamaCppGenerator::context_size() const noexcept {
    return 4096;  // Default; could be configurable
}

// =============================================================================
// FACTORY FUNCTION
// =============================================================================

std::unique_ptr<ITextGenerator> create_llamacpp_generator(
    const std::string& model_path,
    const std::string& config_json
) {
    return std::make_unique<LlamaCppGenerator>(model_path, config_json);
}

} // namespace rag
} // namespace runanywhere
