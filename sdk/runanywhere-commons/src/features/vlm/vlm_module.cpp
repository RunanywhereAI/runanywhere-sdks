/**
 * @file vlm_module.cpp
 * @brief Unified VLM feature module.
 *
 * W4 component unification: merges the former vlm_component.cpp (handle-based
 * Vision Language Model component path) with the entire rac_vlm_proto_abi.cpp
 * (proto-byte C ABI: rac_vlm_process_proto / _stream / cancel / generate /
 * stream / cancel_lifecycle, plus the rac_vlm_proto_quiesce in-flight guard)
 * into one TU.
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "core/internal/platform_compat.h"
#include "features/common/rac_component_lifecycle_internal.h"
#include "features/vlm/rac_vlm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/vlm/rac_vlm_proto_adapters.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "vlm_options.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

static const char* LOG_CAT = "VLM.Component";

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

/**
 * Internal VLM component state.
 */
struct rac_vlm_component {
    /** Lifecycle manager handle */
    rac_handle_t lifecycle;

    /** Current configuration */
    rac_vlm_config_t config;

    /** Default generation options based on config */
    rac_vlm_options_t default_options;

    /** Path to vision projector (for llama.cpp backend) */
    std::string mmproj_path;

    /** Mutex for thread safety */
    std::mutex mtx;

    rac_vlm_component() : lifecycle(nullptr) {
        config = RAC_VLM_CONFIG_DEFAULT;

        // Initialize default options
        default_options.max_tokens = 2048;
        default_options.temperature = 0.7f;
        default_options.top_p = 0.9f;
        default_options.stop_sequences = nullptr;
        default_options.num_stop_sequences = 0;
        default_options.streaming_enabled = RAC_TRUE;
        default_options.system_prompt = nullptr;
        default_options.max_image_size = 0;
        default_options.n_threads = 0;
        default_options.use_gpu = RAC_TRUE;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * Simple token estimation (~4 chars per token).
 */
static int32_t estimate_tokens(const char* text) {
    if (!text)
        return 1;
    const size_t len = strlen(text);
    const int32_t tokens = static_cast<int32_t>((len + 3) / 4);
    return tokens > 0 ? tokens : 1;
}

// =============================================================================
// SPECIAL TOKEN STRIPPING
// =============================================================================

/**
 * Strip model-internal special tokens (e.g. <|im_end|>) from a token string.
 *
 * Scans for patterns matching <|...|> and removes them. The cleaned result is
 * written to buf. Returns a pointer to buf (which may be an empty string if the
 * entire token was a special token).
 */
static const char* vlm_strip_special_tokens(const char* token, char* buf, size_t buf_size) {
    if (!token || !buf || buf_size == 0) {
        if (buf && buf_size > 0)
            buf[0] = '\0';
        return buf;
    }

    size_t out = 0;
    size_t i = 0;

    // Use null-terminator checks instead of strlen() to avoid the upfront O(n) scan.
    // Tokens are typically short (1-4 chars), but this avoids redundant work.
    while (token[i] != '\0' && out < buf_size - 1) {
        if (token[i] == '<' && token[i + 1] == '|') {
            // Scan ahead for closing |>
            size_t end = i + 2;
            while (token[end] != '\0') {
                if (token[end] == '|' && token[end + 1] == '>') {
                    // Found <|...|> — skip the entire special token
                    i = end + 2;
                    break;
                }
                end++;
            }
            if (token[end] == '\0') {
                // No closing |> found — copy the '<' literally
                buf[out++] = token[i++];
            }
        } else {
            buf[out++] = token[i++];
        }
    }

    buf[out] = '\0';
    return buf;
}

// =============================================================================
// MODEL FILE RESOLUTION
// =============================================================================

/**
 * Resolve VLM model files within a directory.
 *
 * Scans the given directory for .gguf files and separates them into:
 * - Main model file: first .gguf NOT containing "mmproj" in its name
 * - Vision projector file: first .gguf containing "mmproj" in its name
 *
 * Uses POSIX opendir/readdir (works on iOS, Android, macOS, Linux).
 */
extern "C" rac_result_t rac_vlm_resolve_model_files(const char* model_dir, char* out_model_path,
                                                    size_t model_path_size, char* out_mmproj_path,
                                                    size_t mmproj_path_size) {
    if (!model_dir || !out_model_path || !out_mmproj_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    out_model_path[0] = '\0';
    out_mmproj_path[0] = '\0';

    DIR* dir = opendir(model_dir);
    if (!dir) {
        RAC_LOG_ERROR(LOG_CAT, "Cannot open model directory: %s", model_dir);
        return RAC_ERROR_NOT_FOUND;
    }

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        const char* const name = entry->d_name;
        const size_t name_len = strlen(name);

        // Must end with .gguf (case-insensitive)
        if (name_len < 5)
            continue;
        const char* ext = name + name_len - 5;
        if (strcasecmp(ext, ".gguf") != 0)
            continue;

        // Check if this is an mmproj file
        bool is_mmproj = false;
        for (size_t i = 0; i + 5 < name_len; i++) {
            if (strncasecmp(name + i, "mmproj", 6) == 0) {
                is_mmproj = true;
                break;
            }
        }

        if (is_mmproj && out_mmproj_path[0] == '\0') {
            snprintf(out_mmproj_path, mmproj_path_size, "%s/%s", model_dir, name);
        } else if (!is_mmproj && out_model_path[0] == '\0') {
            snprintf(out_model_path, model_path_size, "%s/%s", model_dir, name);
        }

        // Stop once both are found
        if (out_model_path[0] != '\0' && out_mmproj_path[0] != '\0') {
            break;
        }
    }

    closedir(dir);

    if (out_model_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "No .gguf model file found in: %s", model_dir);
        return RAC_ERROR_NOT_FOUND;
    }

    RAC_LOG_INFO(LOG_CAT, "Resolved model: %s", out_model_path);
    if (out_mmproj_path[0] != '\0') {
        RAC_LOG_INFO(LOG_CAT, "Resolved mmproj: %s", out_mmproj_path);
    }

    return RAC_SUCCESS;
}

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

/**
 * Service creation callback for lifecycle manager.
 * Creates and initializes the VLM service.
 */
static rac_result_t vlm_create_service(const char* model_id, void* user_data,
                                       rac_handle_t* out_service) {
    auto* component = reinterpret_cast<rac_vlm_component*>(user_data);

    RAC_LOG_INFO(LOG_CAT, "Creating VLM service for model: %s", model_id ? model_id : "");

    // Create VLM service
    rac_result_t result = rac_vlm_create(model_id, out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create VLM service: %d", result);
        return result;
    }

    // Initialize with model path and mmproj path
    const char* mmproj = component->mmproj_path.empty() ? nullptr : component->mmproj_path.c_str();
    result = rac_vlm_initialize(*out_service, model_id, mmproj);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to initialize VLM service: %d", result);
        rac_vlm_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "VLM service created successfully");
    return RAC_SUCCESS;
}

