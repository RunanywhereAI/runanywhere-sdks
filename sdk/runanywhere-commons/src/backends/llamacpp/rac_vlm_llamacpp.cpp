/**
 * @file rac_vlm_llamacpp.cpp
 * @brief RunAnywhere Commons - LlamaCPP VLM Backend Implementation
 *
 * Vision Language Model backend using llama.cpp's multimodal (mtmd) API.
 * Supports VLM architectures including Qwen2-VL, SmolVLM, LLaVA, MiniCPM-V, etc.
 */

#include "rac/backends/rac_vlm_llamacpp.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <llama.h>

// llama.cpp multimodal support (mtmd)
#ifdef RAC_VLM_USE_MTMD
#include "clip.h"
#include "mtmd.h"
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

/**
 * Build combined prompt for VLM (image placeholder + user prompt).
 */
std::string build_vlm_prompt(const char* prompt, bool has_image) {
    std::string result;

    if (has_image) {
        // Use standard image placeholder token
        // Different models may use different tokens, but <image> is common
        result = "<image>\n";
    }

    if (prompt && prompt[0]) {
        result += prompt;
    }

    return result;
}

}  // namespace

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_vlm_llamacpp_create(const char* model_path, const char* mmproj_path,
                                     const rac_vlm_llamacpp_config_t* config,
                                     rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    auto* backend = new (std::nothrow) LlamaCppVLMBackend();
    if (!backend) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Apply configuration
    if (config) {
        backend->config = *config;
    }

    RAC_LOG_INFO(LOG_CAT, "Created VLM backend");

    // If model paths provided, load immediately
    if (model_path && model_path[0]) {
        rac_result_t result =
            rac_vlm_llamacpp_load_model(backend, model_path, mmproj_path, config);
        if (result != RAC_SUCCESS) {
            delete backend;
            return result;
        }
    }

    *out_handle = backend;
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

    // Unload existing model
    if (backend->model_loaded) {
        rac_vlm_llamacpp_unload_model(handle);
    }

    // Apply config if provided
    if (config) {
        backend->config = *config;
    }

    RAC_LOG_INFO(LOG_CAT, "Loading VLM model: %s", model_path);
    if (mmproj_path) {
        RAC_LOG_INFO(LOG_CAT, "Loading vision projector: %s", mmproj_path);
    }

    // Initialize llama backend if needed
    static bool llama_initialized = false;
    if (!llama_initialized) {
        llama_backend_init();
        llama_initialized = true;
    }

    // Load model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = backend->config.gpu_layers;

    // Load the LLM model
    backend->model = llama_model_load_from_file(model_path, model_params);
    if (!backend->model) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load model: %s", model_path);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Create context
    int n_threads = get_num_threads(backend->config.num_threads);
    int ctx_size = backend->config.context_size;
    if (ctx_size <= 0) {
        ctx_size = llama_model_n_ctx_train(backend->model);
        if (ctx_size > 8192)
            ctx_size = 8192;  // Cap for mobile
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    backend->ctx = llama_init_from_model(backend->model, ctx_params);
    if (!backend->ctx) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create context");
        llama_model_free(backend->model);
        backend->model = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Create sampler
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    backend->sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_dist(0));

#ifdef RAC_VLM_USE_MTMD
    // Load vision projector (multimodal context)
    if (mmproj_path && mmproj_path[0]) {
        mtmd_context_params mtmd_params = mtmd_context_params_default();
        mtmd_params.use_gpu = backend->config.use_gpu_vision;
        mtmd_params.n_threads = backend->config.vision_threads > 0 ? backend->config.vision_threads
                                                                   : n_threads;

        backend->mtmd_ctx = mtmd_init_from_file(mmproj_path, backend->model, mtmd_params);
        if (!backend->mtmd_ctx) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load vision projector: %s", mmproj_path);
            // Continue without vision - can still do text-only
            RAC_LOG_WARNING(LOG_CAT, "VLM will operate in text-only mode");
        }
    }
#else
    RAC_LOG_WARNING(LOG_CAT, "VLM multimodal support not compiled - vision disabled");
#endif

    backend->model_path = model_path;
    backend->mmproj_path = mmproj_path ? mmproj_path : "";
    backend->context_size = ctx_size;
    backend->model_loaded = true;

    RAC_LOG_INFO(LOG_CAT, "VLM model loaded successfully (ctx=%d, threads=%d)", ctx_size, n_threads);

    return RAC_SUCCESS;
}

rac_result_t rac_vlm_llamacpp_unload_model(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        return RAC_SUCCESS;
    }

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
    backend->model_path.clear();
    backend->mmproj_path.clear();

    RAC_LOG_INFO(LOG_CAT, "VLM model unloaded");

    return RAC_SUCCESS;
}

