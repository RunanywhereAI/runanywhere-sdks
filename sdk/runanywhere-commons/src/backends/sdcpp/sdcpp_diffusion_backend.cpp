/**
 * @file sdcpp_diffusion_backend.cpp
 * @brief Internal C++ wrapper around stable-diffusion.cpp
 *
 * Implements the SdcppDiffusionBackend class that wraps the sd.cpp C API.
 * Uses the modern params-struct API (new_sd_ctx with sd_ctx_params_t,
 * generate_image with sd_img_gen_params_t).
 *
 * On iOS it uses the Metal backend, on Android it uses CPU/Vulkan/OpenCL.
 */

#include "sdcpp_diffusion_backend.h"

#include <chrono>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// stable-diffusion.cpp public API header
#include "stable-diffusion.h"

// On Android, use __android_log_print directly for guaranteed logcat output.
// RAC_LOG macros fall back to stderr which is invisible on Android.
#ifdef __ANDROID__
#include <android/log.h>
#define SDCPP_LOG_TAG "RAC.sd.cpp"
#define SDCPP_LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, SDCPP_LOG_TAG, __VA_ARGS__)
#define SDCPP_LOGI(...) __android_log_print(ANDROID_LOG_INFO, SDCPP_LOG_TAG, __VA_ARGS__)
#define SDCPP_LOGW(...) __android_log_print(ANDROID_LOG_WARN, SDCPP_LOG_TAG, __VA_ARGS__)
#define SDCPP_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, SDCPP_LOG_TAG, __VA_ARGS__)
#else
#define SDCPP_LOGD(...) RAC_LOG_DEBUG("sd.cpp", __VA_ARGS__)
#define SDCPP_LOGI(...) RAC_LOG_INFO("sd.cpp", __VA_ARGS__)
#define SDCPP_LOGW(...) RAC_LOG_WARNING("sd.cpp", __VA_ARGS__)
#define SDCPP_LOGE(...) RAC_LOG_ERROR("sd.cpp", __VA_ARGS__)
#endif

static const char* LOG_CAT = "Backend.SDCPP";

// =============================================================================
// SD.CPP LOG CALLBACK → redirect to logcat (Android) or RAC logger (other)
// =============================================================================

static void sdcpp_log_callback(enum sd_log_level_t level, const char* text, void* /*data*/) {
    if (!text) return;
    // Strip trailing newline that sd.cpp often adds
    std::string msg(text);
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
        msg.pop_back();
    }
    if (msg.empty()) return;

    switch (level) {
        case SD_LOG_DEBUG:
            SDCPP_LOGD("%s", msg.c_str());
            break;
        case SD_LOG_INFO:
            SDCPP_LOGI("%s", msg.c_str());
            break;
        case SD_LOG_WARN:
            SDCPP_LOGW("%s", msg.c_str());
            break;
        case SD_LOG_ERROR:
            SDCPP_LOGE("%s", msg.c_str());
            break;
        default:
            SDCPP_LOGI("%s", msg.c_str());
            break;
    }
}

namespace runanywhere {

// =============================================================================
// SCHEDULER MAPPING
// =============================================================================

static enum sample_method_t map_scheduler_to_sdcpp_method(rac_diffusion_scheduler_t scheduler) {
    switch (scheduler) {
        case RAC_DIFFUSION_SCHEDULER_EULER:
            return EULER_SAMPLE_METHOD;
        case RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL:
            return EULER_A_SAMPLE_METHOD;
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M:
            return DPMPP2M_SAMPLE_METHOD;
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS:
            return DPMPP2M_SAMPLE_METHOD;  // scheduler_t handles Karras
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_SDE:
            return DPMPP2Mv2_SAMPLE_METHOD;
        case RAC_DIFFUSION_SCHEDULER_DDIM:
            return DDIM_TRAILING_SAMPLE_METHOD;
        case RAC_DIFFUSION_SCHEDULER_PNDM:
            return IPNDM_SAMPLE_METHOD;
        case RAC_DIFFUSION_SCHEDULER_LMS:
            return LCM_SAMPLE_METHOD;
        default:
            return EULER_A_SAMPLE_METHOD;
    }
}

static enum scheduler_t map_scheduler_to_sdcpp_sched(rac_diffusion_scheduler_t scheduler) {
    switch (scheduler) {
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS:
            return KARRAS_SCHEDULER;
        default:
            return DISCRETE_SCHEDULER;
    }
}

// =============================================================================
// SD.CPP STEP CALLBACK
// =============================================================================

static void sdcpp_step_callback(int step, int steps, float /*time*/, void* data) {
    if (!data) return;

    auto* ctx = static_cast<SdcppProgressContext*>(data);

    if (ctx->cancel_flag && ctx->cancel_flag->load()) {
        return;
    }

    if (ctx->callback) {
        rac_diffusion_progress_t progress = {};
        progress.current_step = step + 1;
        progress.total_steps = steps;
        progress.progress =
            static_cast<float>(step + 1) / static_cast<float>(steps > 0 ? steps : 1);
        progress.stage = "Denoising";
        progress.intermediate_image_data = nullptr;
        progress.intermediate_image_size = 0;

        rac_bool_t should_continue = ctx->callback(&progress, ctx->user_data);
        if (!should_continue && ctx->cancel_flag) {
            ctx->cancel_flag->store(true);
        }
    }
}

// =============================================================================
// CONSTRUCTOR / DESTRUCTOR
// =============================================================================

SdcppDiffusionBackend::SdcppDiffusionBackend() {
    // Redirect sd.cpp logging to RAC logger so it appears in logcat on Android.
    sd_set_log_callback(sdcpp_log_callback, nullptr);
}

SdcppDiffusionBackend::~SdcppDiffusionBackend() { cleanup(); }

// =============================================================================
// MODEL LOADING
// =============================================================================

rac_result_t SdcppDiffusionBackend::load_model(const char* model_path,
                                                const rac_diffusion_config_t* config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_path) {
        SDCPP_LOGE("Model path is null");
        return RAC_ERROR_NULL_POINTER;
    }