/**
 * Service destruction callback for lifecycle manager.
 */
static void vlm_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        RAC_LOG_DEBUG(LOG_CAT, "Destroying VLM service");
        rac_vlm_cleanup(service);
        rac_vlm_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_vlm_component_create(rac_handle_t* out_handle) {
    return rac::features::create_lifecycle_component<rac_vlm_component>(
        out_handle, RAC_RESOURCE_TYPE_VLM_MODEL, "VLM.Lifecycle", vlm_create_service,
        vlm_destroy_service, LOG_CAT, "VLM component created");
}

extern "C" rac_result_t rac_vlm_component_configure(rac_handle_t handle,
                                                    const rac_vlm_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config = *config;

    // Update default options based on config
    if (config->max_tokens > 0) {
        component->default_options.max_tokens = config->max_tokens;
    }
    if (config->system_prompt) {
        component->default_options.system_prompt = config->system_prompt;
    }
    component->default_options.temperature = config->temperature;

    RAC_LOG_INFO(LOG_CAT, "VLM component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_vlm_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_vlm_component_get_model_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_vlm_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);

    // Mirror voice_agent.cpp:594. Spin-wait
    // until all in-flight rac_vlm_*_stream_proto / rac_vlm_*_proto entry
    // points have returned before tearing down the lifecycle. Otherwise a
    // racing dispatch thread that already acquired the lifecycle VLM ref
    // can dereference ops vtable / impl pointers after they're freed.
    rac_vlm_proto_quiesce();

    // Destroy lifecycle manager (will cleanup service if loaded)
    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    RAC_LOG_INFO(LOG_CAT, "VLM component destroyed");

    delete component;
}

// =============================================================================
// MODEL LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_vlm_component_load_model(rac_handle_t handle, const char* model_path,
                                                     const char* mmproj_path, const char* model_id,
                                                     const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!model_path)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Store mmproj path for service creation
    component->mmproj_path = mmproj_path ? mmproj_path : "";

    // Delegate to lifecycle manager
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

extern "C" rac_result_t rac_vlm_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->mmproj_path.clear();
    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_vlm_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->mmproj_path.clear();
    return rac_lifecycle_reset(component->lifecycle);
}

extern "C" rac_result_t rac_vlm_component_load_model_by_id(rac_handle_t handle,
                                                           const char* model_id) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!model_id)
        return RAC_ERROR_INVALID_ARGUMENT;

    // 1. Look up model in global registry
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);
    if (result != RAC_SUCCESS || !model_info) {
        RAC_LOG_ERROR(LOG_CAT, "Model not found in registry: %s", model_id);
        return RAC_ERROR_NOT_FOUND;
    }

    // 2. Determine model directory
    char model_folder[1024] = {};

    if (model_info->local_path && model_info->local_path[0] != '\0') {
        // Use the registered local_path — check if it's a directory or file
        struct stat st;
        if (stat(model_info->local_path, &st) == 0 && S_ISDIR(st.st_mode)) {
            snprintf(model_folder, sizeof(model_folder), "%s", model_info->local_path);
        } else {
            // It's a file path — use parent directory
            strncpy(model_folder, model_info->local_path, sizeof(model_folder) - 1);
            char* last_sep = strrchr(model_folder, '/');
            if (last_sep) {
                *last_sep = '\0';
            }
        }
    } else {
        // Fall back to convention-based path
        result = rac_model_paths_get_model_folder(model_id, model_info->framework, model_folder,
                                                  sizeof(model_folder));
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to resolve model folder for: %s", model_id);
            rac_model_info_free(model_info);
            return result;
        }
    }

    // 3. For directory-based models (MetalRT), pass the directory directly.
    //    For GGUF-based models (llama.cpp), resolve .gguf + mmproj files.
    const char* name = model_info->name ? model_info->name : model_id;

    if (rac_framework_uses_directory_based_models(model_info->framework) == RAC_TRUE) {
        struct stat dir_stat;
        if (stat(model_folder, &dir_stat) != 0 || !S_ISDIR(dir_stat.st_mode)) {
            RAC_LOG_ERROR(LOG_CAT, "Directory-based model requires a valid directory path: %s",
                          model_folder);
            rac_model_info_free(model_info);
            return RAC_ERROR_NOT_FOUND;
        }
        RAC_LOG_INFO(LOG_CAT, "Loading directory-based VLM model by ID: %s (dir=%s)", model_id,
                     model_folder);
        result = rac_vlm_component_load_model(handle, model_folder, nullptr, model_id, name);
    } else {
        char model_path[1024] = {};
        char mmproj_path[1024] = {};
        result = rac_vlm_resolve_model_files(model_folder, model_path, sizeof(model_path),
                                             mmproj_path, sizeof(mmproj_path));
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to resolve model files in: %s", model_folder);
            rac_model_info_free(model_info);
            return result;
        }

        const char* mmproj = mmproj_path[0] != '\0' ? mmproj_path : nullptr;
        RAC_LOG_INFO(LOG_CAT, "Loading VLM model by ID: %s (model=%s, mmproj=%s)", model_id,
                     model_path, mmproj ? mmproj : "none");
        result = rac_vlm_component_load_model(handle, model_path, mmproj, model_id, name);
    }

    rac_model_info_free(model_info);
    return result;
}

// =============================================================================
// GENERATION API
// =============================================================================

extern "C" rac_result_t rac_vlm_component_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                                  const char* prompt,
                                                  const rac_vlm_options_t* options,
                                                  rac_vlm_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!image || !prompt || !out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded - cannot process");
        return result;
    }

    // Use provided options or defaults
    const rac_vlm_options_t* effective_options = options ? options : &component->default_options;

    auto start_time = std::chrono::steady_clock::now();

    // Perform VLM processing
    result = rac_vlm_process(service, image, prompt, effective_options, out_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "VLM processing failed: %d", result);
        rac_lifecycle_track_error(component->lifecycle, result, "process");
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    int64_t total_time_ms = duration.count();

    // Update result metrics
    if (out_result->prompt_tokens <= 0) {
        out_result->prompt_tokens = estimate_tokens(prompt);
    }
    if (out_result->completion_tokens <= 0) {
        out_result->completion_tokens = estimate_tokens(out_result->text);
    }
    out_result->total_tokens = out_result->prompt_tokens + out_result->completion_tokens;
    out_result->total_time_ms = total_time_ms;

    if (total_time_ms > 0) {
        out_result->tokens_per_second = static_cast<float>(out_result->completion_tokens) /
                                        (static_cast<float>(total_time_ms) / 1000.0f);
    }

    RAC_LOG_INFO(LOG_CAT, "VLM processing completed");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_vlm_component_supports_streaming(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        return RAC_FALSE;
    }

    rac_vlm_info_t info;
    rac_result_t result = rac_vlm_get_info(service, &info);
    if (result != RAC_SUCCESS) {
        return RAC_FALSE;
    }

    return info.supports_streaming;
}