rac_bool_t rac_vlm_llamacpp_is_model_loaded(rac_handle_t handle) {
    if (!handle) {
        return RAC_FALSE;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    return backend->model_loaded ? RAC_TRUE : RAC_FALSE;
}

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

    memset(out_result, 0, sizeof(rac_vlm_result_t));
    backend->cancel_requested = false;

    auto start_time = std::chrono::steady_clock::now();

    // Get options
    int32_t max_tokens = options ? options->max_tokens : 2048;
    float temperature = options ? options->temperature : 0.7f;
    float top_p = options ? options->top_p : 0.9f;

    // Process image if provided
    int64_t image_encode_time_ms = 0;
    int32_t image_tokens = 0;

#ifdef RAC_VLM_USE_MTMD
    mtmd_bitmap* bitmap = nullptr;
    mtmd_input_chunks* chunks = nullptr;

    if (image && backend->mtmd_ctx) {
        auto image_start = std::chrono::steady_clock::now();

        // Load image based on format
        rac_image_data_t img_data = {};

        switch (image->format) {
            case RAC_VLM_IMAGE_FORMAT_FILE_PATH:
                if (image->file_path) {
                    if (rac_image_load_file(image->file_path, &img_data) != RAC_SUCCESS) {
                        RAC_LOG_ERROR(LOG_CAT, "Failed to load image: %s", image->file_path);
                        return RAC_ERROR_IMAGE_LOAD_FAILED;
                    }
                }
                break;

            case RAC_VLM_IMAGE_FORMAT_RGB_PIXELS:
                if (image->pixel_data && image->width > 0 && image->height > 0) {
                    // Copy pixel data
                    size_t size = image->width * image->height * 3;
                    img_data.pixels = (uint8_t*)malloc(size);
                    if (img_data.pixels) {
                        memcpy(img_data.pixels, image->pixel_data, size);
                        img_data.width = image->width;
                        img_data.height = image->height;
                        img_data.channels = 3;
                        img_data.size = size;
                    }
                }
                break;

            case RAC_VLM_IMAGE_FORMAT_BASE64:
                if (image->base64_data && image->data_size > 0) {
                    if (rac_image_decode_base64(image->base64_data, image->data_size, &img_data) !=
                        RAC_SUCCESS) {
                        RAC_LOG_ERROR(LOG_CAT, "Failed to decode base64 image");
                        return RAC_ERROR_IMAGE_LOAD_FAILED;
                    }
                }
                break;
        }

        if (img_data.pixels) {
            // Create mtmd bitmap
            bitmap = mtmd_bitmap_init(img_data.width, img_data.height, img_data.pixels);
            rac_image_free(&img_data);

            if (bitmap) {
                // Tokenize with image
                chunks = mtmd_input_chunks_init();
                mtmd_input_text input_text = {.text = prompt, .add_special = true, .parse_special = true};
                mtmd_tokenize(backend->mtmd_ctx, chunks, &input_text, &bitmap, 1);

                // Encode image
                for (size_t i = 0; i < mtmd_input_chunks_size(chunks); i++) {
                    const mtmd_input_chunk* chunk = mtmd_input_chunks_get(chunks, i);
                    if (mtmd_input_chunk_get_type(chunk) == MTMD_INPUT_CHUNK_TYPE_IMAGE) {
                        mtmd_encode_chunk(backend->mtmd_ctx, chunk);
                        image_tokens = mtmd_input_chunk_get_n_tokens(chunk);
                    }
                }
            }
        }

        auto image_end = std::chrono::steady_clock::now();
        image_encode_time_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            image_end - image_start).count();

        RAC_LOG_DEBUG(LOG_CAT, "Image encoded in %lld ms, %d tokens", image_encode_time_ms,
                      image_tokens);
    }