    // Cleanup any existing context
    if (ctx_) {
        free_sd_ctx(ctx_);
        ctx_ = nullptr;
    }

    model_path_ = model_path;
    cancel_requested_.store(false);

    if (config) {
        model_variant_ = config->model_variant;
        reduce_memory_ = config->reduce_memory == RAC_TRUE;
    }

    SDCPP_LOGI("Loading sd.cpp model: %s (variant=%d)", model_path,
               static_cast<int>(model_variant_));

    // Initialize context params with defaults
    sd_ctx_params_t ctx_params;
    sd_ctx_params_init(&ctx_params);

    ctx_params.model_path = model_path;
    ctx_params.vae_decode_only = true;  // Only need decoding for txt2img
    ctx_params.free_params_immediately = reduce_memory_;
    ctx_params.n_threads = -1;  // Auto-detect
    ctx_params.wtype = SD_TYPE_COUNT;  // Auto quantization
    ctx_params.rng_type = STD_DEFAULT_RNG;
    ctx_params.flash_attn = false;
    ctx_params.diffusion_flash_attn = true;

    // Create sd.cpp context
    ctx_ = new_sd_ctx(&ctx_params);

    if (!ctx_) {
        SDCPP_LOGE("Failed to create sd.cpp context for model: %s", model_path);
        model_path_.clear();
        return RAC_ERROR_GENERATION_FAILED;
    }

    SDCPP_LOGI("sd.cpp model loaded successfully: %s", model_path);
    return RAC_SUCCESS;
}

// =============================================================================
// GENERATION
// =============================================================================

rac_result_t SdcppDiffusionBackend::generate(const rac_diffusion_options_t* options,
                                              rac_diffusion_result_t* out_result) {
    return generate_internal(options, nullptr, nullptr, out_result);
}

rac_result_t SdcppDiffusionBackend::generate_with_progress(
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback, void* user_data,
    rac_diffusion_result_t* out_result) {
    return generate_internal(options, progress_callback, user_data, out_result);
}