/**
 * Internal structure for VLM streaming context.
 *
 * full_text accumulates raw tokens (including special tokens) for debugging/metrics.
 * cleaned_text accumulates stripped tokens and is used for the final result text.
 */
struct vlm_stream_context {
    rac_vlm_component_token_callback_fn token_callback;
    rac_vlm_component_complete_callback_fn complete_callback;
    rac_vlm_component_error_callback_fn error_callback;
    void* user_data;

    // Metrics tracking
    std::chrono::steady_clock::time_point start_time;
    std::chrono::steady_clock::time_point first_token_time;
    bool first_token_recorded;
    std::string full_text;
    std::string cleaned_text;
    int32_t prompt_tokens;
    int32_t token_count;
};

/**
 * Internal token callback that wraps user callback and tracks metrics.
 * Strips special tokens (e.g. <|im_end|>) before forwarding to the caller.
 */
static rac_bool_t vlm_stream_token_callback(const char* token, void* user_data) {
    auto* ctx = reinterpret_cast<vlm_stream_context*>(user_data);

    if (!token)
        return RAC_TRUE;

    // Strip special tokens from the model output
    char cleaned[512];
    vlm_strip_special_tokens(token, cleaned, sizeof(cleaned));

    // Track first token time (only for non-empty cleaned tokens)
    if (cleaned[0] != '\0' && !ctx->first_token_recorded) {
        ctx->first_token_recorded = true;
        ctx->first_token_time = std::chrono::steady_clock::now();
    }

    // Accumulate raw text for debugging and cleaned text for the final result
    ctx->full_text += token;
    if (cleaned[0] != '\0') {
        ctx->cleaned_text += cleaned;
    }
    ctx->token_count++;

    // Forward only non-empty cleaned tokens to the user callback
    if (cleaned[0] != '\0' && ctx->token_callback) {
        return ctx->token_callback(cleaned, ctx->user_data);
    }

    return RAC_TRUE;
}

extern "C" rac_result_t rac_vlm_component_process_stream(
    rac_handle_t handle, const rac_vlm_image_t* image, const char* prompt,
    const rac_vlm_options_t* options, rac_vlm_component_token_callback_fn token_callback,
    rac_vlm_component_complete_callback_fn complete_callback,
    rac_vlm_component_error_callback_fn error_callback, void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!image || !prompt)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded - cannot process stream");
        if (error_callback) {
            error_callback(result, "No model loaded", user_data);
        }
        return result;
    }

    // Check if streaming is supported
    rac_vlm_info_t info;
    result = rac_vlm_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        RAC_LOG_ERROR(LOG_CAT, "Streaming not supported");
        if (error_callback) {
            error_callback(RAC_ERROR_NOT_SUPPORTED, "Streaming not supported", user_data);
        }
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO(LOG_CAT, "Starting VLM streaming generation");

    // Use provided options or defaults
    const rac_vlm_options_t* effective_options = options ? options : &component->default_options;

    // Setup streaming context
    vlm_stream_context ctx;
    ctx.token_callback = token_callback;
    ctx.complete_callback = complete_callback;
    ctx.error_callback = error_callback;
    ctx.user_data = user_data;
    ctx.start_time = std::chrono::steady_clock::now();
    ctx.first_token_recorded = false;
    ctx.prompt_tokens = estimate_tokens(prompt);
    ctx.token_count = 0;

    // Pre-allocate string capacity to avoid repeated reallocations during streaming.
    // Typical VLM responses are a few hundred tokens (~2KB text).
    ctx.full_text.reserve(2048);
    ctx.cleaned_text.reserve(2048);

    // Perform streaming generation
    result = rac_vlm_process_stream(service, image, prompt, effective_options,
                                    vlm_stream_token_callback, &ctx);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "VLM streaming generation failed");
        rac_lifecycle_track_error(component->lifecycle, result, "processStream");
        if (error_callback) {
            error_callback(result, "Streaming generation failed", user_data);
        }
        return result;
    }

    // Build final result for completion callback
    auto end_time = std::chrono::steady_clock::now();
    auto total_duration =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - ctx.start_time);
    int64_t total_time_ms = total_duration.count();

    rac_vlm_result_t final_result = {};
    // Use cleaned_text (special tokens stripped) for the final result.
    // Fall back to full_text if no cleaned tokens were produced.
    const std::string& result_text = ctx.cleaned_text.empty() ? ctx.full_text : ctx.cleaned_text;
    final_result.text = strdup(result_text.c_str());
    if (!final_result.text) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate result text");
        if (error_callback) {
            error_callback(RAC_ERROR_OUT_OF_MEMORY, "Failed to allocate result text", user_data);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    final_result.prompt_tokens = ctx.prompt_tokens;
    final_result.completion_tokens = estimate_tokens(result_text.c_str());
    final_result.total_tokens = final_result.prompt_tokens + final_result.completion_tokens;
    final_result.total_time_ms = total_time_ms;

    // Calculate TTFT
    if (ctx.first_token_recorded) {
        auto ttft_duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            ctx.first_token_time - ctx.start_time);
        final_result.time_to_first_token_ms = ttft_duration.count();
    }

    // Calculate tokens per second
    if (final_result.total_time_ms > 0) {
        final_result.tokens_per_second = static_cast<float>(final_result.completion_tokens) /
                                         (static_cast<float>(final_result.total_time_ms) / 1000.0f);
    }

    if (complete_callback) {
        complete_callback(&final_result, user_data);
    }

    // Free the duplicated text
    free(final_result.text);

    RAC_LOG_INFO(LOG_CAT, "VLM streaming generation completed");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_vlm_component_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);

    // Do NOT acquire component->mtx here. process_stream holds the mutex for
    // the entire streaming duration, so locking here would deadlock until
    // generation finishes — defeating the purpose of cancel.
    // rac_vlm_cancel only sets an atomic bool, so it is safe without the lock.
    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (service) {
        rac_vlm_cancel(service);
    }

    RAC_LOG_INFO(LOG_CAT, "VLM generation cancellation requested");

    return RAC_SUCCESS;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_vlm_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_vlm_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vlm_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

