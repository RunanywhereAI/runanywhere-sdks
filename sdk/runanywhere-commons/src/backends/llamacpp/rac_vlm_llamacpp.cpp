/**
 * @file rac_vlm_llamacpp.cpp
 * @brief RunAnywhere Commons - LlamaCPP VLM Backend Implementation
 *
 * Vision Language Model backend using llama.cpp's multimodal (mtmd) API.
 * Supports VLM architectures including Qwen2-VL, SmolVLM, LLaVA, MiniCPM-V, etc.
 *
 * Updated for llama.cpp b7650+ mtmd API.
 */

#include "rac/backends/rac_vlm_llamacpp.h"

#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <llama.h>

// llama.cpp multimodal support (mtmd)
#ifdef RAC_VLM_USE_MTMD
#include "clip.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#endif

#include "rac/core/rac_logger.h"
#include "rac/utils/rac_image_utils.h"

static const char* LOG_CAT = "VLM.LlamaCPP";

// =============================================================================
// NAMED CONSTANTS
// =============================================================================

static constexpr int kDefaultMaxContextSize = 4096;
static constexpr int kDefaultBatchSize = 512;
static constexpr int kDefaultMaxTokens = 2048;

// =============================================================================
// INTERNAL BACKEND STATE
// =============================================================================

namespace {

/**
 * Internal VLM backend state.
 */
// Forward declaration
enum class VLMModelType;

struct LlamaCppVLMBackend {
    // llama.cpp model and context
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    llama_sampler* sampler = nullptr;

#ifdef RAC_VLM_USE_MTMD
    // Multimodal context (vision projector)
    mtmd_context* mtmd_ctx = nullptr;
#endif

    // Configuration
    rac_vlm_llamacpp_config_t config = RAC_VLM_LLAMACPP_CONFIG_DEFAULT;

    // State
    bool model_loaded = false;
    std::atomic<bool> cancel_requested{false};

    // Model info
    std::string model_path;
    std::string mmproj_path;
    int context_size = 0;
    llama_pos n_past = 0;

    // Detected model type for chat template
    VLMModelType model_type = static_cast<VLMModelType>(0); // Unknown

    // Cached sampler parameters to avoid unnecessary rebuilds
    float cached_temperature = -1.0f;
    float cached_top_p = -1.0f;

