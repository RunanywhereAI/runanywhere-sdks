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
// INTERNAL BACKEND STATE
// =============================================================================

namespace {

/**
 * Internal VLM backend state.
 */
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

    // Thread safety
    mutable std::mutex mutex;
};

/**
 * Get number of CPU threads to use.
 */
int get_num_threads(int config_threads) {
    if (config_threads > 0)
        return config_threads;

    // Auto-detect based on hardware
    int threads = std::thread::hardware_concurrency();
    if (threads <= 0)
        threads = 4;
    if (threads > 8)
        threads = 8;  // Cap for mobile devices
    return threads;
}

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
        if (ctx_size > 4096) ctx_size = 4096;  // Cap for mobile
    }
    backend->context_size = ctx_size;

    // Create context
    int n_threads = get_num_threads(backend->config.num_threads);
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_batch = backend->config.batch_size > 0 ? backend->config.batch_size : 512;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    backend->ctx = llama_init_from_model(backend->model, ctx_params);
    if (!backend->ctx) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create context");
        llama_model_free(backend->model);
        backend->model = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Initialize sampler
    llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
    backend->sampler = llama_sampler_chain_init(sampler_params);
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_dist(42));

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

    backend->cancel_requested = false;

    // Clear KV cache (memory) before each new request to avoid position conflicts
    llama_memory_t mem = llama_get_memory(backend->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    backend->n_past = 0;

    // Build the prompt with image marker if we have an image
    std::string full_prompt;

#ifdef RAC_VLM_USE_MTMD
    mtmd_bitmap* bitmap = nullptr;

    if (image && backend->mtmd_ctx) {
        // Add image marker to prompt
        full_prompt = std::string(mtmd_default_marker()) + "\n" + prompt;

        // Load image based on format
        if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
            bitmap = mtmd_helper_bitmap_init_from_file(backend->mtmd_ctx, image->file_path);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
            bitmap = mtmd_bitmap_init(image->width, image->height, image->pixel_data);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_BASE64 && image->base64_data) {
            // Decode base64 first
            // For now, skip base64 - would need base64 decoder
            RAC_LOG_WARNING(LOG_CAT, "Base64 image format not yet supported, using text-only");
            full_prompt = prompt;
        }

        if (!bitmap && image->format != RAC_VLM_IMAGE_FORMAT_BASE64) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load image");
            return RAC_ERROR_INVALID_INPUT;
        }
    } else {
        full_prompt = prompt;
    }

    // Tokenize and evaluate
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

        // Evaluate chunks
        llama_pos new_n_past = 0;
        int32_t eval_result = mtmd_helper_eval_chunks(
            backend->mtmd_ctx,
            backend->ctx,
            chunks,
            0,  // n_past
            0,  // seq_id
            backend->config.batch_size > 0 ? backend->config.batch_size : 512,
            true,  // logits_last
            &new_n_past
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
        // Text-only mode - tokenize with llama
        full_prompt = prompt;

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

        // Create batch and decode
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

    // Generate response
    int max_tokens = (options && options->max_tokens > 0) ? options->max_tokens : 256;
    std::string response;
    int tokens_generated = 0;

    llama_batch batch = llama_batch_init(1, 0, 1);
    const llama_vocab* vocab = llama_model_get_vocab(backend->model);

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        char buf[256];
        int len = llama_token_to_piece(vocab, token, buf, sizeof(buf), 0, true);
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

    backend->cancel_requested = false;

    // Clear KV cache (memory) before each new request to avoid position conflicts
    llama_memory_t mem = llama_get_memory(backend->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    backend->n_past = 0;
    RAC_LOG_DEBUG(LOG_CAT, "Cleared KV cache for new request");

    // Build the prompt with image marker if we have an image
    std::string full_prompt;

#ifdef RAC_VLM_USE_MTMD
    mtmd_bitmap* bitmap = nullptr;

    if (image && backend->mtmd_ctx) {
        // Add image marker to prompt
        full_prompt = std::string(mtmd_default_marker()) + "\n" + prompt;

        // Load image based on format
        if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
            bitmap = mtmd_helper_bitmap_init_from_file(backend->mtmd_ctx, image->file_path);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
            bitmap = mtmd_bitmap_init(image->width, image->height, image->pixel_data);
        }

        if (!bitmap) {
            RAC_LOG_WARNING(LOG_CAT, "Failed to load image, using text-only");
            full_prompt = prompt;
        }
    } else {
        full_prompt = prompt;
    }

    // Tokenize and evaluate
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

        // Evaluate chunks
        llama_pos new_n_past = 0;
        int32_t eval_result = mtmd_helper_eval_chunks(
            backend->mtmd_ctx,
            backend->ctx,
            chunks,
            0,  // n_past
            0,  // seq_id
            backend->config.batch_size > 0 ? backend->config.batch_size : 512,
            true,  // logits_last
            &new_n_past
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
        full_prompt = prompt;

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
            return RAC_ERROR_PROCESSING_FAILED;
        }

        llama_batch_free(batch);
        backend->n_past = n_tokens;
    }

    // Generate response with streaming
    int max_tokens = (options && options->max_tokens > 0) ? options->max_tokens : 256;

    llama_batch batch = llama_batch_init(1, 0, 1);
    const llama_vocab* vocab = llama_model_get_vocab(backend->model);

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        bool is_eog = llama_vocab_is_eog(vocab, token);

        char buf[256];
        int len = llama_token_to_piece(vocab, token, buf, sizeof(buf), 0, true);
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
    return RAC_SUCCESS;
}

}  // extern "C"