// =============================================================================
// PROTO-BACKED LOAD FROM RESOLVED ARTIFACTS
// =============================================================================

extern "C" rac_result_t rac_vlm_component_load_resolved_artifacts_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    const bool bytes_ok =
        (request_proto_size == 0 || request_proto_bytes != nullptr) &&
        request_proto_size <= static_cast<size_t>(std::numeric_limits<int>::max());
    if (!bytes_ok) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "VLMLoadResolvedArtifactsRequest bytes are invalid");
    }

    runanywhere::v1::VLMLoadResolvedArtifactsRequest request;
    static const char kEmpty[] = "";
    const void* parse_src = request_proto_size == 0 ? static_cast<const void*>(kEmpty)
                                                    : static_cast<const void*>(request_proto_bytes);
    if (!request.ParseFromArray(parse_src, static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VLMLoadResolvedArtifactsRequest");
    }

    auto emit_failure = [&](rac_result_t code, const char* message) -> rac_result_t {
        runanywhere::v1::VLMLoadResolvedArtifactsResponse response;
        response.set_handle(0);
        response.set_result_code(code);
        if (message && message[0])
            response.set_error_message(message);
        const size_t size = response.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !response.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            return rac_proto_buffer_set_error(
                out_result, RAC_ERROR_ENCODING_ERROR,
                "failed to serialize VLMLoadResolvedArtifactsResponse");
        }
        return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(),
                                     out_result);
    };

    const std::string& primary = request.primary_model_path();
    if (primary.empty()) {
        return emit_failure(RAC_ERROR_INVALID_ARGUMENT, "primary_model_path is required");
    }

    const std::string& model_id = request.model_id();
    const std::string create_id = model_id.empty() ? primary : model_id;

    rac_handle_t service_handle = nullptr;
    rac_result_t rc = rac_vlm_create(create_id.c_str(), &service_handle);
    if (rc != RAC_SUCCESS || !service_handle) {
        return emit_failure(rc != RAC_SUCCESS ? rc : RAC_ERROR_INTERNAL, rac_error_message(rc));
    }

    const char* mmproj_arg = request.has_mmproj_path() && !request.mmproj_path().empty()
                                 ? request.mmproj_path().c_str()
                                 : nullptr;
    rc = rac_vlm_initialize(service_handle, primary.c_str(), mmproj_arg);
    if (rc != RAC_SUCCESS) {
        rac_vlm_destroy(service_handle);
        service_handle = nullptr;
        return emit_failure(rc, rac_error_message(rc));
    }

    runanywhere::v1::VLMLoadResolvedArtifactsResponse response;
    response.set_handle(reinterpret_cast<uint64_t>(service_handle));
    response.set_result_code(RAC_SUCCESS);
    const size_t size = response.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !response.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        rac_vlm_destroy(service_handle);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize VLMLoadResolvedArtifactsResponse");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
#endif
}

// =============================================================================
// PROTO-BYTE C ABI (formerly rac_vlm_proto_abi.cpp)
//
// Proto-byte verbs for VLM service operations. rac_vlm_process_proto keeps both
// the lifecycle-owned path and the legacy handle-as-service fallback. The
// VlmInFlightGuard + rac_vlm_proto_quiesce in-flight quiesce (called from
// rac_vlm_component_destroy above) close the UAF window where a destroy thread
// races a still-in-flight stream dispatch.
// =============================================================================

namespace {

// Lift the voice_agent in_flight quiesce pattern
// to the VLM proto-byte dispatcher. Even though VLM does NOT publish a
// registry-style set/unset stream-callback ABI (each rac_vlm_*_stream_proto
// entry point owns a per-call StreamCtx / GeneratedStreamCtx and invokes
// ops->process_stream synchronously), a defensive in_flight counter still
// closes two real race windows:
//   1. A buggy backend that fires a stray trampoline invocation AFTER
//      ops->process_stream has returned (the Phase 6f EXC_BAD_ACCESS that
//      motivated the existing unique_ptr<StreamCtx> heap allocation).
//   2. Any caller that tears down the lifecycle VLM (rac_vlm_component_destroy
//      / rac_lifecycle_destroy) while a stream entry-point is still mid-call
//      on another thread — release_lifecycle_vlm currently has no quiesce
//      contract, so a destroy thread can race the dispatch thread.
// We increment the counter on entry to each stream entry-point and decrement
// just before returning. rac_vlm_component_destroy spin-waits for the counter
// to drain to zero, exactly mirroring voice_agent.cpp:594.
//
// Complete the voice_agent pattern by adding an
// is_shutting_down barrier (voice_agent.cpp:569 / 1212-1221). Without it, a
// new caller could acquire the in_flight counter mid-quiesce and extend the
// spin-wait indefinitely (and worse, dispatch on a legacy struct-API service
// whose backend is being freed). VlmInFlightGuard now performs the canonical
// TOCTOU-safe sequence: check flag, increment counter, re-check flag, and
// expose admitted() so entry points can early-return without dispatching.
std::atomic<int>& vlm_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

std::atomic<bool>& vlm_proto_shutting_down() {
    static std::atomic<bool> flag{false};
    return flag;
}

struct VlmInFlightGuard {
    VlmInFlightGuard() {
        if (vlm_proto_shutting_down().load(std::memory_order_acquire)) {
            return;
        }
        vlm_in_flight().fetch_add(1, std::memory_order_acq_rel);
        // Re-check after incrementing to avoid TOCTOU with rac_vlm_proto_quiesce.
        if (vlm_proto_shutting_down().load(std::memory_order_acquire)) {
            vlm_in_flight().fetch_sub(1, std::memory_order_acq_rel);
            return;
        }
        admitted_ = true;
    }
    ~VlmInFlightGuard() {
        if (admitted_) {
            vlm_in_flight().fetch_sub(1, std::memory_order_acq_rel);
        }
    }
    bool admitted() const { return admitted_; }
    VlmInFlightGuard(const VlmInFlightGuard&) = delete;
    VlmInFlightGuard& operator=(const VlmInFlightGuard&) = delete;