#endif

    // Build prompt and tokenize
    std::string full_prompt = build_vlm_prompt(prompt, image != nullptr);
    std::vector<llama_token> tokens = llama_tokenize(backend->model, full_prompt, true, true);

    if (tokens.empty()) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to tokenize prompt");
        return RAC_ERROR_TOKENIZATION_FAILED;
    }

    int32_t prompt_tokens = static_cast<int32_t>(tokens.size()) + image_tokens;

    // Clear KV cache
    llama_kv_cache_clear(backend->ctx);

    // Process prompt tokens
    llama_batch batch = llama_batch_init(512, 0, 1);

    for (size_t i = 0; i < tokens.size(); i++) {
        llama_batch_add(batch, tokens[i], i, {0}, false);
    }
    batch.logits[batch.n_tokens - 1] = true;

    if (llama_decode(backend->ctx, batch) != 0) {
        llama_batch_free(batch);
        RAC_LOG_ERROR(LOG_CAT, "Failed to decode prompt");
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Generate response
    std::string response;
    int generated_tokens = 0;
    auto first_token_time = std::chrono::steady_clock::time_point();
    bool first_token_recorded = false;

    llama_token eos_token = llama_token_eos(backend->model);

    while (generated_tokens < max_tokens && !backend->cancel_requested) {
        llama_token new_token = llama_sampler_sample(backend->sampler, backend->ctx, -1);

        if (new_token == eos_token) {
            break;
        }

        if (!first_token_recorded) {
            first_token_time = std::chrono::steady_clock::now();
            first_token_recorded = true;
        }

        char buf[256];
        int len = llama_token_to_piece(backend->model, new_token, buf, sizeof(buf), 0, true);
        if (len > 0) {
            response.append(buf, len);
        }

        generated_tokens++;

        // Prepare next batch
        llama_batch_clear(batch);
        llama_batch_add(batch, new_token, prompt_tokens + generated_tokens, {0}, true);

        if (llama_decode(backend->ctx, batch) != 0) {
            break;
        }
    }

    llama_batch_free(batch);

#ifdef RAC_VLM_USE_MTMD
    if (chunks) {
        mtmd_input_chunks_free(chunks);
    }
    if (bitmap) {
        mtmd_bitmap_free(bitmap);
    }
#endif

    auto end_time = std::chrono::steady_clock::now();

    // Build result
    out_result->text = strdup(response.c_str());
    out_result->prompt_tokens = prompt_tokens;
    out_result->image_tokens = image_tokens;
    out_result->completion_tokens = generated_tokens;
    out_result->total_tokens = prompt_tokens + generated_tokens;
    out_result->image_encode_time_ms = image_encode_time_ms;

    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    out_result->total_time_ms = total_duration.count();

    if (first_token_recorded) {
        auto ttft_duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            first_token_time - start_time);
        out_result->time_to_first_token_ms = ttft_duration.count();
    }

    if (out_result->total_time_ms > 0) {
        out_result->tokens_per_second = static_cast<float>(generated_tokens) /
            (static_cast<float>(out_result->total_time_ms) / 1000.0f);
    }

    RAC_LOG_INFO(LOG_CAT, "VLM generation complete: %d tokens, %.1f tok/s",
                 generated_tokens, out_result->tokens_per_second);

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

    // Get options
    int32_t max_tokens = options ? options->max_tokens : 2048;

    // For streaming, we follow the same process as non-streaming but call callback on each token
    // Note: Full implementation would include image processing similar to rac_vlm_llamacpp_process

    // Build prompt
    std::string full_prompt = build_vlm_prompt(prompt, image != nullptr);
    std::vector<llama_token> tokens = llama_tokenize(backend->model, full_prompt, true, true);

    if (tokens.empty()) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to tokenize prompt");
        return RAC_ERROR_TOKENIZATION_FAILED;
    }

    // Clear KV cache
    llama_kv_cache_clear(backend->ctx);

    // Process prompt
    llama_batch batch = llama_batch_init(512, 0, 1);

    for (size_t i = 0; i < tokens.size(); i++) {
        llama_batch_add(batch, tokens[i], i, {0}, false);
    }
    batch.logits[batch.n_tokens - 1] = true;

    if (llama_decode(backend->ctx, batch) != 0) {
        llama_batch_free(batch);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Generate with streaming
    int generated_tokens = 0;
    llama_token eos_token = llama_token_eos(backend->model);

    while (generated_tokens < max_tokens && !backend->cancel_requested) {
        llama_token new_token = llama_sampler_sample(backend->sampler, backend->ctx, -1);

        bool is_final = (new_token == eos_token) || (generated_tokens + 1 >= max_tokens);

        if (new_token != eos_token) {
            char buf[256];
            int len = llama_token_to_piece(backend->model, new_token, buf, sizeof(buf), 0, true);
            if (len > 0) {
                buf[len] = '\0';
                if (!callback(buf, is_final ? RAC_TRUE : RAC_FALSE, user_data)) {
                    // User requested stop
                    break;
                }
            }
        }

        if (is_final) {
            break;
        }

        generated_tokens++;

        llama_batch_clear(batch);
        llama_batch_add(batch, new_token, tokens.size() + generated_tokens, {0}, true);

        if (llama_decode(backend->ctx, batch) != 0) {
            break;
        }
    }

    llama_batch_free(batch);

    return RAC_SUCCESS;
}

void rac_vlm_llamacpp_cancel(rac_handle_t handle) {
    if (!handle) {
        return;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    backend->cancel_requested = true;

    RAC_LOG_DEBUG(LOG_CAT, "VLM generation cancelled");
}

rac_result_t rac_vlm_llamacpp_get_model_info(rac_handle_t handle, char** out_json) {
    if (!handle || !out_json) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        *out_json = strdup("{}");
        return RAC_SUCCESS;
    }

    // Build JSON info
    char buf[1024];
    snprintf(buf, sizeof(buf),
             R"({"model_path":"%s","mmproj_path":"%s","context_size":%d,"has_vision":%s})",
             backend->model_path.c_str(),
             backend->mmproj_path.c_str(),
             backend->context_size,
#ifdef RAC_VLM_USE_MTMD
             backend->mtmd_ctx ? "true" : "false"
#else
             "false"
#endif
    );

    *out_json = strdup(buf);
    return RAC_SUCCESS;
}

void rac_vlm_llamacpp_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);

    rac_vlm_llamacpp_unload_model(handle);

    delete backend;

    RAC_LOG_DEBUG(LOG_CAT, "VLM backend destroyed");
}

}  // extern "C"
