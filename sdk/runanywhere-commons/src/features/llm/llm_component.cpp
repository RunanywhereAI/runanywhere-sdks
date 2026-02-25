/**
 * @file llm_component.cpp
 * @brief LLM Capability Component Implementation
 *
 * C++ port of Swift's LLMCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/LLM/LLMCapability.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/infrastructure/events/rac_events.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

/**
 * Internal LLM component state.
 * Mirrors Swift's LLMCapability actor state.
 */
struct rac_llm_component {
    /** Lifecycle manager handle */
    rac_handle_t lifecycle;

    /** Current configuration */
    rac_llm_config_t config;

    /** Default generation options based on config */
    rac_llm_options_t default_options;

    /** Mutex for thread safety */
    std::mutex mtx;

    /** Resolved inference framework (defaults to LlamaCPP, the primary LLM backend) */
    rac_inference_framework_t actual_framework;

    rac_llm_component() : lifecycle(nullptr), actual_framework(RAC_FRAMEWORK_LLAMACPP) {
        // Initialize with defaults - matches rac_llm_types.h rac_llm_config_t
        config = RAC_LLM_CONFIG_DEFAULT;

        default_options = RAC_LLM_OPTIONS_DEFAULT;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * Simple token estimation (~4 chars per token).
 * Mirrors Swift's token estimation in LLMCapability.
 */
static int32_t estimate_tokens(const char* text) {
    if (!text)
        return 1;
    size_t len = strlen(text);
    int32_t tokens = static_cast<int32_t>((len + 3) / 4);
    return tokens > 0 ? tokens : 1;  // Minimum 1 token
}

/**
 * Generate a unique ID for generation tracking.
 */
static std::string generate_unique_id() {
    auto now = std::chrono::high_resolution_clock::now();
    auto epoch = now.time_since_epoch();
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(epoch).count();
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "gen_%lld", static_cast<long long>(ns));
    return std::string(buffer);
}

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

/**
 * Service creation callback for lifecycle manager.
 * Creates and initializes the LLM service.
 */
static rac_result_t llm_create_service(const char* model_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    RAC_LOG_INFO("LLM.Component", "Creating LLM service for model: %s", model_id ? model_id : "");

    // Create LLM service
    rac_result_t result = rac_llm_create(model_id, out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Failed to create LLM service: %d", result);
        return result;
    }

    // Initialize with model path
    result = rac_llm_initialize(*out_service, model_id);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Failed to initialize LLM service: %d", result);
        rac_llm_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    RAC_LOG_INFO("LLM.Component", "LLM service created successfully");
    return RAC_SUCCESS;
}

/**
 * Service destruction callback for lifecycle manager.
 * Cleans up the LLM service.
 */
static void llm_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        RAC_LOG_DEBUG("LLM.Component", "Destroying LLM service");
        rac_llm_cleanup(service);
        rac_llm_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_llm_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_llm_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create lifecycle manager
    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_LLM_MODEL;
    lifecycle_config.logger_category = "LLM.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, llm_create_service,
                                               llm_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    RAC_LOG_INFO("LLM.Component", "LLM component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_llm_component_configure(rac_handle_t handle,
                                                    const rac_llm_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Copy configuration
    // Mirrors Swift's: self.config = config
    component->config = *config;

    // Resolve actual framework: if caller explicitly set one (not UNKNOWN=99), use it;
    // otherwise keep the default (RAC_FRAMEWORK_LLAMACPP for LLM components)
    if (config->preferred_framework != static_cast<int32_t>(RAC_FRAMEWORK_UNKNOWN)) {
        component->actual_framework =
            static_cast<rac_inference_framework_t>(config->preferred_framework);
    }

    // Update default options based on config
    if (config->max_tokens > 0) {
        component->default_options.max_tokens = config->max_tokens;
    }
    if (config->system_prompt) {
        component->default_options.system_prompt = config->system_prompt;
    }

    log_info("LLM.Component", "LLM component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_llm_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_llm_component_get_model_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_llm_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);

    // Destroy lifecycle manager (will cleanup service if loaded)
    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    log_info("LLM.Component", "LLM component destroyed");

    delete component;
}

// =============================================================================
// MODEL LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_llm_component_load_model(rac_handle_t handle, const char* model_path,
                                                     const char* model_id, const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Emit model load started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_MODEL_LOAD_STARTED;
        event.data.llm_model.model_id = model_id;
        event.data.llm_model.model_name = model_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_LLM_MODEL_LOAD_STARTED, &event);
    }

    auto load_start = std::chrono::steady_clock::now();

    // Delegate to lifecycle manager with separate path, model_id, and model_name
    rac_handle_t service = nullptr;
    rac_result_t result =
        rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);

    double load_duration_ms = static_cast<double>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() -
                                                              load_start)
            .count());

    if (result != RAC_SUCCESS) {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_MODEL_LOAD_FAILED;
        event.data.llm_model.model_id = model_id;
        event.data.llm_model.model_name = model_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = result;
        event.data.llm_model.error_message = "Model load failed";
        rac_analytics_event_emit(RAC_EVENT_LLM_MODEL_LOAD_FAILED, &event);
    } else {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_MODEL_LOAD_COMPLETED;
        event.data.llm_model.model_id = model_id;
        event.data.llm_model.model_name = model_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_LLM_MODEL_LOAD_COMPLETED, &event);
    }

    return result;
}