   private:
    bool admitted_{false};
};

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

int64_t now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return buffer;
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

void populate_envelope(runanywhere::v1::SDKEvent* event, runanywhere::v1::ErrorSeverity severity) {
    event->set_id(event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(runanywhere::v1::EVENT_CATEGORY_VLM);
    event->set_severity(severity);
    event->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_source("cpp");
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    // Route through the destination router (sdk_event_publish) so the envelope's
    // TELEMETRY destination bit reaches the telemetry manager. A direct
    // rac_sdk_event_publish_proto call feeds only the PUBLIC stream, so these
    // capability events would never be recorded as telemetry.
    (void)rac::events::publish_prebuilt(event);
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        float progress, int64_t input_count, int64_t output_count,
                        const char* error, double duration_ms = 0.0,
                        const char* model_id = nullptr, int64_t input_tokens = 0,
                        int64_t total_tokens = 0, double tokens_per_second = 0.0,
                        double ttft_ms = 0.0, const char* framework = nullptr,
                        double temperature = -1.0, int32_t max_tokens = 0,
                        int64_t vision_tokens = 0, double vision_encode_ms = 0.0,
                        const char* image_resolution = nullptr) {
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, (error != nullptr && error[0] != '\0')
                                  ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                  : runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    if (model_id != nullptr && model_id[0] != '\0') {
        cap->set_model_id(model_id);
    }
    if (framework != nullptr && framework[0] != '\0') {
        (*event.mutable_properties())["framework"] = framework;
    }
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error)
        cap->set_error(error);
    // CapabilityOperationEvent has no duration field; telemetry reads it from
    // the envelope properties map (see telemetry_manager kCapability extraction).
    if (duration_ms > 0.0) {
        (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    }
    // VLM token metrics ride the properties carrier (the VLM V2 row carries the
    // LLM-style token fields; output_tokens comes from output_count above).
    if (input_tokens > 0) {
        (*event.mutable_properties())["input_tokens"] = std::to_string(input_tokens);
    }
    if (total_tokens > 0) {
        (*event.mutable_properties())["total_tokens"] = std::to_string(total_tokens);
    }
    if (tokens_per_second > 0.0) {
        (*event.mutable_properties())["tokens_per_second"] = std::to_string(tokens_per_second);
    }
    if (ttft_ms > 0.0) {
        (*event.mutable_properties())["time_to_first_token_ms"] = std::to_string(ttft_ms);
    }
    // temperature=0.0 is a valid (greedy) setting, so a -1.0 sentinel marks
    // "not provided"; max_tokens 0 means unset.
    if (temperature >= 0.0) {
        (*event.mutable_properties())["temperature"] = std::to_string(temperature);
    }
    if (max_tokens > 0) {
        (*event.mutable_properties())["max_tokens"] = std::to_string(max_tokens);
    }
    // Vision-specific metrics (0 when the engine doesn't surface them → skipped).
    if (vision_tokens > 0) {
        (*event.mutable_properties())["vision_tokens"] = std::to_string(vision_tokens);
    }
    if (vision_encode_ms > 0.0) {
        (*event.mutable_properties())["vision_encode_time_ms"] = std::to_string(vision_encode_ms);
    }
    if (image_resolution != nullptr && image_resolution[0] != '\0') {
        (*event.mutable_properties())["image_resolution"] = image_resolution;
    }
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(
        runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED, operation, 0.0f, 0, 0,
        (message != nullptr && message[0] != '\0') ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "vlm", operation, RAC_TRUE);
}

void free_vlm_image(rac_vlm_image_t* image) {
    if (!image)
        return;
    rac_free(const_cast<char*>(image->file_path));
    rac_free(const_cast<uint8_t*>(image->pixel_data));
    rac_free(const_cast<char*>(image->base64_data));
    std::memset(image, 0, sizeof(*image));
}

rac_result_t parse_vlm_request(const uint8_t* image_bytes, size_t image_size,
                               const uint8_t* options_bytes, size_t options_size,
                               rac_vlm_image_t* out_image, rac_vlm_options_t* out_options,
                               const char** out_prompt, rac_proto_buffer_t* out_error) {
    if (!valid_bytes(image_bytes, image_size) || !valid_bytes(options_bytes, options_size)) {
        return parse_error(out_error, "VLM proto input bytes are invalid");
    }

    runanywhere::v1::VLMImage image_proto;
    if (!image_proto.ParseFromArray(parse_data(image_bytes, image_size),
                                    static_cast<int>(image_size))) {
        return parse_error(out_error, "failed to parse VLMImage");
    }

    runanywhere::v1::VLMGenerationOptions options_proto;
    if (!options_proto.ParseFromArray(parse_data(options_bytes, options_size),
                                      static_cast<int>(options_size))) {
        return parse_error(out_error, "failed to parse VLMGenerationOptions");
    }

    if (!rac::foundation::rac_vlm_image_from_proto(image_proto, out_image) ||
        !rac::foundation::rac_vlm_options_from_proto(options_proto, out_options, out_prompt)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert VLM request");
    }
    if (!*out_prompt || (*out_prompt)[0] == '\0') {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VLMGenerationOptions.prompt is required");
    }
    if (!out_image->file_path && !out_image->pixel_data && !out_image->base64_data) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VLMImage source is required");
    }
    return RAC_SUCCESS;
}

rac_result_t parse_vlm_generation_request(const uint8_t* request_bytes, size_t request_size,
                                          runanywhere::v1::VLMGenerationRequest* out_request,
                                          rac_vlm_image_t* out_image,
                                          rac_vlm_options_t* out_options, const char** out_prompt,
                                          rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_bytes, request_size)) {
        return parse_error(out_error, "VLMGenerationRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_bytes, request_size),
                                     static_cast<int>(request_size))) {
        return parse_error(out_error, "failed to parse VLMGenerationRequest");
    }
    if (out_request->images_size() != 1) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_INVALID_ARGUMENT,
            "VLMGenerationRequest.images must contain exactly one image");
    }

    const runanywhere::v1::VLMGenerationOptions& options_proto =
        out_request->has_options() ? out_request->options()
                                   : runanywhere::v1::VLMGenerationOptions::default_instance();

    if (!rac::foundation::rac_vlm_image_from_proto(out_request->images(0), out_image) ||
        !rac::foundation::rac_vlm_options_from_proto(options_proto, out_options, out_prompt)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert VLMGenerationRequest");
    }
    if (!*out_prompt || (*out_prompt)[0] == '\0') {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VLMGenerationOptions.prompt is required");
    }
    if (!out_image->file_path && !out_image->pixel_data && !out_image->base64_data) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VLMImage source is required");
    }
    return RAC_SUCCESS;
}

