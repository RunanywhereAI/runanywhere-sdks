/**
 * @file diffusion_module.cpp
 * @brief Unified Diffusion feature module.
 *
 * One TU owns the handle-based component path, the handle-based
 * rac_diffusion_generate_proto / _with_progress / cancel ABI, and the
 * handle-less rac_diffusion_generate_lifecycle_proto verb.
 *
 * Supports text-to-image, image-to-image, and inpainting.
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <random>
#include <string>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_component.h"
#include "rac/features/diffusion/rac_diffusion_proto_adapters.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/diffusion/rac_diffusion_stream.h"
#include "rac/features/diffusion/rac_diffusion_tokenizer.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#include "sdk_events.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

// INTERNAL STRUCTURES

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

    /** Cancellation flag (atomic for thread-safe access from cancel() while generate holds mutex)
     */
    std::atomic<bool> cancel_requested;

    rac_diffusion_component() : lifecycle(nullptr), cancel_requested(false) {
        // Initialize with defaults
        config = RAC_DIFFUSION_CONFIG_DEFAULT;
        default_options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    }
};

// HELPER FUNCTIONS

/**
 * Merge user-provided options over component defaults.
 *
 * For numeric fields, zero/negative values mean "use default" (except guidance_scale
 * where 0.0 is valid for CFG-free models like SDXS/SDXL Turbo - use negative to skip).
 * Pointer fields are copied if non-null. Enums are always copied.
 */
static rac_diffusion_options_t merge_diffusion_options(const rac_diffusion_options_t& defaults,
                                                       const rac_diffusion_options_t* options) {
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
    static thread_local std::mt19937 gen(std::random_device{}());
    std::uniform_int_distribution<uint32_t> dis;
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "diff_%08x%08x", dis(gen), dis(gen));
    return {buffer};
}

// LIFECYCLE CALLBACKS

/**
 * Service creation callback for lifecycle manager.
 * Creates and initializes the diffusion service.
 */
static rac_result_t diffusion_create_service(const char* model_id, void* user_data,
                                             rac_handle_t* out_service) {
    auto* component = reinterpret_cast<rac_diffusion_component*>(user_data);

    RAC_LOG_INFO("Diffusion.Component", "Creating diffusion service for model: %s",
                 model_id ? model_id : "");

    if (component && model_id) {
        rac_result_t ensure_result =
            rac_diffusion_tokenizer_ensure_files(model_id, &component->config.tokenizer);
        if (ensure_result != RAC_SUCCESS) {
            RAC_LOG_ERROR("Diffusion.Component", "Failed to ensure tokenizer files for %s: %d",
                          model_id, ensure_result);
            return ensure_result;
        }
    }

    // Create diffusion service
    rac_result_t result = rac_diffusion_create_with_config(
        model_id, component ? &component->config : nullptr, out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "Failed to create diffusion service: %d", result);
        return result;
    }

    // Initialize with model path and config
    result =
        rac_diffusion_initialize(*out_service, model_id, component ? &component->config : nullptr);
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

// LIFECYCLE API

extern "C" rac_result_t rac_diffusion_component_create(rac_handle_t* out_handle) {
    return rac::features::create_lifecycle_component<rac_diffusion_component>(
        out_handle, RAC_RESOURCE_TYPE_DIFFUSION_MODEL, "Diffusion.Lifecycle",
        diffusion_create_service, diffusion_destroy_service, "Diffusion.Component",
        "Diffusion component created");
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

    // B-FL-5-001 sibling fix: clear any lingering proto-stream callback
    // registration keyed by this component handle BEFORE freeing the memory.
    // Even though rac_diffusion_stream_start_proto is currently NOT_IMPLEMENTED,
    // the slot registry is live and reachable via the public ABI — clearing
    // here prevents stale wire-seq / stale user_data when the handle heap
    // address is reused by a fresh component.
    rac_diffusion_unset_stream_proto_callback(handle);
    // spin-wait for any in-flight
    // dispatch_diffusion_stream_event() invocation on another thread before
    // freeing the component. Mirrors rac_vlm_component_destroy / rac_llm_component_destroy.
    rac_diffusion_proto_quiesce();

    RAC_LOG_INFO("Diffusion.Component", "Diffusion component destroyed");

    delete component;
}

