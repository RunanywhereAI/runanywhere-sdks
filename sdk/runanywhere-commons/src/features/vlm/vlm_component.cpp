/**
 * @file vlm_component.cpp
 * @brief VLM Capability Component Implementation
 *
 * Vision Language Model component that owns model lifecycle and generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <mutex>
#include <string>
#include <sys/stat.h>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

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
    size_t len = strlen(text);
    int32_t tokens = static_cast<int32_t>((len + 3) / 4);
    return tokens > 0 ? tokens : 1;
}

/**
 * Generate a unique ID for generation tracking.
 */
static std::string generate_unique_id() {
    auto now = std::chrono::high_resolution_clock::now();
    auto epoch = now.time_since_epoch();
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(epoch).count();
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "vlm_gen_%lld", static_cast<long long>(ns));
    return std::string(buffer);
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
    size_t len = strlen(token);

    while (i < len && out < buf_size - 1) {
        if (token[i] == '<' && i + 1 < len && token[i + 1] == '|') {
            // Scan ahead for closing |>
            size_t end = i + 2;
            while (end < len) {
                if (token[end] == '|' && end + 1 < len && token[end + 1] == '>') {
                    // Found <|...|> — skip the entire special token
                    i = end + 2;
                    break;
                }
                end++;
            }
            if (end >= len) {
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
        const char* name = entry->d_name;
        size_t name_len = strlen(name);

        // Must end with .gguf (case-insensitive)
        if (name_len < 5) continue;
        const char* ext = name + name_len - 5;
        if (strcasecmp(ext, ".gguf") != 0) continue;

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
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_vlm_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create lifecycle manager
    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_VLM_MODEL;
    lifecycle_config.logger_category = "VLM.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, vlm_create_service,
                                               vlm_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    RAC_LOG_INFO(LOG_CAT, "VLM component created");

    return RAC_SUCCESS;
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

    // 3. Resolve model files within the directory
    char model_path[1024] = {};
    char mmproj_path[1024] = {};
    result = rac_vlm_resolve_model_files(model_folder, model_path, sizeof(model_path), mmproj_path,
                                         sizeof(mmproj_path));
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to resolve model files in: %s", model_folder);
        rac_model_info_free(model_info);
        return result;
    }

    // 4. Delegate to the existing load function
    const char* mmproj = mmproj_path[0] != '\0' ? mmproj_path : nullptr;
    const char* name = model_info->name ? model_info->name : model_id;

    RAC_LOG_INFO(LOG_CAT, "Loading VLM model by ID: %s (model=%s, mmproj=%s)", model_id, model_path,
                 mmproj ? mmproj : "none");

    result = rac_vlm_component_load_model(handle, model_path, mmproj, model_id, name);

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

    if (!token) return RAC_TRUE;

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
    std::lock_guard<std::mutex> lock(component->mtx);

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