rac_result_t check_lifecycle_model(const runanywhere::v1::VLMGenerationRequest& request,
                                   const rac::vlm::LifecycleVlmRef& ref,
                                   rac_proto_buffer_t* out_error) {
    if (!request.model_id().empty() && ref.model_id && request.model_id() != ref.model_id) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_INVALID_ARGUMENT,
            "VLMGenerationRequest.model_id does not match the lifecycle-loaded model");
    }
    return RAC_SUCCESS;
}

// Aggregate-result accumulator for the typed stream path. (The legacy
// SDKEvent-envelope stream ABI that originally owned this struct was
// removed; only text/token_count feed populate_result_from_stream.)
struct StreamCtx {
    std::string text;
    int32_t token_count{0};
};

void populate_result_from_stream(const StreamCtx& ctx, int64_t elapsed_ms,
                                 runanywhere::v1::VLMResult* out) {
    out->set_text(ctx.text);
    out->set_completion_tokens(ctx.token_count);
    out->set_total_tokens(ctx.token_count);
    out->set_processing_time_ms(elapsed_ms);
    if (elapsed_ms > 0) {
        out->set_tokens_per_second(static_cast<float>(ctx.token_count) /
                                   (static_cast<float>(elapsed_ms) / 1000.0f));
    }
}

struct GeneratedStreamCtx {
    rac_vlm_stream_event_proto_callback_fn callback{nullptr};
    void* user_data{nullptr};
    rac::vlm::LifecycleVlmRef* ref{nullptr};
    std::string request_id;
    std::string text;
    uint64_t seq{0};
    int32_t token_count{0};
    int64_t started_ms{0};
    bool terminal_sent{false};
};

bool serialize_vlm_stream_event(const runanywhere::v1::VLMStreamEvent& event,
                                std::vector<uint8_t>* out) {
    out->resize(event.ByteSizeLong());
    return out->empty() || event.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

rac_bool_t dispatch_vlm_stream_event(GeneratedStreamCtx* ctx,
                                     runanywhere::v1::VLMStreamEventKind kind, const char* token,
                                     bool is_final, const runanywhere::v1::VLMResult* result,
                                     const char* error_message, int32_t error_code) {
    if (!ctx || !ctx->callback) {
        return RAC_TRUE;
    }

    runanywhere::v1::VLMStreamEvent event;
    event.set_seq(++ctx->seq);
    event.set_timestamp_us(now_us());
    event.set_request_id(ctx->request_id);
    event.set_kind(kind);
    event.set_is_final(is_final);
    if (token != nullptr && token[0] != '\0') {
        event.set_token(token);
        event.set_token_index(ctx->token_count - 1);
    }
    if (result) {
        event.mutable_result()->CopyFrom(*result);
        event.set_tokens_per_second(result->tokens_per_second());
    }
    if (error_message != nullptr && error_message[0] != '\0') {
        event.set_error_message(error_message);
    }
    if (error_code != 0) {
        event.set_error_code(error_code);
    }

    std::vector<uint8_t> bytes;
    if (!serialize_vlm_stream_event(event, &bytes)) {
        return RAC_FALSE;
    }
    return ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
}

rac_bool_t dispatch_vlm_terminal_once(GeneratedStreamCtx* ctx,
                                      runanywhere::v1::VLMStreamEventKind kind,
                                      const runanywhere::v1::VLMResult* result,
                                      const char* error_message, int32_t error_code) {
    if (!ctx || ctx->terminal_sent) {
        return RAC_TRUE;
    }
    ctx->terminal_sent = true;
    return dispatch_vlm_stream_event(ctx, kind, nullptr, true, result, error_message, error_code);
}

rac_bool_t generated_stream_token_trampoline(const char* token, void* user_data) {
    auto* ctx = static_cast<GeneratedStreamCtx*>(user_data);
    if (!ctx || !ctx->ref)
        return RAC_FALSE;
    if (rac::vlm::lifecycle_vlm_cancel_requested(ctx->ref)) {
        return RAC_FALSE;
    }

    const char* safe_token = token ? token : "";
    ctx->text += safe_token;
    if (safe_token[0] != '\0') {
        ++ctx->token_count;
    }

    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* generation = event.mutable_generation();
    generation->set_kind(ctx->token_count == 1
                             ? runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED
                             : runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED);
    generation->set_token(safe_token);
    generation->set_streaming_text(ctx->text);
    generation->set_tokens_count(ctx->token_count);
    if (ctx->ref->model_id)
        generation->set_model_id(ctx->ref->model_id);
    publish_event(event);

    return dispatch_vlm_stream_event(ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_TOKEN, safe_token,
                                     false, nullptr, nullptr, 0);
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

// Public quiesce helper. Callers (rac_vlm_component_destroy, lifecycle
// teardown paths in SDK bridges) spin-wait here before freeing any
// user_data that may have been passed into a rac_vlm_*_stream_proto call.
// Mirrors the in-flight quiesce contract used by the LLM dispatcher.
//
// Set the is_shutting_down barrier FIRST so any caller that
// tries to enter the dispatcher after quiesce begins is rejected by
// VlmInFlightGuard, then spin-wait until currently-in-flight calls drain.
// This mirrors voice_agent.cpp:569-592 and rac_diffusion_proto_quiesce.
//
// e2e-rn-vlm-fix: the barrier MUST be cleared after the drain completes.
// The original implementation left the flag process-lifetime sticky on the
// assumption that VLM only quiesces at destroy. That assumption was wrong:
// the RN core Nitro bridge (HybridRunAnywhereCore+Voice.cpp:952) and the
// Flutter VLM bridge (dart_bridge_vlm.dart:164/175) both invoke this quiesce
// as a per-stream drain after EVERY rac_vlm_stream_proto call — the exact
// teardown recipe documented in rac_vlm_service.h:236-243 and shared with the
// LLM/STT/TTS dispatchers, whose quiesce helpers are pure idempotent drains.
// Leaving the flag latched poisoned the ABI: the SECOND describe (and the
// first RN describe after any earlier stream) was rejected by
// VlmInFlightGuard with RAC_ERROR_INVALID_STATE, surfacing in JS/Dart as
// "rac_vlm_stream_proto failed: invalid state". Clearing the barrier after
// the drain — identical to rac_diffusion_proto_quiesce, which already does
// this for its per-model-swap reuse — keeps the ABI reusable across streams
// while preserving the TOCTOU-safe barrier+drain window (any dispatcher entry
// that observed false→true was rejected or already drained before the clear).
// Swift is unaffected: its VLM stream path never calls this quiesce per
// stream (it cancels via rac_vlm_cancel_proto in onTermination). The destroy
// paths (vlm_component.cpp:350, rac_vlm_service.cpp:274) remain safe because
// they tear down the lifecycle immediately afterwards, so a post-clear
// acquire_lifecycle_vlm returns RAC_ERROR_NOT_INITIALIZED rather than
// dispatching into freed state.
void rac_vlm_proto_quiesce(void) {
    vlm_proto_shutting_down().store(true, std::memory_order_release);
    while (vlm_in_flight().load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
    vlm_proto_shutting_down().store(false, std::memory_order_release);
}

rac_result_t rac_vlm_process_proto(rac_handle_t handle, const uint8_t* image_proto_bytes,
                                   size_t image_proto_size, const uint8_t* options_proto_bytes,
                                   size_t options_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)image_proto_bytes;
    (void)image_proto_size;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return feature_unavailable(out_result);
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "VLM proto ABI is shutting down");
    }
    // Phase 6j fix: prefer the lifecycle-owned VLM service over the caller's
    // handle. iOS SDK's `CppBridge.VLM` passes a `rac_vlm_component*` into this
    // proto ABI (the only VLM handle it owns), not a `rac_vlm_service_t*`.
    // Blindly casting to `rac_vlm_service_t*` previously misread the ops vtable
    // pointer out of the component's `LifecycleManager::logger_category`
    // std::string, producing `EXC_BAD_ACCESS` at `0x6566694c2e4d4c56` -- the
    // little-endian encoding of "VLM.Life" -- on iPhone 17 Pro Max. Routing
    // through `acquire_lifecycle_vlm` removes the handle-type dependency
    // entirely; Swift, Kotlin, and JNI callers all populate the lifecycle via
    // `rac_model_lifecycle_load_proto` before inference, so the lifecycle
    // reference is always authoritative. The `handle` parameter is retained
    // only for the legacy struct-API smoke tests that pass a mock
    // `rac_vlm_service_t*` without going through the lifecycle.
    rac::vlm::LifecycleVlmRef lifecycle_ref;
    const rac_result_t acquire_rc = rac::vlm::acquire_lifecycle_vlm(&lifecycle_ref);
    const bool have_lifecycle = (acquire_rc == RAC_SUCCESS);

    if (!have_lifecycle && !handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.process",
                        "VLM lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "VLM lifecycle component is not loaded");
    }

    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rac_result_t rc = parse_vlm_request(image_proto_bytes, image_proto_size, options_proto_bytes,
                                        options_proto_size, &image, &options, &prompt, out_result);
    if (rc != RAC_SUCCESS) {
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        if (have_lifecycle)
            rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
        publish_failure(rc, "vlm.process", out_result->error_message);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED, "vlm.process",
                       0.0f, 1, 0, nullptr, 0.0,
                       have_lifecycle ? lifecycle_ref.model_id : nullptr);

    rac_vlm_result_t result = {};
    if (have_lifecycle) {
        if (!lifecycle_ref.ops || !lifecycle_ref.ops->process) {
            rc = RAC_ERROR_NOT_SUPPORTED;
        } else {
            rc = lifecycle_ref.ops->process(lifecycle_ref.impl, &image, prompt, &options, &result);
        }
    } else {
        // Legacy struct-API path: caller provided a `rac_vlm_service_t*`.
        rc = rac_vlm_process(handle, &image, prompt, &options, &result);
    }
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.process", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        if (have_lifecycle)
            rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::VLMResult proto;
    if (!rac::foundation::rac_vlm_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode VLMResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    const std::string vlm_res = (image.width > 0 && image.height > 0)
                                    ? std::to_string(image.width) + "x" + std::to_string(image.height)
                                    : std::string();
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                       "vlm.process", 1.0f, 1, proto.completion_tokens(), nullptr,
                       static_cast<double>(proto.processing_time_ms()),
                       have_lifecycle ? lifecycle_ref.model_id : nullptr, proto.prompt_tokens(),
                       proto.total_tokens(), static_cast<double>(proto.tokens_per_second()),
                       static_cast<double>(proto.time_to_first_token_ms()),
                       have_lifecycle ? lifecycle_ref.framework_name : nullptr,
                       static_cast<double>(options.temperature), options.max_tokens,
                       proto.image_tokens(), static_cast<double>(proto.image_encode_time_ms()),
                       vlm_res.empty() ? nullptr : vlm_res.c_str());
    rac_vlm_result_free(&result);
    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    rac::foundation::rac_vlm_options_free_owned(&options);
    if (have_lifecycle)
        rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
    return rc;
#endif
}