// MODEL LIFECYCLE

extern "C" rac_result_t rac_diffusion_component_load_model(rac_handle_t handle,
                                                           const char* model_path,
                                                           const char* model_id,
                                                           const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // B-FL-5-001 sibling v2 fix: clear any prior proto-stream callback
    // registration BEFORE loading a new model. The load_model path elides
    // destroy → original destroy-time fix never fires for handle reuse, so
    // the wire-seq counter in g_slots() would retain its prior value.
    rac_diffusion_unset_stream_proto_callback(handle);
    // drain any in-flight dispatcher bound
    // to the previous model before swapping in the new one so user_data
    // captured by the previous registration can be safely freed.
    rac_diffusion_proto_quiesce();

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

// GENERATION API

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

    // Acquire lock only for state reads; release before long-running generation
    rac_handle_t service = nullptr;
    rac_diffusion_options_t effective_options;
    {
        std::lock_guard<std::mutex> lock(component->mtx);

        // Reset cancellation flag (also atomic, but set under lock for consistency)
        component->cancel_requested = false;

        // Pin service via acquire to prevent unload during generation
        rac_result_t result = rac_lifecycle_acquire_service(component->lifecycle, &service);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("Diffusion.Component", "No model loaded - cannot generate");
            return result;
        }

        // Merge user options over component defaults
        effective_options = merge_diffusion_options(component->default_options, options);
    }
    // Lock released — safe to do long-running generation

    RAC_LOG_INFO("Diffusion.Component",
                 "Starting generation: %dx%d, %d steps, guidance=%.1f, scheduler=%d",
                 effective_options.width, effective_options.height, effective_options.steps,
                 effective_options.guidance_scale, effective_options.scheduler);

    auto start_time = std::chrono::steady_clock::now();

    // Perform generation outside lock
    rac_result_t result = rac_diffusion_generate(service, &effective_options, out_result);

    // Release pinned service in all exit paths
    rac_lifecycle_release_service(component->lifecycle);

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

    // Acquire lock only for state reads; release before long-running generation
    rac_handle_t service = nullptr;
    rac_diffusion_options_t effective_options;
    {
        std::lock_guard<std::mutex> lock(component->mtx);

        // Reset cancellation flag
        component->cancel_requested = false;

        // Pin service via acquire to prevent unload during generation
        rac_result_t result = rac_lifecycle_acquire_service(component->lifecycle, &service);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("Diffusion.Component", "No model loaded - cannot generate");
            if (error_callback) {
                error_callback(result, "No model loaded", user_data);
            }
            return result;
        }

        // Merge user options over component defaults
        effective_options = merge_diffusion_options(component->default_options, options);
    }
    // Lock released — safe to do long-running generation

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

    // Perform generation with progress (outside lock)
    rac_diffusion_result_t gen_result = {};
    rac_result_t result = rac_diffusion_generate_with_progress(
        service, &effective_options, diffusion_progress_wrapper, &ctx, &gen_result);

    // Release pinned service in all exit paths
    rac_lifecycle_release_service(component->lifecycle);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Component", "Generation failed: %d", result);
        rac_lifecycle_track_error(component->lifecycle, result, "generateWithCallbacks");
        if (error_callback) {
            error_callback(
                result, gen_result.error_message ? gen_result.error_message : "Generation failed",
                user_data);
        }
        rac_diffusion_result_free(&gen_result);
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - ctx.start_time);
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

// CAPABILITY QUERY API