    // Thread safety
    mutable std::mutex mutex;
};

/**
 * Get number of CPU threads to use.
 */
int get_num_threads(const int config_threads) {
    if (config_threads > 0)
        return config_threads;

    // Auto-detect based on hardware
    int threads = static_cast<int>(std::thread::hardware_concurrency());
    if (threads <= 0)
        threads = 4;
    if (threads > 8)
        threads = 8;  // Cap for mobile devices
    return threads;
}

// =============================================================================
// CHAT TEMPLATE HELPERS
// =============================================================================

/**
 * VLM model type for chat template selection.
 */
enum class VLMModelType {
    Unknown,
    SmolVLM,    // SmolVLM uses "User:" / "Assistant:" format
    Qwen2VL,    // Qwen2-VL uses chatml with <|im_start|>user format
    LLaVA,      // LLaVA uses "USER:" / "ASSISTANT:" format
    Generic     // Generic chatml fallback
};

/**
 * Detect VLM model type from model name metadata.
 */
VLMModelType detect_vlm_model_type(llama_model* model) {
    if (!model) return VLMModelType::Generic;

    // Try to get model name from metadata
    char name_buf[256] = {0};
    int32_t len = llama_model_meta_val_str(model, "general.name", name_buf, sizeof(name_buf));
    if (len <= 0) {
        len = llama_model_meta_val_str(model, "general.basename", name_buf, sizeof(name_buf));
    }

    if (len > 0) {
        std::string name(name_buf);
        // Convert to lowercase for comparison
        for (auto& c : name) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

        RAC_LOG_DEBUG(LOG_CAT, "Model name from metadata: %s", name.c_str());

        if (name.find("smolvlm") != std::string::npos ||
            name.find("smol") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected SmolVLM model type");
            return VLMModelType::SmolVLM;
        }
        if (name.find("qwen") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected Qwen2-VL model type");
            return VLMModelType::Qwen2VL;
        }
        if (name.find("llava") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected LLaVA model type");
            return VLMModelType::LLaVA;
        }
    }

    // Check chat template as fallback
    const char* chat_template = llama_model_chat_template(model, nullptr);
    if (chat_template) {
        std::string tmpl(chat_template);
        if (tmpl.find("User:") != std::string::npos &&
            tmpl.find("Assistant:") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected SmolVLM model type from chat template");
            return VLMModelType::SmolVLM;
        }
    }

    RAC_LOG_DEBUG(LOG_CAT, "Using generic chat template");
    return VLMModelType::Generic;
}

/**
 * Format prompt using model's built-in chat template via llama_chat_apply_template.
 * Falls back to manual formatting if template application fails.
 */
std::string format_vlm_prompt_with_template(llama_model* model, const std::string& user_prompt,
                                            const char* image_marker, bool has_image) {
    // Build user content with image marker if present
    std::string user_content;
    if (has_image) {
        user_content = std::string(image_marker) + user_prompt;
    } else {
        user_content = user_prompt;
    }

    // Get the model's chat template
    const char* tmpl = llama_model_chat_template(model, nullptr);

    // Try to use llama_chat_apply_template
    if (tmpl) {
        RAC_LOG_DEBUG(LOG_CAT, "Using model chat template: %.80s...", tmpl);

        llama_chat_message messages[1];
        messages[0].role = "user";
        messages[0].content = user_content.c_str();

        // First call to get required buffer size
        int32_t size = llama_chat_apply_template(tmpl, messages, 1, true, nullptr, 0);
        if (size > 0) {
            std::vector<char> buf(size + 1);
            int32_t result = llama_chat_apply_template(tmpl, messages, 1, true, buf.data(), buf.size());
            if (result > 0) {
                std::string formatted(buf.data(), result);
                RAC_LOG_DEBUG(LOG_CAT, "Template-formatted prompt (%d chars): %s",
                              (int)formatted.length(), formatted.c_str());
                return formatted;
            }
        }
        RAC_LOG_WARNING(LOG_CAT, "llama_chat_apply_template failed (size=%d), falling back to manual", size);
    } else {
        RAC_LOG_DEBUG(LOG_CAT, "No chat template in model, using manual formatting");
    }

    // Fallback: manual chatml format (works for most models)
    std::string formatted = "<|im_start|>user\n";
    formatted += user_content;
    formatted += "<|im_end|>\n<|im_start|>assistant\n";

    RAC_LOG_DEBUG(LOG_CAT, "Manual-formatted prompt (%d chars): %s",
                  (int)formatted.length(), formatted.c_str());
    return formatted;
}

/**
 * Get the image marker string.
 * When mtmd is available, uses the default marker from mtmd.
 * Otherwise falls back to a generic "<image>" marker.
 */
const char* get_image_marker() {
#ifdef RAC_VLM_USE_MTMD
    return mtmd_default_marker();
#else
    return "<image>";
#endif
}

/**
 * Configure the sampler chain with the given generation parameters.
 * Only rebuilds the sampler when parameters actually change, avoiding
 * unnecessary heap allocations on every inference call.
 */
void configure_sampler(LlamaCppVLMBackend* backend, const rac_vlm_options_t* options) {
    // Determine parameters from options or use defaults
    float temperature = 0.7f;
    float top_p = 0.9f;

    if (options) {
        if (options->temperature >= 0.0f) {
            temperature = options->temperature;
        }
        if (options->top_p > 0.0f && options->top_p <= 1.0f) {
            top_p = options->top_p;
        }
    }

    // Skip rebuild if params haven't changed and sampler already exists
    if (backend->sampler &&
        backend->cached_temperature == temperature &&
        backend->cached_top_p == top_p) {
        return;
    }

    // Free existing sampler
    if (backend->sampler) {
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
    }

    // Build new sampler chain (consistent with LLM backend: greedy when temp <= 0)
    llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
    sampler_params.no_perf = true;  // Disable perf tracking (consistent with LLM backend)
    backend->sampler = llama_sampler_chain_init(sampler_params);

    if (temperature > 0.0f) {
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_p(top_p, 1));
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    } else {
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_greedy());
    }

    // Cache the params for next comparison
    backend->cached_temperature = temperature;
    backend->cached_top_p = top_p;

    RAC_LOG_DEBUG(LOG_CAT, "Sampler configured: temp=%.2f, top_p=%.2f", temperature, top_p);
}

/**
 * Prepare the VLM context for generation: reset state, configure sampler,
 * build prompt, load image (if provided), tokenize, and evaluate.
 * After success, the backend is ready for token sampling (n_past is set).
 *
 * Shared between rac_vlm_llamacpp_process() and rac_vlm_llamacpp_process_stream()
 * to eliminate code duplication (~100 lines of identical prompt prep logic).
 */