extern "C" rac_result_t rac_llm_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_llm_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Mirrors Swift's: await managedLifecycle.reset()
    return rac_lifecycle_reset(component->lifecycle);
}

// =============================================================================
// GENERATION API
// =============================================================================

extern "C" rac_result_t rac_llm_component_generate(rac_handle_t handle, const char* prompt,
                                                   const rac_llm_options_t* options,
                                                   rac_llm_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!prompt)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Generate unique ID for this generation
    std::string generation_id = generate_unique_id();

    // Get model ID and name from lifecycle manager
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("LLM.Component", "No model loaded - cannot generate");

        // Emit generation failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_FAILED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.error_code = result;
        event.data.llm_generation.error_message = "No model loaded";
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_FAILED, &event);

        return result;
    }

    // Use provided options or defaults
    const rac_llm_options_t* effective_options = options ? options : &component->default_options;

    // Get service info for context_length
    rac_llm_info_t service_info = {};
    int32_t context_length = 0;
    if (rac_llm_get_info(service, &service_info) == RAC_SUCCESS) {
        context_length = service_info.context_length;
    }

    // Emit generation started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_STARTED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.is_streaming = RAC_FALSE;
        event.data.llm_generation.framework = component->actual_framework;
        event.data.llm_generation.temperature = effective_options->temperature;
        event.data.llm_generation.max_tokens = effective_options->max_tokens;
        event.data.llm_generation.context_length = context_length;
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_STARTED, &event);
    }

    auto start_time = std::chrono::steady_clock::now();

    // Perform generation
    result = rac_llm_generate(service, prompt, effective_options, out_result);

    if (result != RAC_SUCCESS) {
        log_error("LLM.Component", "Generation failed");
        rac_lifecycle_track_error(component->lifecycle, result, "generate");

        // Emit generation failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_FAILED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.error_code = result;
        event.data.llm_generation.error_message = "Generation failed";
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_FAILED, &event);

        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    int64_t total_time_ms = duration.count();

    // Update result metrics
    // Use actual token counts from backend if available, otherwise estimate
    log_debug("LLM.Component", "Backend returned prompt_tokens=%d, completion_tokens=%d",
              out_result->prompt_tokens, out_result->completion_tokens);

    if (out_result->prompt_tokens <= 0) {
        out_result->prompt_tokens = estimate_tokens(prompt);
        log_debug("LLM.Component", "Using estimated prompt_tokens=%d", out_result->prompt_tokens);
    }
    if (out_result->completion_tokens <= 0) {
        out_result->completion_tokens = estimate_tokens(out_result->text);
        log_debug("LLM.Component", "Using estimated completion_tokens=%d",
                  out_result->completion_tokens);
    }
    out_result->total_tokens = out_result->prompt_tokens + out_result->completion_tokens;
    out_result->total_time_ms = total_time_ms;
    out_result->time_to_first_token_ms = 0;  // Non-streaming: no TTFT

    double tokens_per_second = 0.0;
    if (total_time_ms > 0) {
        tokens_per_second = static_cast<double>(out_result->completion_tokens) /
                            (static_cast<double>(total_time_ms) / 1000.0);
        out_result->tokens_per_second = static_cast<float>(tokens_per_second);
    }

    log_info("LLM.Component", "Generation completed");

    // Emit generation completed event
    // Use estimated input_tokens for telemetry consistency across platforms
    // (some backends return actual tokenized count including chat template,
    // others return 0 - estimation ensures consistent user-facing metrics)
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_COMPLETED;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.input_tokens = estimate_tokens(prompt);
        event.data.llm_generation.output_tokens = out_result->completion_tokens;
        event.data.llm_generation.duration_ms = static_cast<double>(total_time_ms);
        event.data.llm_generation.tokens_per_second = tokens_per_second;
        event.data.llm_generation.is_streaming = RAC_FALSE;
        event.data.llm_generation.time_to_first_token_ms = 0;
        event.data.llm_generation.framework = component->actual_framework;
        event.data.llm_generation.temperature = effective_options->temperature;
        event.data.llm_generation.max_tokens = effective_options->max_tokens;
        event.data.llm_generation.context_length = context_length;
        event.data.llm_generation.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_COMPLETED, &event);
    }

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_llm_component_supports_streaming(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        return RAC_FALSE;
    }

    rac_llm_info_t info;
    rac_result_t result = rac_llm_get_info(service, &info);
    if (result != RAC_SUCCESS) {
        return RAC_FALSE;
    }

    return info.supports_streaming;
}