extern "C" uint32_t rac_diffusion_component_get_capabilities(rac_handle_t handle) {
    if (!handle)
        return 0;

    auto* component = reinterpret_cast<rac_diffusion_component*>(handle);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        // Return default capabilities based on config
        uint32_t caps = RAC_DIFFUSION_CAP_TEXT_TO_IMAGE | RAC_DIFFUSION_CAP_INTERMEDIATE_IMAGES;
        if (component->config.enable_safety_checker == RAC_TRUE) {
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

// STATE QUERY API

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

// PROTO-BYTE C ABI + LIFECYCLE-OWNED GENERATED-PROTO C ABI
//
// rac_diffusion_generate_proto / _with_progress / cancel are handle-based;
// rac_diffusion_generate_lifecycle_proto resolves the loaded model via the
// global registry (rac::lifecycle::acquire_lifecycle_diffusion).

namespace {

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return buffer;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    return rac::proto::parse_bytes(bytes, size);
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return rac::proto::bytes_valid(bytes, size);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

// Carried from rac_nonllm_lifecycle_proto_abi.cpp — needed by the lifecycle
// generate verb below. Internal linkage; no ODR clash.
rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac::proto::parse_error(out, message);
}

rac_result_t check_model_id(const std::string& requested, const char* loaded, const char* message,
                            rac_proto_buffer_t* out) {
    if (!requested.empty() && loaded && requested != loaded) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_INVALID_ARGUMENT, message);
    }
    return RAC_SUCCESS;
}

void free_diffusion_options(rac_diffusion_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

bool serialize_proto(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    // Route through the destination router (sdk_event_publish) so the envelope's
    // TELEMETRY destination bit reaches the telemetry manager. A direct
    // rac_sdk_event_publish_proto call feeds only the PUBLIC stream, so these
    // capability events would never be recorded as telemetry.
    (void)rac::events::publish_prebuilt(event);
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        float progress, const char* error, double duration_ms = 0.0,
                        const char* model_id = nullptr, int32_t prompt_length = 0,
                        int32_t negative_prompt_length = 0, int32_t image_width = 0,
                        int32_t image_height = 0, int32_t num_inference_steps = 0,
                        double guidance_scale = 0.0, int64_t seed = 0,
                        int64_t output_size_bytes = 0) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_DIFFUSION);
    event.set_severity(error && error[0] != '\0' ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                                 : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    if (model_id != nullptr && model_id[0] != '\0') {
        cap->set_model_id(model_id);
    }
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    if (error)
        cap->set_error(error);
    // CapabilityOperationEvent has no duration field; telemetry reads it from
    // the envelope properties map (see telemetry_manager kCapability extraction).
    if (duration_ms > 0.0) {
        (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    }
    // ImageGen detail fields ride the properties carrier (extracted in the
    // telemetry kCapability SDK_COMPONENT_DIFFUSION branch). Gated on >0 so the
    // started/failed emits (which pass defaults) don't carry them.
    if (prompt_length > 0)
        (*event.mutable_properties())["prompt_length"] = std::to_string(prompt_length);
    if (negative_prompt_length > 0)
        (*event.mutable_properties())["negative_prompt_length"] =
            std::to_string(negative_prompt_length);
    if (image_width > 0)
        (*event.mutable_properties())["image_width"] = std::to_string(image_width);
    if (image_height > 0)
        (*event.mutable_properties())["image_height"] = std::to_string(image_height);
    if (num_inference_steps > 0)
        (*event.mutable_properties())["num_inference_steps"] = std::to_string(num_inference_steps);
    if (guidance_scale > 0.0)
        (*event.mutable_properties())["guidance_scale"] = std::to_string(guidance_scale);
    if (output_size_bytes > 0) {
        (*event.mutable_properties())["output_size_bytes"] = std::to_string(output_size_bytes);
        // seed is meaningful (incl. 0) but only emit it on a real completed
        // generation — keyed off output_size_bytes being present.
        (*event.mutable_properties())["seed"] = std::to_string(seed);
    }
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED, operation,
                       0.0f, message && message[0] != '\0' ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "diffusion", operation, RAC_TRUE);
}