rac_result_t SdcppDiffusionBackend::generate_internal(
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback, void* user_data,
    rac_diffusion_result_t* out_result) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!ctx_) {
        SDCPP_LOGE("No model loaded");
        return RAC_ERROR_NOT_INITIALIZED;
    }
    if (!options || !options->prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    cancel_requested_.store(false);
    *out_result = {};

    auto start_time = std::chrono::steady_clock::now();

    // Set up progress callback if provided
    SdcppProgressContext progress_ctx = {};
    if (progress_callback) {
        progress_ctx.callback = progress_callback;
        progress_ctx.user_data = user_data;
        progress_ctx.total_steps = options->steps;
        progress_ctx.cancel_flag = &cancel_requested_;
        sd_set_progress_callback(sdcpp_step_callback, &progress_ctx);
    }

    int width = options->width > 0 ? options->width : 512;
    int height = options->height > 0 ? options->height : 512;
    int steps = options->steps > 0 ? options->steps : 28;
    float cfg_scale = options->guidance_scale > 0.0f ? options->guidance_scale : 7.5f;
    int64_t seed = options->seed >= 0 ? options->seed : -1;

    const char* negative_prompt = options->negative_prompt ? options->negative_prompt : "";

    SDCPP_LOGI("Generating image: %dx%d, steps=%d, cfg=%.1f, seed=%lld",
               width, height, steps, cfg_scale, static_cast<long long>(seed));

    // Initialize generation params
    sd_img_gen_params_t gen_params;
    sd_img_gen_params_init(&gen_params);

    gen_params.prompt = options->prompt;
    gen_params.negative_prompt = negative_prompt;
    gen_params.width = width;
    gen_params.height = height;
    gen_params.seed = seed;
    gen_params.batch_count = 1;
    gen_params.strength = options->denoise_strength > 0.0f ? options->denoise_strength : 0.75f;

    // Sample params
    gen_params.sample_params.sample_method = map_scheduler_to_sdcpp_method(options->scheduler);
    gen_params.sample_params.scheduler = map_scheduler_to_sdcpp_sched(options->scheduler);
    gen_params.sample_params.sample_steps = steps;

    // Note: CFG scale is not a direct field in newer sd.cpp API.
    // It's handled internally based on the model type.

    // Handle img2img
    if (options->mode == RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE && options->input_image_data) {
        sd_image_t input_image = {};
        input_image.width = static_cast<uint32_t>(options->input_image_width);
        input_image.height = static_cast<uint32_t>(options->input_image_height);
        input_image.data = const_cast<uint8_t*>(options->input_image_data);
        input_image.channel = 3;
        gen_params.init_image = input_image;
    }

    // Handle inpainting mask
    if (options->mode == RAC_DIFFUSION_MODE_INPAINTING && options->mask_data) {
        sd_image_t mask_image = {};
        mask_image.width = static_cast<uint32_t>(options->input_image_width);
        mask_image.height = static_cast<uint32_t>(options->input_image_height);
        mask_image.data = const_cast<uint8_t*>(options->mask_data);
        mask_image.channel = 1;
        gen_params.mask_image = mask_image;
    }

    // Generate
    sd_image_t* result_images = generate_image(ctx_, &gen_params);

    // Clear progress callback
    if (progress_callback) {
        sd_set_progress_callback(nullptr, nullptr);
    }

    if (cancel_requested_.load()) {
        if (result_images) {
            free(result_images->data);
            free(result_images);
        }
        out_result->error_code = RAC_ERROR_CANCELLED;
        return RAC_ERROR_CANCELLED;
    }

    if (!result_images || !result_images->data) {
        SDCPP_LOGE("sd.cpp generation returned null");
        out_result->error_code = RAC_ERROR_GENERATION_FAILED;
        out_result->error_message = strdup("sd.cpp generation failed");
        return RAC_ERROR_GENERATION_FAILED;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    // Convert RGB output to RGBA (our API requires RGBA)
    size_t rgba_size = 0;
    uint8_t* rgba_data = convert_rgb_to_rgba(result_images->data,
                                              static_cast<int>(result_images->width),
                                              static_cast<int>(result_images->height),
                                              &rgba_size);

    // Free sd.cpp output
    free(result_images->data);
    free(result_images);

    if (!rgba_data) {
        SDCPP_LOGE("Failed to convert RGB to RGBA");
        out_result->error_code = RAC_ERROR_GENERATION_FAILED;
        return RAC_ERROR_GENERATION_FAILED;
    }

    out_result->image_data = rgba_data;
    out_result->image_size = rgba_size;
    out_result->width = width;
    out_result->height = height;
    out_result->seed_used = seed;
    out_result->generation_time_ms = static_cast<int64_t>(duration_ms);
    out_result->safety_flagged = RAC_FALSE;
    out_result->error_code = RAC_SUCCESS;

    SDCPP_LOGI("Image generated in %lldms (%dx%d, %zu bytes RGBA)",
               static_cast<long long>(duration_ms), width, height, rgba_size);

    return RAC_SUCCESS;
}

// =============================================================================
// CANCELLATION
// =============================================================================

void SdcppDiffusionBackend::cancel() { cancel_requested_.store(true); }

// =============================================================================
// CLEANUP
// =============================================================================

void SdcppDiffusionBackend::cleanup() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (ctx_) {
        free_sd_ctx(ctx_);
        ctx_ = nullptr;
    }
    model_path_.clear();
    cancel_requested_.store(false);
}

// =============================================================================
// INFO
// =============================================================================

bool SdcppDiffusionBackend::is_ready() const { return ctx_ != nullptr; }

uint32_t SdcppDiffusionBackend::capabilities() const {
    uint32_t caps = RAC_DIFFUSION_CAP_TEXT_TO_IMAGE;
    if (ctx_) {
        caps |= RAC_DIFFUSION_CAP_IMAGE_TO_IMAGE;
        caps |= RAC_DIFFUSION_CAP_INPAINTING;
    }
    return caps;
}

// =============================================================================
// HELPERS
// =============================================================================

uint8_t* SdcppDiffusionBackend::convert_rgb_to_rgba(const uint8_t* rgb_data, int width,
                                                      int height, size_t* out_size) {
    if (!rgb_data || width <= 0 || height <= 0) return nullptr;

    size_t pixel_count = static_cast<size_t>(width) * static_cast<size_t>(height);
    size_t rgba_size = pixel_count * 4;
    auto* rgba = static_cast<uint8_t*>(malloc(rgba_size));
    if (!rgba) return nullptr;

    for (size_t i = 0; i < pixel_count; ++i) {
        rgba[i * 4 + 0] = rgb_data[i * 3 + 0];
        rgba[i * 4 + 1] = rgb_data[i * 3 + 1];
        rgba[i * 4 + 2] = rgb_data[i * 3 + 2];
        rgba[i * 4 + 3] = 255;
    }

    if (out_size) *out_size = rgba_size;
    return rgba;
}

}  // namespace runanywhere