rac_result_t rac_vlm_cancel_proto(rac_handle_t handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return RAC_ERROR_INVALID_STATE;
    }
    // Phase 6j fix: prefer the lifecycle-owned VLM to avoid the handle-type
    // mismatch that crashed `rac_vlm_process_proto` on iOS. The `handle`
    // parameter is kept only as a legacy fallback for struct-API smoke tests.
    rac::vlm::LifecycleVlmRef lifecycle_ref;
    const rac_result_t acquire_rc = rac::vlm::acquire_lifecycle_vlm(&lifecycle_ref);
    const bool have_lifecycle = (acquire_rc == RAC_SUCCESS);

    if (!have_lifecycle && !handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.cancel",
                        "VLM lifecycle component is not loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    runanywhere::v1::SDKEvent requested;
    populate_envelope(&requested, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    cancel->set_operation_id("vlm.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    rac_result_t rc;
    if (have_lifecycle) {
        if (lifecycle_ref.ops && lifecycle_ref.ops->cancel) {
            rc = lifecycle_ref.ops->cancel(lifecycle_ref.impl);
        } else {
            rc = RAC_SUCCESS;  // No-op if backend doesn't implement cancel
        }
    } else {
        rc = rac_vlm_cancel(handle);
    }
    runanywhere::v1::SDKEvent completed;
    populate_envelope(&completed, rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                                    : runanywhere::v1::ERROR_SEVERITY_ERROR);
    auto* completed_cancel = completed.mutable_cancellation();
    completed_cancel->set_kind(rc == RAC_SUCCESS
                                   ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                   : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    completed_cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    completed_cancel->set_operation_id("vlm.cancel");
    completed_cancel->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    completed_cancel->set_user_initiated(true);
    publish_event(completed);
    if (have_lifecycle)
        rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
    return rc;
#endif
}

rac_result_t rac_vlm_generate_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                    rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "VLM proto ABI is shutting down");
    }
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.generate", "no lifecycle VLM model loaded");
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle VLM model loaded");
    }

    runanywhere::v1::VLMGenerationRequest request;
    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rc = parse_vlm_generation_request(request_proto_bytes, request_proto_size, &request, &image,
                                      &options, &prompt, out_result);
    if (rc == RAC_SUCCESS) {
        rc = check_lifecycle_model(request, ref, out_result);
    }
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.generate", out_result->error_message);
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return rc;
    }

    rac::vlm::clear_lifecycle_vlm_cancel(&ref);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED, "vlm.generate",
                       0.0f, 1, 0, nullptr, 0.0, ref.model_id);

    rac_vlm_result_t raw = {};
    rc = (ref.ops && ref.ops->process) ? ref.ops->process(ref.impl, &image, prompt, &options, &raw)
                                       : RAC_ERROR_NOT_SUPPORTED;
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.generate", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::VLMResult result;
    if (!rac::foundation::rac_vlm_result_to_proto(&raw, &result)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode VLMResult");
    } else {
        rc = copy_proto(result, out_result);
    }
    const std::string vlm_gen_res =
        (image.width > 0 && image.height > 0)
            ? std::to_string(image.width) + "x" + std::to_string(image.height)
            : std::string();
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                       "vlm.generate", 1.0f, 1, result.completion_tokens(), nullptr,
                       static_cast<double>(result.processing_time_ms()), ref.model_id,
                       result.prompt_tokens(), result.total_tokens(),
                       static_cast<double>(result.tokens_per_second()),
                       static_cast<double>(result.time_to_first_token_ms()), ref.framework_name,
                       static_cast<double>(options.temperature), options.max_tokens,
                       result.image_tokens(), static_cast<double>(result.image_encode_time_ms()),
                       vlm_gen_res.empty() ? nullptr : vlm_gen_res.c_str());
    rac_vlm_result_free(&raw);
    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    rac::foundation::rac_vlm_options_free_owned(&options);
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc;
#endif
}

