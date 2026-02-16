/**
 * @file diffusion_component.cpp
 * @brief Diffusion Capability Component Implementation
 *
 * Actor-based diffusion capability that owns model lifecycle and generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 *
 * Supports text-to-image, image-to-image, and inpainting.
 */

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/diffusion/rac_diffusion_component.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/diffusion/rac_diffusion_tokenizer.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

/**
 * Internal diffusion component state.
 */
struct rac_diffusion_component {
    /** Lifecycle manager handle */
    rac_handle_t lifecycle;

    /** Current configuration */
    rac_diffusion_config_t config;

    /** Storage for optional string fields in config */
    std::string model_id_storage;
    std::string tokenizer_custom_url_storage;

    /** Default generation options based on config */
    rac_diffusion_options_t default_options;

    /** Mutex for thread safety */
    std::mutex mtx;

    /** Cancellation flag (atomic for thread-safe access from cancel() while generate holds mutex) */
    std::atomic<bool> cancel_requested;

    rac_diffusion_component() : lifecycle(nullptr), cancel_requested(false) {
        // Initialize with defaults
        config = RAC_DIFFUSION_CONFIG_DEFAULT;
        default_options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * Merge user-provided options over component defaults.
 *
 * For numeric fields, zero/negative values mean "use default" (except guidance_scale
 * where 0.0 is valid for CFG-free models like SDXS/SDXL Turbo - use negative to skip).
 * Pointer fields are copied if non-null. Enums are always copied.
 */
static rac_diffusion_options_t merge_diffusion_options(
    const rac_diffusion_options_t& defaults, const rac_diffusion_options_t* options) {
    rac_diffusion_options_t effective = defaults;

    effective.prompt = options->prompt;
    if (options->negative_prompt) {
        effective.negative_prompt = options->negative_prompt;
    }
    if (options->width > 0) {
        effective.width = options->width;
    }
    if (options->height > 0) {
        effective.height = options->height;
    }
    if (options->steps > 0) {
        effective.steps = options->steps;
    }
    // guidance_scale >= 0 allows 0.0 (valid for CFG-free models like SDXS, SDXL Turbo)
    // Only skip override if user passes a negative sentinel (which is never valid)
    if (options->guidance_scale >= 0.0f) {
        effective.guidance_scale = options->guidance_scale;
    }
    if (options->seed != 0) {
        effective.seed = options->seed;
    }
    effective.scheduler = options->scheduler;
    effective.mode = options->mode;

    // Image-to-image / inpainting fields
    effective.input_image_data = options->input_image_data;
    effective.input_image_size = options->input_image_size;
    effective.input_image_width = options->input_image_width;
    effective.input_image_height = options->input_image_height;
    effective.mask_data = options->mask_data;
    effective.mask_size = options->mask_size;
    effective.denoise_strength = options->denoise_strength;

    // Progress reporting fields
    effective.report_intermediate_images = options->report_intermediate_images;
    effective.progress_stride = options->progress_stride > 0 ? options->progress_stride : 1;

    return effective;
}

/**
 * Generate a unique ID for generation tracking.
 */
static std::string generate_unique_id() {
    auto now = std::chrono::high_resolution_clock::now();
    auto epoch = now.time_since_epoch();
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(epoch).count();
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "diffusion_%lld", static_cast<long long>(ns));
    return std::string(buffer);
}

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

/**
 * Service creation callback for lifecycle manager.
 * Creates and initializes the diffusion service.
 */
static rac_result_t diffusion_create_service(const char* model_id, void* user_data,
                                             rac_handle_t* out_service) {
    auto* component = reinterpret_cast<rac_diffusion_component*>(user_data);

    RAC_LOG_INFO("Diffusion.Component", "Creating diffusion service for model: %s",
                 model_id ? model_id : "");

    // Tokenizer files are only needed for CoreML models (Apple's ml-stable-diffusion).
    // sd.cpp bundles its own tokenizer, so skip this check for SDCPP framework.
    if (component && model_id) {
        auto fw = static_cast<rac_inference_framework_t>(component->config.preferred_framework);
        if (fw != RAC_FRAMEWORK_SDCPP) {
            rac_result_t ensure_result =
                rac_diffusion_tokenizer_ensure_files(model_id, &component->config.tokenizer);
            if (ensure_result != RAC_SUCCESS) {
                RAC_LOG_ERROR("Diffusion.Component",
                              "Failed to ensure tokenizer files for %s: %d",
                              model_id, ensure_result);
                return ensure_result;
            }
        } else {
            RAC_LOG_DEBUG("Diffusion.Component",
                          "Skipping tokenizer check for sd.cpp framework (built-in tokenizer)");
        }
    }

    // Create diffusion service
    rac_result_t result =
        rac_diffusion_create_with_config(model_id, component ? &component->config : nullptr,
                                         out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "Failed to create diffusion service: %d", result);
        return result;
    }