rac_result_t prepare_vlm_context(LlamaCppVLMBackend* backend,
                                  const rac_vlm_image_t* image,
                                  const char* prompt,
                                  const rac_vlm_options_t* options) {
    backend->cancel_requested = false;
    configure_sampler(backend, options);

    // Clear KV cache before each new request
    llama_memory_t mem = llama_get_memory(backend->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    backend->n_past = 0;

    // Build prompt with image handling
    std::string full_prompt;
    bool has_image = false;
    const char* image_marker = get_image_marker();

#ifdef RAC_VLM_USE_MTMD
    mtmd_bitmap* bitmap = nullptr;

    if (image && backend->mtmd_ctx) {
        if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
            bitmap = mtmd_helper_bitmap_init_from_file(backend->mtmd_ctx, image->file_path);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
            bitmap = mtmd_bitmap_init(image->width, image->height, image->pixel_data);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_BASE64 && image->base64_data) {
            RAC_LOG_WARNING(LOG_CAT, "Base64 image format not yet supported, using text-only");
        }

        has_image = (bitmap != nullptr);
        if (!has_image && image->format != RAC_VLM_IMAGE_FORMAT_BASE64) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load image");
            return RAC_ERROR_INVALID_INPUT;
        }
    }

    full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, has_image);

    // Tokenize and evaluate with MTMD if image present
    if (backend->mtmd_ctx && bitmap) {
        mtmd_input_chunks* chunks = mtmd_input_chunks_init();

        mtmd_input_text text;
        text.text = full_prompt.c_str();
        text.add_special = true;
        text.parse_special = true;

        const mtmd_bitmap* bitmaps[] = { bitmap };
        int32_t tokenize_result = mtmd_tokenize(backend->mtmd_ctx, chunks, &text, bitmaps, 1);

        if (tokenize_result != 0) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to tokenize prompt with image: %d", tokenize_result);
            mtmd_bitmap_free(bitmap);
            mtmd_input_chunks_free(chunks);
            return RAC_ERROR_PROCESSING_FAILED;
        }

        llama_pos new_n_past = 0;
        int32_t eval_result = mtmd_helper_eval_chunks(
            backend->mtmd_ctx, backend->ctx, chunks,
            0, 0,
            backend->config.batch_size > 0 ? backend->config.batch_size : kDefaultBatchSize,
            true, &new_n_past
        );

        mtmd_bitmap_free(bitmap);
        mtmd_input_chunks_free(chunks);

        if (eval_result != 0) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to evaluate chunks: %d", eval_result);
            return RAC_ERROR_PROCESSING_FAILED;
        }

        backend->n_past = new_n_past;
    } else
#endif
    {
        // Text-only mode
        full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, false);

        const llama_vocab* vocab = llama_model_get_vocab(backend->model);
        std::vector<llama_token> tokens(full_prompt.size() + 16);
        int n_tokens = llama_tokenize(vocab, full_prompt.c_str(), full_prompt.size(),
                                      tokens.data(), tokens.size(), true, true);
        if (n_tokens < 0) {
            tokens.resize(-n_tokens);
            n_tokens = llama_tokenize(vocab, full_prompt.c_str(), full_prompt.size(),
                                      tokens.data(), tokens.size(), true, true);
        }
        tokens.resize(n_tokens);

        llama_batch batch = llama_batch_init(n_tokens, 0, 1);
        for (int i = 0; i < n_tokens; i++) {
            batch.token[i] = tokens[i];
            batch.pos[i] = i;
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = 0;
            batch.logits[i] = (i == n_tokens - 1);
        }
        batch.n_tokens = n_tokens;

        if (llama_decode(backend->ctx, batch) != 0) {
            llama_batch_free(batch);
            RAC_LOG_ERROR(LOG_CAT, "Failed to decode prompt");
            return RAC_ERROR_PROCESSING_FAILED;
        }

        llama_batch_free(batch);
        backend->n_past = n_tokens;
    }

    return RAC_SUCCESS;
}

// Verify backend struct size hasn't grown unexpectedly (catches accidental
// large member additions that might hurt cache locality).
static_assert(sizeof(LlamaCppVLMBackend) <= 512,
              "LlamaCppVLMBackend grew unexpectedly — review member layout");

}  // namespace