/**
 * Internal structure for streaming context.
 */
struct llm_stream_context {
    rac_llm_component_token_callback_fn token_callback;
    rac_llm_component_complete_callback_fn complete_callback;
    rac_llm_component_error_callback_fn error_callback;
    void* user_data;

    // Metrics tracking
    std::chrono::steady_clock::time_point start_time;
    std::chrono::steady_clock::time_point first_token_time;
    bool first_token_recorded;
    std::string full_text;
    int32_t prompt_tokens;

    // Analytics event data
    std::string generation_id;
    const char* model_id;
    const char* model_name;
    rac_inference_framework_t framework;
    float temperature;
    int32_t max_tokens;
    int32_t token_count;  // Track tokens for streaming updates
};

/**
 * Internal token callback that wraps user callback and tracks metrics.
 */
static rac_bool_t llm_stream_token_callback(const char* token, void* user_data) {
    auto* ctx = reinterpret_cast<llm_stream_context*>(user_data);

    // Track first token time and emit first token event
    if (!ctx->first_token_recorded) {
        ctx->first_token_recorded = true;
        ctx->first_token_time = std::chrono::steady_clock::now();

        // Calculate TTFT
        auto ttft_duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            ctx->first_token_time - ctx->start_time);
        double ttft_ms = static_cast<double>(ttft_duration.count());

        // Emit first token event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_FIRST_TOKEN;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = ctx->generation_id.c_str();
        event.data.llm_generation.model_id = ctx->model_id;
        event.data.llm_generation.model_name = ctx->model_name;
        event.data.llm_generation.time_to_first_token_ms = ttft_ms;
        event.data.llm_generation.framework = ctx->framework;
        rac_analytics_event_emit(RAC_EVENT_LLM_FIRST_TOKEN, &event);
    }

    // Accumulate text and track token count
    if (token) {
        ctx->full_text += token;
        ctx->token_count++;

        // Emit streaming update event (every 10 tokens to avoid spam)
        if (ctx->token_count % 10 == 0) {
            rac_analytics_event_data_t event = {};
            event.type = RAC_EVENT_LLM_STREAMING_UPDATE;
            event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
            event.data.llm_generation.generation_id = ctx->generation_id.c_str();
            event.data.llm_generation.output_tokens = ctx->token_count;
            rac_analytics_event_emit(RAC_EVENT_LLM_STREAMING_UPDATE, &event);
        }
    }

    // Call user callback
    if (ctx->token_callback) {
        return ctx->token_callback(token, ctx->user_data);
    }

    return RAC_TRUE;  // Continue by default
}