    // Initialize with model path and config
    result = rac_diffusion_initialize(*out_service, model_id,
                                      component ? &component->config : nullptr);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "Failed to initialize diffusion service: %d", result);
        rac_diffusion_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    RAC_LOG_INFO("Diffusion.Component", "Diffusion service created successfully");
    return RAC_SUCCESS;
}

/**
 * Service destruction callback for lifecycle manager.
 * Cleans up the diffusion service.
 */
static void diffusion_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        RAC_LOG_DEBUG("Diffusion.Component", "Destroying diffusion service");
        rac_diffusion_cleanup(service);
        rac_diffusion_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_diffusion_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_diffusion_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create lifecycle manager
    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_DIFFUSION_MODEL;
    lifecycle_config.logger_category = "Diffusion.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, diffusion_create_service,
                                               diffusion_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    RAC_LOG_INFO("Diffusion.Component", "Diffusion component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_diffusion_component_configure(rac_handle_t handle,
                                                          const rac_diffusion_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Copy configuration (shallow) then normalize owned string fields
    component->config = *config;

    if (config->model_id) {
        component->model_id_storage = config->model_id;
        component->config.model_id = component->model_id_storage.c_str();
    } else {
        component->model_id_storage.clear();
        component->config.model_id = nullptr;
    }

    if (config->tokenizer.custom_base_url) {
        component->tokenizer_custom_url_storage = config->tokenizer.custom_base_url;
        component->config.tokenizer.custom_base_url =
            component->tokenizer_custom_url_storage.c_str();
    } else {
        component->tokenizer_custom_url_storage.clear();
        component->config.tokenizer.custom_base_url = nullptr;
    }

    // Update default options based on model variant
    switch (config->model_variant) {
        case RAC_DIFFUSION_MODEL_SDXL:
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            component->default_options.width = 1024;
            component->default_options.height = 1024;
            break;
        case RAC_DIFFUSION_MODEL_SD_2_1:
            component->default_options.width = 768;
            component->default_options.height = 768;
            break;
        case RAC_DIFFUSION_MODEL_SDXS:
        case RAC_DIFFUSION_MODEL_LCM:
        case RAC_DIFFUSION_MODEL_SD_1_5:
        default:
            component->default_options.width = 512;
            component->default_options.height = 512;
            break;
    }

    // Ultra-fast models: SDXS (1 step), SDXL Turbo (4 steps), LCM (4 steps)
    switch (config->model_variant) {
        case RAC_DIFFUSION_MODEL_SDXS:
            // SDXS: 1 step, no CFG
            component->default_options.steps = 1;
            component->default_options.guidance_scale = 0.0f;
            component->default_options.scheduler = RAC_DIFFUSION_SCHEDULER_EULER;
            break;
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            // SDXL Turbo: 4 steps, no CFG
            component->default_options.steps = 4;
            component->default_options.guidance_scale = 0.0f;
            break;
        case RAC_DIFFUSION_MODEL_LCM:
            // LCM: 4 steps, lower CFG
            component->default_options.steps = 4;
            component->default_options.guidance_scale = 1.5f;
            component->default_options.scheduler = RAC_DIFFUSION_SCHEDULER_EULER;
            break;
        default:
            // Standard models keep default values
            break;
    }

    RAC_LOG_INFO("Diffusion.Component", "Diffusion component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_diffusion_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_diffusion_component_get_model_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_diffusion_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);

    // Destroy lifecycle manager (will cleanup service if loaded)
    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    RAC_LOG_INFO("Diffusion.Component", "Diffusion component destroyed");

    delete component;
}

// =============================================================================
// MODEL LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_diffusion_component_load_model(rac_handle_t handle,
                                                           const char* model_path,
                                                           const char* model_id,
                                                           const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Delegate to lifecycle manager
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

extern "C" rac_result_t rac_diffusion_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_diffusion_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_reset(component->lifecycle);
}