// =============================================================================
// LIFECYCLE MANAGEMENT
// =============================================================================

extern "C" {

rac_result_t rac_vlm_llamacpp_create(const char* model_path, const char* mmproj_path,
                                     const rac_vlm_llamacpp_config_t* config,
                                     rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = new (std::nothrow) LlamaCppVLMBackend();
    if (!backend) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (config) {
        backend->config = *config;
    }

    if (model_path) {
        backend->model_path = model_path;
    }
    if (mmproj_path) {
        backend->mmproj_path = mmproj_path;
    }

    *out_handle = backend;
    RAC_LOG_INFO(LOG_CAT, "Created VLM backend");
    return RAC_SUCCESS;
}

rac_result_t rac_vlm_llamacpp_load_model(rac_handle_t handle, const char* model_path,
                                         const char* mmproj_path,
                                         const rac_vlm_llamacpp_config_t* config) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Update config if provided
    if (config) {
        backend->config = *config;
    }

    RAC_LOG_INFO(LOG_CAT, "Loading VLM model: %s", model_path);
    if (mmproj_path) {
        RAC_LOG_INFO(LOG_CAT, "With vision projector: %s", mmproj_path);
    }

    // Initialize llama backend
    llama_backend_init();

    // Load model
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = backend->config.gpu_layers;

    backend->model = llama_model_load_from_file(model_path, model_params);
    if (!backend->model) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load model: %s", model_path);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Determine context size
    int ctx_size = backend->config.context_size;
    if (ctx_size <= 0) {
        ctx_size = llama_model_n_ctx_train(backend->model);
        if (ctx_size > kDefaultMaxContextSize) ctx_size = kDefaultMaxContextSize;  // Cap for mobile
    }
    backend->context_size = ctx_size;

    // Create context
    int n_threads = get_num_threads(backend->config.num_threads);
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_batch = backend->config.batch_size > 0 ? backend->config.batch_size : kDefaultBatchSize;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    backend->ctx = llama_init_from_model(backend->model, ctx_params);
    if (!backend->ctx) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create context");
        llama_model_free(backend->model);
        backend->model = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Initialize sampler with default parameters
    // Sampler is reconfigured per-request in process()/process_stream() to respect user options
    configure_sampler(backend, nullptr);

#ifdef RAC_VLM_USE_MTMD
    // Initialize mtmd context if mmproj provided
    if (mmproj_path && mmproj_path[0]) {
        mtmd_context_params mparams = mtmd_context_params_default();
        mparams.use_gpu = backend->config.use_gpu_vision;
        mparams.n_threads = n_threads;
        mparams.print_timings = false;
        mparams.warmup = true;

        backend->mtmd_ctx = mtmd_init_from_file(mmproj_path, backend->model, mparams);
        if (!backend->mtmd_ctx) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load vision projector: %s", mmproj_path);
            // Continue without vision - will work as text-only LLM
            RAC_LOG_WARNING(LOG_CAT, "VLM will operate in text-only mode");
        } else {
            RAC_LOG_INFO(LOG_CAT, "Vision projector loaded successfully");
        }
        backend->mmproj_path = mmproj_path;
    }
#endif

    backend->model_path = model_path;
    backend->model_loaded = true;
    backend->n_past = 0;

    // Detect model type for chat template
    backend->model_type = detect_vlm_model_type(backend->model);

    RAC_LOG_INFO(LOG_CAT, "VLM model loaded successfully (ctx=%d, threads=%d)", ctx_size, n_threads);
    return RAC_SUCCESS;
}

rac_result_t rac_vlm_llamacpp_unload_model(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

#ifdef RAC_VLM_USE_MTMD
    if (backend->mtmd_ctx) {
        mtmd_free(backend->mtmd_ctx);
        backend->mtmd_ctx = nullptr;
    }
#endif

    if (backend->sampler) {
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
    }

    if (backend->ctx) {
        llama_free(backend->ctx);
        backend->ctx = nullptr;
    }

    if (backend->model) {
        llama_model_free(backend->model);
        backend->model = nullptr;
    }

    backend->model_loaded = false;
    backend->n_past = 0;
    RAC_LOG_INFO(LOG_CAT, "VLM model unloaded");
    return RAC_SUCCESS;
}

rac_bool_t rac_vlm_llamacpp_is_model_loaded(rac_handle_t handle) {
    if (!handle) return RAC_FALSE;
    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    return backend->model_loaded ? RAC_TRUE : RAC_FALSE;
}

