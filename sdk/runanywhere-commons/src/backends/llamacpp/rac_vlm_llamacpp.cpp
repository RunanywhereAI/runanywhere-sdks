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
 *
 * When system_prompt is provided, it is prepended as a system message.
 * For models that expect a system message (e.g. Qwen2-VL), a default is
 * injected based on the detected model_type when no explicit prompt is given.
 */
std::string format_vlm_prompt_with_template(llama_model* model, const std::string& user_prompt,
                                            const char* image_marker, bool has_image,
                                            const char* system_prompt, VLMModelType model_type) {
    // Build user content with image marker if present
    std::string user_content;
    if (has_image) {
        user_content = std::string(image_marker) + user_prompt;
    } else {
        user_content = user_prompt;
    }

    // Resolve system prompt: use explicit value, or inject a default for Qwen2-VL
    const char* effective_system = system_prompt;
    if (!effective_system && model_type == VLMModelType::Qwen2VL) {
        effective_system = "You are a helpful assistant.";
    }

    // Get the model's chat template
    const char* tmpl = llama_model_chat_template(model, nullptr);

    // Try to use llama_chat_apply_template
    if (tmpl) {
        RAC_LOG_DEBUG(LOG_CAT, "Using model chat template: %.80s...", tmpl);

        if (effective_system) {
            llama_chat_message messages[2];
            messages[0].role = "system";
            messages[0].content = effective_system;
            messages[1].role = "user";
            messages[1].content = user_content.c_str();

            int32_t size = llama_chat_apply_template(tmpl, messages, 2, true, nullptr, 0);
            if (size > 0) {
                std::vector<char> buf(size + 1);
                int32_t result = llama_chat_apply_template(tmpl, messages, 2, true, buf.data(), buf.size());
                if (result > 0) {
                    std::string formatted(buf.data(), result);
                    RAC_LOG_DEBUG(LOG_CAT, "Template-formatted prompt with system (%d chars): %s",
                                  (int)formatted.length(), formatted.c_str());
                    return formatted;
                }
            }
            RAC_LOG_WARNING(LOG_CAT, "llama_chat_apply_template with system failed (size=%d), trying without", size);
        }

        llama_chat_message messages[1];
        messages[0].role = "user";
        messages[0].content = user_content.c_str();

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
    std::string formatted;
    if (effective_system) {
        formatted = "<|im_start|>system\n";
        formatted += effective_system;
        formatted += "<|im_end|>\n";
    }
    formatted += "<|im_start|>user\n";
    formatted += user_content;
    formatted += "<|im_end|>\n<|im_start|>assistant\n";

    RAC_LOG_DEBUG(LOG_CAT, "Manual-formatted prompt (%d chars): %s",
                  (int)formatted.length(), formatted.c_str());
    return formatted;
}

/**
 * Legacy format function for backward compatibility.
 * Uses model type detection for manual template selection.
 */
std::string format_vlm_prompt(VLMModelType model_type, const std::string& user_prompt,
                               const char* image_marker, bool has_image) {
    std::string formatted;

    // Build user content with image marker
    std::string user_content;
    if (has_image) {
        user_content = std::string(image_marker) + user_prompt;
    } else {
        user_content = user_prompt;
    }

    switch (model_type) {
        case VLMModelType::SmolVLM:
            // SmolVLM format: <|im_start|>User: content \nAssistant:
            formatted = "<|im_start|>User: ";
            formatted += user_content;
            formatted += " \nAssistant:";
            break;

        case VLMModelType::Qwen2VL:
            // Qwen2-VL chatml format
            formatted = "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n";
            formatted += "<|im_start|>user\n";
            formatted += user_content;
            formatted += "<|im_end|>\n<|im_start|>assistant\n";
            break;

        case VLMModelType::LLaVA:
            // LLaVA/Vicuna format
            formatted = "USER: ";
            formatted += user_content;
            formatted += "\nASSISTANT:";
            break;

        case VLMModelType::Generic:
        default:
            // Generic chatml format
            formatted = "<|im_start|>user\n";
            formatted += user_content;
            formatted += "<|im_end|>\n<|im_start|>assistant\n";
            break;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Formatted prompt (%d chars): %.100s...",
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
 * Rebuilds the sampler to apply per-request temperature, top_p, etc.
 */
void configure_sampler(LlamaCppVLMBackend* backend, const rac_vlm_options_t* options) {
    // Free existing sampler
    if (backend->sampler) {
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
    }

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

    // Build new sampler chain.
    // Order follows llama.cpp common_sampler_init: penalties → DRY → top_p → min_p → temp → dist.
    // Penalties and DRY must be applied to raw logits before temperature softens them.
    llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
    backend->sampler = llama_sampler_chain_init(sampler_params);

    // Token-level repetition penalty + frequency/presence penalties
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_penalties(256, 1.3f, 0.1f, 0.1f));

    // DRY sampler: catches n-gram (sequence) repetition like "gó gó gó" where individual
    // tokens may alternate. Multiplier=0.8, base=1.75, allowed_length=2, last_n=256.
    const llama_vocab* vocab = llama_model_get_vocab(backend->model);
    static const char* dry_breakers[] = { "\n", ":", "\"", "*" };
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_dry(
        vocab, llama_model_n_ctx_train(backend->model),
        0.8f, 1.75f, 2, 256, dry_breakers, 4));

    llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_min_p(0.1f, 1));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(backend->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    RAC_LOG_INFO(LOG_CAT, "[v3] Sampler: temp=%.2f top_p=%.2f repeat=1.3 freq=0.1 pres=0.1 DRY=0.8 min_p=0.1 + repeat_guard=4",
                 temperature, top_p);
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
    int gpu_layers = backend->config.gpu_layers;
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = gpu_layers;

    backend->model = llama_model_load_from_file(model_path, model_params);
    if (!backend->model) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load model: %s", model_path);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Detect model type early — M-RoPE models (Qwen2-VL) produce NaN logits on
    // WebGPU due to shader precision limitations in the rotary position encoding.
    // The upstream WebGPU RoPE shader does contain M-RoPE handling, but f16
    // accumulation overflow causes all 151k+ logits to become NaN.
    //
    // Force CPU execution for these models by reloading with n_gpu_layers=0.
    // NOTE: default gpu_layers is -1 (all layers), so we check != 0 not > 0.
    //
    // PERFORMANCE: CPU fallback runs at ~1 tok/s in single-threaded WASM, which
    // is significantly slower than WebGPU-accelerated models like LFM2-VL (~15-20
    // tok/s). This is a correctness-over-speed trade-off until the WebGPU backend
    // resolves the M-RoPE precision issue.
    // TODO: re-test Qwen2-VL on WebGPU after future llama.cpp upgrades — the
    // Vulkan fp16 FA fix (b8168) and related precision work may eventually land
    // in the WebGPU backend as well.
    backend->model_type = detect_vlm_model_type(backend->model);
    bool force_cpu = false;

#ifdef RAC_VLM_USE_MTMD
    if (backend->model_type == VLMModelType::Qwen2VL && gpu_layers != 0) {
        RAC_LOG_WARNING(LOG_CAT, "Qwen2-VL uses M-RoPE which is incompatible with WebGPU "
                        "(gpu_layers=%d) — reloading with n_gpu_layers=0 for CPU execution",
                        gpu_layers);
        llama_model_free(backend->model);
        backend->model = nullptr;

        model_params.n_gpu_layers = 0;
        backend->model = llama_model_load_from_file(model_path, model_params);
        if (!backend->model) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to reload model for CPU: %s", model_path);
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        force_cpu = true;
        gpu_layers = 0;
    }
#endif

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

    // Initialize sampler with default parameters
    // Sampler is reconfigured per-request in process()/process_stream() to respect user options
    configure_sampler(backend, nullptr);

#ifdef RAC_VLM_USE_MTMD
    // Initialize mtmd context if mmproj provided
    if (mmproj_path && mmproj_path[0]) {
        mtmd_context_params mparams = mtmd_context_params_default();
        // Force CPU for vision encoder too when model requires CPU (M-RoPE)
        mparams.use_gpu = force_cpu ? false : backend->config.use_gpu_vision;
        mparams.n_threads = n_threads;
        mparams.print_timings = false;
        mparams.warmup = true;

        backend->mtmd_ctx = mtmd_init_from_file(mmproj_path, backend->model, mparams);
        if (!backend->mtmd_ctx) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load vision projector: %s", mmproj_path);
            // Continue without vision - will work as text-only LLM
            RAC_LOG_WARNING(LOG_CAT, "VLM will operate in text-only mode");
        } else {
            RAC_LOG_INFO(LOG_CAT, "Vision projector loaded successfully%s",
                         force_cpu ? " (CPU mode for M-RoPE compat)" : "");
        }
        backend->mmproj_path = mmproj_path;
    }
#endif

    backend->model_path = model_path;
    backend->model_loaded = true;
    backend->n_past = 0;

    RAC_LOG_INFO(LOG_CAT, "VLM model loaded (ctx=%d, threads=%d, gpu_layers=%d%s) [build:v4-cpu-mrope]",
                 ctx_size, n_threads, gpu_layers, force_cpu ? ", forced-cpu" : "");
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

    // Reconfigure sampler with per-request options (temperature, top_p)
    configure_sampler(backend, options);

    // Clear KV cache (memory) before each new request to avoid position conflicts
    llama_memory_t mem = llama_get_memory(backend->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    backend->n_past = 0;

    // Resolve effective model type: options override > auto-detected at load time
    VLMModelType effective_model_type = backend->model_type;
    if (options && options->model_family != RAC_VLM_MODEL_FAMILY_AUTO) {
        switch (options->model_family) {
            case RAC_VLM_MODEL_FAMILY_QWEN2_VL: effective_model_type = VLMModelType::Qwen2VL; break;
            case RAC_VLM_MODEL_FAMILY_SMOLVLM:  effective_model_type = VLMModelType::SmolVLM; break;
            case RAC_VLM_MODEL_FAMILY_LLAVA:     effective_model_type = VLMModelType::LLaVA;   break;
            default:                             effective_model_type = VLMModelType::Generic;  break;
        }
    }

    const char* system_prompt = (options && options->system_prompt) ? options->system_prompt : nullptr;

    // Build the prompt with proper chat template formatting
    std::string full_prompt;
    bool has_image = false;
    const char* image_marker = get_image_marker();

#ifdef RAC_VLM_USE_MTMD
    mtmd_bitmap* bitmap = nullptr;

    if (image && backend->mtmd_ctx) {
        // Load image based on format
        if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
            bitmap = mtmd_helper_bitmap_init_from_file(backend->mtmd_ctx, image->file_path);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
            bitmap = mtmd_bitmap_init(image->width, image->height, image->pixel_data);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_BASE64 && image->base64_data) {
            // Decode base64 first
            // For now, skip base64 - would need base64 decoder
            RAC_LOG_WARNING(LOG_CAT, "Base64 image format not yet supported, using text-only");
        }

        has_image = (bitmap != nullptr);
        if (!has_image && image->format != RAC_VLM_IMAGE_FORMAT_BASE64) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load image");
            return RAC_ERROR_INVALID_INPUT;
        }
    }

    // Format prompt using model's built-in chat template
    full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, has_image,
                                                  system_prompt, effective_model_type);

    RAC_LOG_INFO(LOG_CAT, "[v3-process] Prompt (%d chars, img=%d, type=%d): %.200s",
                 (int)full_prompt.length(), has_image ? 1 : 0, (int)effective_model_type,
                 full_prompt.c_str());

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
        // Text-only mode - still apply chat template for consistent formatting
        full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, false,
                                                      system_prompt, effective_model_type);

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
    int max_tokens = (options && options->max_tokens > 0) ? options->max_tokens : 2048;
    std::string response;
    int tokens_generated = 0;

    llama_batch batch = llama_batch_init(1, 0, 1);
    const llama_vocab* vocab = llama_model_get_vocab(backend->model);

    // Runtime repetition guard: track last token and consecutive repeat count.
    // If the same token appears too many times in a row, the model is stuck and
    // we force-stop to avoid emitting garbage like "gó gó gó gó ...".
    llama_token prev_token = -1;
    int repeat_run = 0;
    constexpr int MAX_CONSECUTIVE_REPEATS = 4;

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        // Diagnostic: on first token, inspect logits for NaN/corruption
        if (i == 0) {
            float* logits = llama_get_logits(backend->ctx);
            int n_vocab = llama_vocab_n_tokens(vocab);
            if (logits && n_vocab > 0) {
                float max_logit = logits[0];
                int max_idx = 0;
                int nan_count = 0;
                int inf_count = 0;
                for (int v = 0; v < n_vocab; v++) {
                    if (logits[v] != logits[v]) nan_count++;       // NaN check
                    if (logits[v] > 1e30f || logits[v] < -1e30f) inf_count++;
                    if (logits[v] > max_logit) { max_logit = logits[v]; max_idx = v; }
                }
                RAC_LOG_INFO(LOG_CAT, "[v3-diag] Logits: n_vocab=%d, max_logit=%.4f at token %d, NaN=%d, Inf=%d",
                             n_vocab, max_logit, max_idx, nan_count, inf_count);
                // Log top 5 logits
                float top5_val[5] = {-1e30f, -1e30f, -1e30f, -1e30f, -1e30f};
                int   top5_idx[5] = {0, 0, 0, 0, 0};
                for (int v = 0; v < n_vocab; v++) {
                    if (logits[v] != logits[v]) continue; // skip NaN
                    for (int k = 0; k < 5; k++) {
                        if (logits[v] > top5_val[k]) {
                            for (int j = 4; j > k; j--) { top5_val[j] = top5_val[j-1]; top5_idx[j] = top5_idx[j-1]; }
                            top5_val[k] = logits[v]; top5_idx[k] = v;
                            break;
                        }
                    }
                }
                RAC_LOG_INFO(LOG_CAT, "[v3-diag] Top5: [%d]=%.2f [%d]=%.2f [%d]=%.2f [%d]=%.2f [%d]=%.2f",
                             top5_idx[0], top5_val[0], top5_idx[1], top5_val[1],
                             top5_idx[2], top5_val[2], top5_idx[3], top5_val[3],
                             top5_idx[4], top5_val[4]);
            }
        }

        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        // Detect stuck generation: same token repeated consecutively
        if (token == prev_token) {
            repeat_run++;
            if (repeat_run >= MAX_CONSECUTIVE_REPEATS) {
                RAC_LOG_WARNING(LOG_CAT, "Repetition guard: token %d repeated %d times, stopping",
                                token, repeat_run + 1);
                break;
            }
        } else {
            repeat_run = 0;
        }
        prev_token = token;

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

    // Reconfigure sampler with per-request options (temperature, top_p)
    configure_sampler(backend, options);

    // Clear KV cache (memory) before each new request to avoid position conflicts
    llama_memory_t mem = llama_get_memory(backend->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    backend->n_past = 0;
    RAC_LOG_DEBUG(LOG_CAT, "Cleared KV cache for new request");

    // Resolve effective model type: options override > auto-detected at load time
    VLMModelType effective_model_type = backend->model_type;
    if (options && options->model_family != RAC_VLM_MODEL_FAMILY_AUTO) {
        switch (options->model_family) {
            case RAC_VLM_MODEL_FAMILY_QWEN2_VL: effective_model_type = VLMModelType::Qwen2VL; break;
            case RAC_VLM_MODEL_FAMILY_SMOLVLM:  effective_model_type = VLMModelType::SmolVLM; break;
            case RAC_VLM_MODEL_FAMILY_LLAVA:     effective_model_type = VLMModelType::LLaVA;   break;
            default:                             effective_model_type = VLMModelType::Generic;  break;
        }
    }

    const char* system_prompt = (options && options->system_prompt) ? options->system_prompt : nullptr;

    // Build the prompt with proper chat template formatting
    std::string full_prompt;
    bool has_image = false;
    const char* image_marker = get_image_marker();

#ifdef RAC_VLM_USE_MTMD
    mtmd_bitmap* bitmap = nullptr;

    if (image && backend->mtmd_ctx) {
        // Load image based on format
        if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
            bitmap = mtmd_helper_bitmap_init_from_file(backend->mtmd_ctx, image->file_path);
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
            bitmap = mtmd_bitmap_init(image->width, image->height, image->pixel_data);
        }

        has_image = (bitmap != nullptr);
        if (!has_image) {
            RAC_LOG_WARNING(LOG_CAT, "Failed to load image, using text-only");
        }
    }

    // Format prompt using model's built-in chat template (streaming path)
    full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, has_image,
                                                  system_prompt, effective_model_type);

    RAC_LOG_INFO(LOG_CAT, "[v3-stream] Prompt (%d chars, img=%d, type=%d): %.200s",
                 (int)full_prompt.length(), has_image ? 1 : 0, (int)effective_model_type,
                 full_prompt.c_str());

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
        // Text-only mode - still apply chat template for consistent formatting
        full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, false,
                                                      system_prompt, effective_model_type);

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
    int max_tokens = (options && options->max_tokens > 0) ? options->max_tokens : 2048;

    llama_batch batch = llama_batch_init(1, 0, 1);
    const llama_vocab* vocab = llama_model_get_vocab(backend->model);

    // Runtime repetition guard (same as non-streaming path)
    llama_token prev_token = -1;
    int repeat_run = 0;
    constexpr int MAX_CONSECUTIVE_REPEATS = 4;

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        bool is_eog = llama_vocab_is_eog(vocab, token);

        // Detect stuck generation
        if (!is_eog) {
            if (token == prev_token) {
                repeat_run++;
                if (repeat_run >= MAX_CONSECUTIVE_REPEATS) {
                    RAC_LOG_WARNING(LOG_CAT, "Repetition guard: token %d repeated %d times, stopping",
                                    token, repeat_run + 1);
                    callback("", RAC_TRUE, user_data);
                    break;
                }
            } else {
                repeat_run = 0;
            }
            prev_token = token;
        }

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