extern "C" rac_result_t rac_llm_component_generate_stream(
    rac_handle_t handle, const char* prompt, const rac_llm_options_t* options,
    rac_llm_component_token_callback_fn token_callback,
    rac_llm_component_complete_callback_fn complete_callback,
    rac_llm_component_error_callback_fn error_callback, void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!prompt)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Generate unique ID for this generation
    std::string generation_id = generate_unique_id();
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("LLM.Component", "No model loaded - cannot generate stream");

        // Emit generation failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_FAILED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.error_code = result;
        event.data.llm_generation.error_message = "No model loaded";
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_FAILED, &event);

        if (error_callback) {
            error_callback(result, "No model loaded", user_data);
        }
        return result;
    }

    // Check if streaming is supported
    rac_llm_info_t info;
    result = rac_llm_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        log_error("LLM.Component", "Streaming not supported");

        // Emit generation failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_FAILED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.error_code = RAC_ERROR_NOT_SUPPORTED;
        event.data.llm_generation.error_message = "Streaming not supported";
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_FAILED, &event);

        if (error_callback) {
            error_callback(RAC_ERROR_NOT_SUPPORTED, "Streaming not supported", user_data);
        }
        return RAC_ERROR_NOT_SUPPORTED;
    }

    log_info("LLM.Component", "Starting streaming generation");

    // Get context_length from service info
    int32_t context_length = info.context_length;

    // Use provided options or defaults
    const rac_llm_options_t* effective_options = options ? options : &component->default_options;

    // Emit generation started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_STARTED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.is_streaming = RAC_TRUE;
        event.data.llm_generation.framework = component->actual_framework;
        event.data.llm_generation.temperature = effective_options->temperature;
        event.data.llm_generation.max_tokens = effective_options->max_tokens;
        event.data.llm_generation.context_length = context_length;
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_STARTED, &event);
    }

    // Setup streaming context
    llm_stream_context ctx;
    ctx.token_callback = token_callback;
    ctx.complete_callback = complete_callback;
    ctx.error_callback = error_callback;
    ctx.user_data = user_data;
    ctx.start_time = std::chrono::steady_clock::now();
    ctx.first_token_recorded = false;
    ctx.prompt_tokens = estimate_tokens(prompt);
    ctx.generation_id = generation_id;
    ctx.model_id = model_id;
    ctx.model_name = model_name;
    ctx.framework = component->actual_framework;
    ctx.temperature = effective_options->temperature;
    ctx.max_tokens = effective_options->max_tokens;
    ctx.token_count = 0;

    // Perform streaming generation
    result = rac_llm_generate_stream(service, prompt, effective_options, llm_stream_token_callback,
                                     &ctx);

    if (result != RAC_SUCCESS) {
        log_error("LLM.Component", "Streaming generation failed");
        rac_lifecycle_track_error(component->lifecycle, result, "generateStream");

        // Emit generation failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_FAILED;
        event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.error_code = result;
        event.data.llm_generation.error_message = "Streaming generation failed";
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_FAILED, &event);

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

    rac_llm_result_t final_result = {};
    final_result.text = strdup(ctx.full_text.c_str());
    final_result.prompt_tokens = ctx.prompt_tokens;
    final_result.completion_tokens = estimate_tokens(ctx.full_text.c_str());
    final_result.total_tokens = final_result.prompt_tokens + final_result.completion_tokens;
    final_result.total_time_ms = total_time_ms;

    double ttft_ms = 0.0;
    // Calculate TTFT
    if (ctx.first_token_recorded) {
        auto ttft_duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            ctx.first_token_time - ctx.start_time);
        final_result.time_to_first_token_ms = ttft_duration.count();
        ttft_ms = static_cast<double>(ttft_duration.count());
    }

    // Calculate tokens per second
    double tokens_per_second = 0.0;
    if (final_result.total_time_ms > 0) {
        tokens_per_second = static_cast<double>(final_result.completion_tokens) /
                            (static_cast<double>(final_result.total_time_ms) / 1000.0);
        final_result.tokens_per_second = static_cast<float>(tokens_per_second);
    }

    if (complete_callback) {
        complete_callback(&final_result, user_data);
    }

    // Emit generation completed event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_LLM_GENERATION_COMPLETED;
        event.data.llm_generation.generation_id = generation_id.c_str();
        event.data.llm_generation.model_id = model_id;
        event.data.llm_generation.model_name = model_name;
        event.data.llm_generation.input_tokens = final_result.prompt_tokens;
        event.data.llm_generation.output_tokens = final_result.completion_tokens;
        event.data.llm_generation.duration_ms = static_cast<double>(total_time_ms);
        event.data.llm_generation.tokens_per_second = tokens_per_second;
        event.data.llm_generation.is_streaming = RAC_TRUE;
        event.data.llm_generation.time_to_first_token_ms = ttft_ms;
        event.data.llm_generation.framework = component->actual_framework;
        event.data.llm_generation.temperature = effective_options->temperature;
        event.data.llm_generation.max_tokens = effective_options->max_tokens;
        event.data.llm_generation.context_length = context_length;
        event.data.llm_generation.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_COMPLETED, &event);
    }

    // Free the duplicated text
    free(final_result.text);

    log_info("LLM.Component", "Streaming generation completed");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_llm_component_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (service) {
        rac_llm_cancel(service);
    }

    log_info("LLM.Component", "Generation cancellation requested");

    return RAC_SUCCESS;
}