void free_options(rac_diffusion_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

rac_result_t parse_options(const uint8_t* bytes, size_t size, rac_diffusion_options_t* out_options,
                           rac_proto_buffer_t* out_error) {
    if (!valid_bytes(bytes, size)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "Diffusion options bytes are invalid");
    }
    runanywhere::v1::DiffusionGenerationOptions proto;
    if (!proto.ParseFromArray(parse_data(bytes, size), static_cast<int>(size))) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse DiffusionGenerationOptions");
    }
    if (!rac::foundation::rac_diffusion_options_from_proto(proto, out_options)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert DiffusionGenerationOptions");
    }
    if (!out_options->prompt || out_options->prompt[0] == '\0') {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationOptions.prompt is required");
    }
    return RAC_SUCCESS;
}

struct ProgressCtx {
    rac_diffusion_progress_proto_callback_fn callback{nullptr};
    void* user_data{nullptr};
};

rac_bool_t progress_trampoline(const rac_diffusion_progress_t* progress, void* user_data) {
    auto* ctx = static_cast<ProgressCtx*>(user_data);
    if (!progress)
        return RAC_TRUE;

    runanywhere::v1::DiffusionProgress proto;
    if (!rac::foundation::rac_diffusion_progress_to_proto(progress, &proto)) {
        return RAC_FALSE;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS,
                       "diffusion.generate", progress->progress, nullptr);

    if (!ctx || !ctx->callback)
        return RAC_TRUE;
    std::vector<uint8_t> bytes;
    if (!serialize_proto(proto, &bytes))
        return RAC_FALSE;
    return ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data) ==
                   RAC_TRUE
               ? RAC_TRUE
               : RAC_FALSE;
}

#endif  // RAC_HAVE_PROTOBUF

#if !defined(RAC_HAVE_PROTOBUF)
rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    if (out) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                          "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}
#endif

}  // namespace