// =============================================================================
// GENERATION API
// =============================================================================

extern "C" rac_result_t rac_diffusion_component_generate(rac_handle_t handle,
                                                         const rac_diffusion_options_t* options,
                                                         rac_diffusion_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!options || !options->prompt)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Reset cancellation flag
    component->cancel_requested = false;

    // Generate unique ID for this generation
    std::string generation_id = generate_unique_id();

    // Get model ID and name from lifecycle manager
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "No model loaded - cannot generate");
        return result;
    }

    // Merge user options over component defaults
    rac_diffusion_options_t effective_options = merge_diffusion_options(
        component->default_options, options);

    RAC_LOG_INFO("Diffusion.Component",
                 "Starting generation: %dx%d, %d steps, guidance=%.1f, scheduler=%d",
                 effective_options.width, effective_options.height, effective_options.steps,
                 effective_options.guidance_scale, effective_options.scheduler);

    auto start_time = std::chrono::steady_clock::now();

    // Perform generation
    result = rac_diffusion_generate(service, &effective_options, out_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "Generation failed: %d", result);
        rac_lifecycle_track_error(component->lifecycle, result, "generate");
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    out_result->generation_time_ms = duration.count();

    RAC_LOG_INFO("Diffusion.Component", "Generation completed in %lld ms, seed=%lld",
                 static_cast<long long>(out_result->generation_time_ms),
                 static_cast<long long>(out_result->seed_used));

    return RAC_SUCCESS;
}

/**
 * Internal structure for progress callback context.
 */
struct diffusion_callback_context {
    rac_diffusion_component* component;
    rac_diffusion_progress_callback_fn progress_callback;
    rac_diffusion_complete_callback_fn complete_callback;
    rac_diffusion_error_callback_fn error_callback;
    void* user_data;

    std::chrono::steady_clock::time_point start_time;
    std::string generation_id;
};

/**
 * Internal progress callback that wraps user callback and checks cancellation.
 */
static rac_bool_t diffusion_progress_wrapper(const rac_diffusion_progress_t* progress,
                                             void* user_data) {
    auto* ctx = reinterpret_cast<diffusion_callback_context*>(user_data);

    // Check cancellation
    if (ctx->component->cancel_requested) {
        RAC_LOG_INFO("Diffusion.Component", "Generation cancelled by user");
        return RAC_FALSE;  // Signal to stop
    }

    // Call user callback
    if (ctx->progress_callback) {
        return ctx->progress_callback(progress, ctx->user_data);
    }

    return RAC_TRUE;  // Continue by default
}