// =============================================================================
// LORA ADAPTER API
// =============================================================================

extern "C" rac_result_t rac_llm_component_load_lora(rac_handle_t handle,
                                                     const char* adapter_path,
                                                     float scale) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        log_error("LLM.Component", "Cannot load LoRA adapter: no model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    // Dispatch through vtable (backend-agnostic)
    auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
    if (!llm_service->ops || !llm_service->ops->load_lora)
        return RAC_ERROR_NOT_SUPPORTED;
    return llm_service->ops->load_lora(llm_service->impl, adapter_path, scale);
}

extern "C" rac_result_t rac_llm_component_remove_lora(rac_handle_t handle,
                                                       const char* adapter_path) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        log_error("LLM.Component", "Cannot remove LoRA adapter: no model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
    if (!llm_service->ops || !llm_service->ops->remove_lora)
        return RAC_ERROR_NOT_SUPPORTED;
    return llm_service->ops->remove_lora(llm_service->impl, adapter_path);
}

extern "C" rac_result_t rac_llm_component_clear_lora(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        return RAC_SUCCESS;  // No service = no adapters to clear
    }

    auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
    if (!llm_service->ops || !llm_service->ops->clear_lora)
        return RAC_ERROR_NOT_SUPPORTED;
    return llm_service->ops->clear_lora(llm_service->impl);
}

extern "C" rac_result_t rac_llm_component_get_lora_info(rac_handle_t handle,
                                                         char** out_json) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_json)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        log_error("LLM.Component", "Cannot get LoRA info: no model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
    if (!llm_service->ops || !llm_service->ops->get_lora_info)
        return RAC_ERROR_NOT_SUPPORTED;
    return llm_service->ops->get_lora_info(llm_service->impl, out_json);
}

extern "C" rac_result_t rac_llm_component_check_lora_compat(rac_handle_t handle,
                                                              const char* adapter_path,
                                                              char** out_error) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!adapter_path || !out_error)
        return RAC_ERROR_INVALID_ARGUMENT;

    *out_error = nullptr;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        *out_error = rac_strdup("No model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    // Check if the adapter file path is non-empty
    if (strlen(adapter_path) == 0) {
        *out_error = rac_strdup("Empty adapter path");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Basic pre-check: verify the backend supports LoRA at all
    auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
    if (!llm_service->ops || !llm_service->ops->load_lora) {
        *out_error = rac_strdup("Backend does not support LoRA adapters");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    // Adapter path and backend both valid - considered compatible
    return RAC_SUCCESS;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_llm_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_llm_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}