void rac_vlm_llamacpp_destroy(rac_handle_t handle) {
    if (!handle) return;

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);

    // Unload model first
    rac_vlm_llamacpp_unload_model(handle);

    delete backend;
    RAC_LOG_INFO(LOG_CAT, "VLM backend destroyed");
}

// =============================================================================
// INFERENCE
// =============================================================================

rac_result_t rac_vlm_llamacpp_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                      const char* prompt, const rac_vlm_options_t* options,
                                      rac_vlm_result_t* out_result) {
    if (!handle || !prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded");
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    // Shared context preparation: reset, configure sampler, build prompt, evaluate
    rac_result_t prep_result = prepare_vlm_context(backend, image, prompt, options);
    if (prep_result != RAC_SUCCESS) {
        return prep_result;
    }

    // Generate response (batch mode — accumulate all tokens)
    const int max_tokens = (options && options->max_tokens > 0) ? options->max_tokens : kDefaultMaxTokens;
    std::string response;
    response.reserve(kDefaultMaxTokens);  // Typical VLM responses are a few hundred tokens
    int tokens_generated = 0;

    llama_batch batch = llama_batch_init(1, 0, 1);
    const llama_vocab* const vocab = llama_model_get_vocab(backend->model);

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        char buf[256];
        int len = llama_token_to_piece(vocab, token, buf, sizeof(buf) - 1, 0, true);
        if (len > 0) {
            response.append(buf, len);
        }
        tokens_generated++;

        // Prepare next token
        batch.token[0] = token;
        batch.pos[0] = backend->n_past++;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = true;
        batch.n_tokens = 1;

        if (llama_decode(backend->ctx, batch) != 0) {
            break;
        }
    }

    llama_batch_free(batch);

    // Fill result
    out_result->text = strdup(response.c_str());
    if (!out_result->text) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate result text");
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->completion_tokens = tokens_generated;
    out_result->prompt_tokens = backend->n_past - tokens_generated;
    out_result->total_tokens = backend->n_past;

    RAC_LOG_INFO(LOG_CAT, "Generated %d tokens", tokens_generated);
    return RAC_SUCCESS;
}

rac_result_t rac_vlm_llamacpp_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                             const char* prompt, const rac_vlm_options_t* options,
                                             rac_vlm_llamacpp_stream_callback_fn callback,
                                             void* user_data) {
    if (!handle || !prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded");
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    // Shared context preparation: reset, configure sampler, build prompt, evaluate
    rac_result_t prep_result = prepare_vlm_context(backend, image, prompt, options);
    if (prep_result != RAC_SUCCESS) {
        return prep_result;
    }

    // Generate response (streaming mode — callback per token)
    const int max_tokens = (options && options->max_tokens > 0) ? options->max_tokens : kDefaultMaxTokens;

    llama_batch batch = llama_batch_init(1, 0, 1);
    const llama_vocab* const vocab = llama_model_get_vocab(backend->model);

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        bool is_eog = llama_vocab_is_eog(vocab, token);

        char buf[256];
        int len = llama_token_to_piece(vocab, token, buf, sizeof(buf) - 1, 0, true);
        if (len > 0) {
            buf[len] = '\0';
            if (callback(buf, is_eog ? RAC_TRUE : RAC_FALSE, user_data) == RAC_FALSE) {
                break;  // Callback requested stop
            }
        }

        if (is_eog) {
            break;
        }

        // Prepare next token
        batch.token[0] = token;
        batch.pos[0] = backend->n_past++;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = true;
        batch.n_tokens = 1;

        if (llama_decode(backend->ctx, batch) != 0) {
            break;
        }
    }

    llama_batch_free(batch);
    return RAC_SUCCESS;
}

void rac_vlm_llamacpp_cancel(rac_handle_t handle) {
    if (!handle) return;
    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    backend->cancel_requested = true;
}

rac_result_t rac_vlm_llamacpp_get_model_info(rac_handle_t handle, char** out_json) {
    if (!handle || !out_json) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    // Build simple JSON info
    char buffer[1024];
    snprintf(buffer, sizeof(buffer),
             "{\"context_size\":%d,\"model_path\":\"%s\",\"has_vision\":%s}",
             backend->context_size,
             backend->model_path.c_str(),
#ifdef RAC_VLM_USE_MTMD
             backend->mtmd_ctx ? "true" : "false"
#else
             "false"
#endif
    );

    *out_json = strdup(buffer);
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

}  // extern "C"