extern "C" rac_result_t rac_diffusion_component_generate_with_callbacks(
    rac_handle_t handle, const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback,
    rac_diffusion_complete_callback_fn complete_callback,
    rac_diffusion_error_callback_fn error_callback, void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!options || !options->prompt)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Reset cancellation flag
    component->cancel_requested = false;

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "No model loaded - cannot generate");
        if (error_callback) {
            error_callback(result, "No model loaded", user_data);
        }
        return result;
    }

    // Merge user options over component defaults
    rac_diffusion_options_t effective_options = merge_diffusion_options(
        component->default_options, options);

    RAC_LOG_INFO("Diffusion.Component",
                 "Starting generation with callbacks: %dx%d, %d steps, stride=%d",
                 effective_options.width, effective_options.height, effective_options.steps,
                 effective_options.progress_stride);

    // Setup callback context
    diffusion_callback_context ctx;
    ctx.component = component;
    ctx.progress_callback = progress_callback;
    ctx.complete_callback = complete_callback;
    ctx.error_callback = error_callback;
    ctx.user_data = user_data;
    ctx.start_time = std::chrono::steady_clock::now();
    ctx.generation_id = generate_unique_id();

    // Perform generation with progress
    rac_diffusion_result_t gen_result = {};
    result = rac_diffusion_generate_with_progress(service, &effective_options,
                                                  diffusion_progress_wrapper, &ctx, &gen_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "Generation failed: %d", result);
        rac_lifecycle_track_error(component->lifecycle, result, "generateWithCallbacks");
        if (error_callback) {
            error_callback(result, gen_result.error_message ? gen_result.error_message
                                                           : "Generation failed",
                           user_data);
        }
        rac_diffusion_result_free(&gen_result);
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - ctx.start_time);
    gen_result.generation_time_ms = duration.count();

    RAC_LOG_INFO("Diffusion.Component", "Generation completed in %lld ms",
                 static_cast<long long>(gen_result.generation_time_ms));

    // Call completion callback
    if (complete_callback) {
        complete_callback(&gen_result, user_data);
    }

    // Free result (user should have copied what they need in callback)
    rac_diffusion_result_free(&gen_result);

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_diffusion_component_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);

    // Set cancellation flag (checked by progress callback)
    component->cancel_requested = true;

    // Also try to cancel via service
    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (service) {
        rac_diffusion_cancel(service);
    }

    RAC_LOG_INFO("Diffusion.Component", "Generation cancellation requested");

    return RAC_SUCCESS;
}

// =============================================================================
// CAPABILITY QUERY API
// =============================================================================

extern "C" uint32_t rac_diffusion_component_get_capabilities(rac_handle_t handle) {
    if (!handle)
        return 0;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        // Return default capabilities based on config
        uint32_t caps = RAC_DIFFUSION_CAP_TEXT_TO_IMAGE | RAC_DIFFUSION_CAP_INTERMEDIATE_IMAGES;
        if (component->config.enable_safety_checker) {
            caps |= RAC_DIFFUSION_CAP_SAFETY_CHECKER;
        }
        return caps;
    }

    return rac_diffusion_get_capabilities(service);
}

extern "C" rac_result_t rac_diffusion_component_get_info(rac_handle_t handle,
                                                         rac_diffusion_info_t* out_info) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_info)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        // Return info based on config
        out_info->is_ready = RAC_FALSE;
        out_info->current_model = nullptr;
        out_info->model_variant = component->config.model_variant;
        out_info->supports_text_to_image = RAC_TRUE;
        out_info->supports_image_to_image = RAC_TRUE;
        out_info->supports_inpainting = RAC_TRUE;
        out_info->safety_checker_enabled = component->config.enable_safety_checker;

        // Set max dimensions based on variant
        switch (component->config.model_variant) {
            case RAC_DIFFUSION_MODEL_SDXL:
            case RAC_DIFFUSION_MODEL_SDXL_TURBO:
                out_info->max_width = 1024;
                out_info->max_height = 1024;
                break;
            case RAC_DIFFUSION_MODEL_SD_2_1:
                out_info->max_width = 768;
                out_info->max_height = 768;
                break;
            case RAC_DIFFUSION_MODEL_SDXS:
            case RAC_DIFFUSION_MODEL_LCM:
            case RAC_DIFFUSION_MODEL_SD_1_5:
            default:
                out_info->max_width = 512;
                out_info->max_height = 512;
                break;
        }
        return RAC_SUCCESS;
    }

    return rac_diffusion_get_info(service, out_info);
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_diffusion_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_diffusion_component_get_metrics(rac_handle_t handle,
                                                            rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}