rac_result_t rac_vlm_stream_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                  rac_vlm_stream_event_proto_callback_fn callback,
                                  void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback) {
        return RAC_ERROR_NULL_POINTER;
    }

    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return RAC_ERROR_INVALID_STATE;
    }
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.stream", "no lifecycle VLM model loaded");
        return rc;
    }

    rac_proto_buffer_t error_buffer;
    rac_proto_buffer_init(&error_buffer);
    runanywhere::v1::VLMGenerationRequest request;
    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rc = parse_vlm_generation_request(request_proto_bytes, request_proto_size, &request, &image,
                                      &options, &prompt, &error_buffer);
    if (rc == RAC_SUCCESS) {
        rc = check_lifecycle_model(request, ref, &error_buffer);
    }
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.stream", error_buffer.error_message);
        rac_proto_buffer_free(&error_buffer);
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return rc;
    }
    rac_proto_buffer_free(&error_buffer);
    if (!ref.ops || !ref.ops->process_stream) {
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac::vlm::clear_lifecycle_vlm_cancel(&ref);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED, "vlm.stream",
                       0.0f, 1, 0, nullptr, 0.0, ref.model_id);

    GeneratedStreamCtx ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.request_id = request.request_id();
    ctx.started_ms = now_ms();

    dispatch_vlm_stream_event(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_STARTED, nullptr, false,
                              nullptr, nullptr, 0);

    rc = ref.ops->process_stream(ref.impl, &image, prompt, &options,
                                 generated_stream_token_trampoline, &ctx);

    const int64_t elapsed_ms = now_ms() - ctx.started_ms;
    const bool cancelled = rac::vlm::lifecycle_vlm_cancel_requested(&ref) ||
                           rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        runanywhere::v1::VLMResult result;
        populate_result_from_stream(StreamCtx{.text = ctx.text, .token_count = ctx.token_count},
                                    elapsed_ms, &result);
        dispatch_vlm_terminal_once(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_COMPLETED, &result,
                                   nullptr, 0);
        rc = RAC_SUCCESS;
    } else if (rc != RAC_SUCCESS) {
        dispatch_vlm_terminal_once(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_ERROR, nullptr,
                                   rac_error_message(rc), static_cast<int32_t>(rc));
        publish_failure(rc, "vlm.stream", rac_error_message(rc));
    } else {
        runanywhere::v1::VLMResult result;
        populate_result_from_stream(StreamCtx{.text = ctx.text, .token_count = ctx.token_count},
                                    elapsed_ms, &result);
        dispatch_vlm_terminal_once(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_COMPLETED, &result,
                                   nullptr, 0);
        const std::string vlm_stream_res =
            (image.width > 0 && image.height > 0)
                ? std::to_string(image.width) + "x" + std::to_string(image.height)
                : std::string();
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                           "vlm.stream", 1.0f, 1, ctx.token_count, nullptr,
                           static_cast<double>(elapsed_ms), ref.model_id, result.prompt_tokens(),
                           result.total_tokens(), static_cast<double>(result.tokens_per_second()),
                           static_cast<double>(result.time_to_first_token_ms()), ref.framework_name,
                           static_cast<double>(options.temperature), options.max_tokens,
                           result.image_tokens(), static_cast<double>(result.image_encode_time_ms()),
                           vlm_stream_res.empty() ? nullptr : vlm_stream_res.c_str());
    }

    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    rac::foundation::rac_vlm_options_free_owned(&options);
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc;
#endif
}

rac_result_t rac_vlm_cancel_lifecycle_proto(rac_proto_buffer_t* out_event) {
    if (!out_event)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_event);
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return rac_proto_buffer_set_error(out_event, RAC_ERROR_INVALID_STATE,
                                          "VLM proto ABI is shutting down");
    }
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.cancel", "no lifecycle VLM model loaded");
        return rac_proto_buffer_set_error(out_event, rc, "no lifecycle VLM model loaded");
    }

    rac::vlm::request_lifecycle_vlm_cancel(&ref);
    runanywhere::v1::SDKEvent requested;
    populate_envelope(&requested, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    cancel->set_operation_id("vlm.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    if (ref.ops && ref.ops->cancel) {
        rc = ref.ops->cancel(ref.impl);
    } else {
        rc = RAC_SUCCESS;
    }

    runanywhere::v1::SDKEvent completed;
    populate_envelope(&completed, rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                                    : runanywhere::v1::ERROR_SEVERITY_ERROR);
    auto* completed_cancel = completed.mutable_cancellation();
    completed_cancel->set_kind(rc == RAC_SUCCESS
                                   ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                   : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    completed_cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    completed_cancel->set_operation_id("vlm.cancel");
    completed_cancel->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    completed_cancel->set_user_initiated(true);
    publish_event(completed);

    rac_result_t copy_rc = copy_proto(completed, out_event);
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc == RAC_SUCCESS ? copy_rc : rc;
#endif
}

}  // extern "C"