extern "C" {

rac_result_t rac_diffusion_generate_proto(rac_handle_t handle, const uint8_t* options_proto_bytes,
                                          size_t options_proto_size,
                                          rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "diffusion.generate",
                        "Diffusion lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "Diffusion lifecycle component is not loaded");
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    rac_result_t rc = parse_options(options_proto_bytes, options_proto_size, &options, out_result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", out_result->error_message);
        free_options(&options);
        return rc;
    }

    const char* model_id = rac_diffusion_component_get_model_id(handle);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
                       "diffusion.generate", 0.0f, nullptr, 0.0, model_id);
    rac_diffusion_result_t result = {};
    rc = rac_diffusion_generate(handle, &options, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
        free_options(&options);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult proto;
    if (!rac::foundation::rac_diffusion_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode DiffusionResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    if (rc == RAC_SUCCESS) {
        publish_capability(
            runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
            "diffusion.generate", 1.0f, nullptr, static_cast<double>(result.generation_time_ms),
            model_id, options.prompt ? static_cast<int32_t>(strlen(options.prompt)) : 0,
            options.negative_prompt ? static_cast<int32_t>(strlen(options.negative_prompt)) : 0,
            result.width, result.height, options.steps,
            static_cast<double>(options.guidance_scale), result.seed_used,
            static_cast<int64_t>(result.image_size));
    } else {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
    }
    rac_diffusion_result_free(&result);
    free_options(&options);
    return rc;
#endif
}

rac_result_t rac_diffusion_generate_with_progress_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_diffusion_progress_proto_callback_fn progress_callback, void* user_data,
    rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)options_proto_bytes;
    (void)options_proto_size;
    (void)progress_callback;
    (void)user_data;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "diffusion.generate",
                        "Diffusion lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "Diffusion lifecycle component is not loaded");
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    rac_result_t rc = parse_options(options_proto_bytes, options_proto_size, &options, out_result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", out_result->error_message);
        free_options(&options);
        return rc;
    }

    const char* model_id = rac_diffusion_component_get_model_id(handle);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
                       "diffusion.generate", 0.0f, nullptr, 0.0, model_id);
    ProgressCtx ctx;
    ctx.callback = progress_callback;
    ctx.user_data = user_data;
    rac_diffusion_result_t result = {};
    rc = rac_diffusion_generate_with_progress(handle, &options, progress_trampoline, &ctx, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
        free_options(&options);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult proto;
    if (!rac::foundation::rac_diffusion_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode DiffusionResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    if (rc == RAC_SUCCESS) {
        publish_capability(
            runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
            "diffusion.generate", 1.0f, nullptr, static_cast<double>(result.generation_time_ms),
            model_id, options.prompt ? static_cast<int32_t>(strlen(options.prompt)) : 0,
            options.negative_prompt ? static_cast<int32_t>(strlen(options.negative_prompt)) : 0,
            result.width, result.height, options.steps,
            static_cast<double>(options.guidance_scale), result.seed_used,
            static_cast<int64_t>(result.image_size));
    } else {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
    }
    rac_diffusion_result_free(&result);
    free_options(&options);
    return rc;
#endif
}

rac_result_t rac_diffusion_cancel_proto(rac_handle_t handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "diffusion.cancel",
                        "Diffusion lifecycle component is not loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    runanywhere::v1::SDKEvent requested;
    requested.set_id(event_id());
    requested.set_timestamp_ms(now_ms());
    requested.set_category(runanywhere::v1::EVENT_CATEGORY_CANCELLATION);
    requested.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    requested.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    requested.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    requested.set_source("cpp");
    requested.set_operation_id("diffusion.cancel");
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    cancel->set_operation_id("diffusion.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    rac_result_t rc = rac_diffusion_cancel(handle);
    runanywhere::v1::SDKEvent completed;
    completed.set_id(event_id());
    completed.set_timestamp_ms(now_ms());
    completed.set_category(runanywhere::v1::EVENT_CATEGORY_CANCELLATION);
    completed.set_severity(rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                             : runanywhere::v1::ERROR_SEVERITY_ERROR);
    completed.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    completed.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    completed.set_source("cpp");
    completed.set_operation_id("diffusion.cancel");
    auto* done = completed.mutable_cancellation();
    done->set_kind(rc == RAC_SUCCESS ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                     : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    done->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    done->set_operation_id("diffusion.cancel");
    done->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    done->set_user_initiated(true);
    publish_event(completed);
    return rc;
#endif
}

rac_result_t rac_diffusion_generate_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                    size_t request_proto_size,
                                                    rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "DiffusionGenerationRequest bytes are invalid");
    }
    runanywhere::v1::DiffusionGenerationRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse DiffusionGenerationRequest");
    }
    if (!request.has_options()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationRequest.options is required");
    }

    rac::lifecycle::LifecycleDiffusionRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_diffusion(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "Diffusion lifecycle model is not loaded");
    }
    rc = check_model_id(
        request.model_id(), ref.model_id,
        "DiffusionGenerationRequest.model_id does not match the lifecycle-loaded model",
        out_result);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rc;
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    if (!rac::foundation::rac_diffusion_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert DiffusionGenerationOptions");
    }
    if (!options.prompt || options.prompt[0] == '\0') {
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationOptions.prompt is required");
    }

    rac_diffusion_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_diffusion_result_t raw = {};
    rc = rac_diffusion_generate(&service, &options, &raw);
    if (rc != RAC_SUCCESS) {
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult result;
    if (!rac::foundation::rac_diffusion_result_to_proto(&raw, &result)) {
        rac_diffusion_result_free(&raw);
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode DiffusionResult");
    }
    rc = copy_proto(result, out_result);
    rac_diffusion_result_free(&raw);
    free_diffusion_options(&options);
    rac::lifecycle::release_lifecycle_diffusion(&ref);
    return rc;
#endif
}

}  // extern "C"
