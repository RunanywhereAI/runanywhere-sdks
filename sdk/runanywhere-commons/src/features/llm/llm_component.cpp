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

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <mutex>
#include <random>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"
#include "rac/infrastructure/events/rac_events.h"

// v2 close-out Phase G-2 / BUG-STREAMING-001: pull in the canonical
// 13-field LLM stream emitter shared with rac_llm_proto_service.cpp.
// We invoke `rac::llm::dispatch_llm_stream_event()` once per token and
// once on terminal events so any collectors registered via
// rac_llm_set_stream_proto_callback() see the full decoded sequence.
// The symbol is a no-op when no callback has been registered.
#include "features/llm/rac_llm_stream_internal.h"

extern "C" void rac_lora_forget_component_state(rac_handle_t handle);

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

    /** Cancellation flag - set by cancel(), read by token callback without holding mtx */
    std::atomic<bool> cancel_requested{false};

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
    static thread_local std::mt19937 gen(std::random_device{}());
    std::uniform_int_distribution<uint32_t> dis;
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "gen_%08x%08x", dis(gen), dis(gen));
    return {buffer};
}

// =============================================================================
// EOS / SPECIAL TOKEN STRIPPING (CLUSTER-19 examples-react-native-004)
// =============================================================================

/**
 * Strip tokenizer-internal special tokens from a streamed LLM token before
 * the value reaches user callbacks or downstream proto subscribers.
 *
 * Backends occasionally leak end-of-utterance / end-of-text sentinels into
 * the streaming callback when the runtime swallow path missed them (notably
 * SmolVLM, Qwen-VL, Llama-3 — see B-RN-14-001 / CLUSTER-19). Without this
 * filter the angle-bracket artifacts (`<|im_end|>`, `<|eot_id|>`,
 * `<|endoftext|>`, `<eot>`, `<end_of_utterance>`) appear in chat UIs.
 *
 * Two pattern families are recognised:
 *   1. `<|TOKEN|>` — Qwen / Llama-3 / GPT-style pipe-wrapped sentinels.
 *      The scanner consumes everything between `<|` and the next `|>` so
 *      this naturally covers `im_end`, `eot_id`, `endoftext`, `im_start`,
 *      `vision_start`, `vision_end`, etc.
 *   2. Bare `<TOKEN>` sentinels — `<eot>`, `<end_of_utterance>`,
 *      `<endoftext>`, `<eos>`. Only the explicit allowlist is stripped so
 *      legitimate user content containing `<` is preserved.
 *
 * The cleaned output is written to @p buf and is guaranteed NUL-terminated
 * provided @p buf_size >= 1. The function returns @p buf for convenience —
 * if the entire token was a sentinel, @p buf points at the empty string.
 */
static const char* llm_strip_eos_tokens(const char* token, char* buf, size_t buf_size) {
    if (!buf || buf_size == 0) {
        return buf;
    }
    if (!token) {
        buf[0] = '\0';
        return buf;
    }

    // Bare-form sentinels matched as exact substrings. Keep the list short:
    // every additional entry costs an O(n*m) scan per token. Patterns must
    // not overlap (`<eos>` is a prefix of `<eos_id>` — not in this list).
    static const char* kBareSentinels[] = {
        "<end_of_utterance>",
        "<endoftext>",
        "<eot>",
        "<eos>",
    };
    constexpr size_t kBareCount = sizeof(kBareSentinels) / sizeof(kBareSentinels[0]);

    size_t out = 0;
    size_t i = 0;
    while (token[i] != '\0' && out + 1 < buf_size) {
        if (token[i] == '<' && token[i + 1] == '|') {
            // Pipe-wrapped form: skip everything through the next |> .
            size_t end = i + 2;
            while (token[end] != '\0') {
                if (token[end] == '|' && token[end + 1] == '>') {
                    i = end + 2;
                    break;
                }
                ++end;
            }
            if (token[end] == '\0') {
                // No closing |> in this chunk — copy `<` literally and
                // continue so a multi-chunk sentinel surfacing across two
                // callback invocations still appears (downstream gets one
                // partial chunk; this never produced the angle-bracket
                // artifact observed in the reports because the runtime
                // emits the full sentinel as a single token).
                buf[out++] = token[i++];
            }
            continue;
        }

        if (token[i] == '<') {
            bool stripped = false;
            for (size_t k = 0; k < kBareCount; ++k) {
                const char* needle = kBareSentinels[k];
                const size_t needle_len = strlen(needle);
                if (strncmp(token + i, needle, needle_len) == 0) {
                    i += needle_len;
                    stripped = true;
                    break;
                }
            }
            if (stripped) {
                continue;
            }
        }

        buf[out++] = token[i++];
    }
    buf[out] = '\0';
    return buf;
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

    RAC_LOG_INFO("LLM.Component", "LLM component configured");

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

    // Acquire component mutex to serialize against in-flight operations.
    // lifecycle_destroy -> unload will block until any acquired services are released.
    {
        std::lock_guard<std::mutex> lock(component->mtx);
        if (component->lifecycle) {
            rac_lifecycle_destroy(component->lifecycle);
            component->lifecycle = nullptr;
        }
    }

    // B-FL-5-001 fix: clear any lingering proto-stream callback registration
    // keyed by this component handle BEFORE freeing the memory. If the
    // allocator later hands the same address back to a fresh component
    // (rac_llm_component_create), the new component would otherwise inherit
    // the previous slot's stale seq counter / callback pointer — corrupting
    // the LLMStreamEvent wire seq sequence and causing the Flutter Java
    // protobuf decoder to throw "end-group tag did not match" on the first
    // generate after a model switch.
    rac_llm_unset_stream_proto_callback(handle);
    // pass2-syn-001-followup-llm: spin-wait for any in-flight
    // dispatch_llm_stream_event() invocation on another thread before freeing
    // the component. Mirrors rac_vlm_component_destroy:350.
    rac_llm_proto_quiesce();
    rac_lora_forget_component_state(handle);

    RAC_LOG_INFO("LLM.Component", "LLM component destroyed");

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

    // B-FL-5-001 v2 fix: clear any prior proto-stream callback registration
    // BEFORE re-creating the internal service for a new model. Without this,
    // the wire-seq counter in g_slots() retains its prior value and corrupts
    // the proto stream on the very first generate after a model switch (the
    // load_model path elides destroy → original B-FL-5-001 fix in destroy()
    // never fires for handle reuse).
    rac_llm_unset_stream_proto_callback(handle);
    // pass2-syn-001-followup-llm: drain any in-flight dispatcher invocation
    // bound to the previous model before swapping in the new service. The
    // unset above clears the slot but a concurrent dispatcher that already
    // copied the slot keeps running until it finishes; spin-wait until that
    // pending invocation has returned so the user_data captured by the
    // previous registration can be safely freed.
    rac_llm_proto_quiesce();

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

    double load_duration_ms =
        static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - load_start)
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
        rac_lora_forget_component_state(handle);
    }

    return result;
}

extern "C" rac_result_t rac_llm_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_result_t result = rac_lifecycle_unload(component->lifecycle);
    if (result == RAC_SUCCESS) {
        rac_lora_forget_component_state(handle);
    }
    return result;
}

extern "C" rac_result_t rac_llm_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Mirrors Swift's: await managedLifecycle.reset()
    rac_result_t result = rac_lifecycle_reset(component->lifecycle);
    if (result == RAC_SUCCESS) {
        rac_lora_forget_component_state(handle);
    }
    return result;
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
        RAC_LOG_ERROR("LLM.Component", "No model loaded - cannot generate");

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
        RAC_LOG_ERROR("LLM.Component", "Generation failed");
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
    RAC_LOG_DEBUG("LLM.Component", "Backend returned prompt_tokens=%d, completion_tokens=%d",
                  out_result->prompt_tokens, out_result->completion_tokens);

    if (out_result->prompt_tokens <= 0) {
        out_result->prompt_tokens = estimate_tokens(prompt);
        RAC_LOG_DEBUG("LLM.Component", "Using estimated prompt_tokens=%d",
                      out_result->prompt_tokens);
    }
    if (out_result->completion_tokens <= 0) {
        out_result->completion_tokens = estimate_tokens(out_result->text);
        RAC_LOG_DEBUG("LLM.Component", "Using estimated completion_tokens=%d",
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

    RAC_LOG_INFO("LLM.Component", "Generation completed");

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

    std::atomic<bool>* cancel_flag;
    // Benchmark timing (optional, NULL when not benchmarking)
    rac_benchmark_timing_t* timing_out;

    // v2 close-out Phase G-2: component handle for the proto-byte stream
    // dispatcher. Each delivered token fires a LLMStreamEvent to any
    // collector registered via rac_llm_set_stream_proto_callback().
    rac_handle_t component_handle;
};

/**
 * Internal token callback that wraps user callback and tracks metrics.
 *
 * CLUSTER-19 examples-react-native-004: every emitted token is run through
 * `llm_strip_eos_tokens()` before it reaches the user callback or the
 * proto stream dispatcher. Backends occasionally leak EOS sentinels
 * (`<|im_end|>`, `<|eot_id|>`, `<end_of_utterance>`, …) which the example
 * apps used to strip locally; the regex-based example workaround in
 * `useVLMCamera.ts` is now obsolete because commons emits cleaned tokens
 * directly.
 */
static rac_bool_t llm_stream_token_callback(const char* token, void* user_data) {
    auto* ctx = reinterpret_cast<llm_stream_context*>(user_data);

    if (ctx->cancel_flag && ctx->cancel_flag->load(std::memory_order_relaxed)) {
        return RAC_FALSE;
    }

    // Strip tokenizer-internal sentinels before any caller observes the
    // chunk. The stack-allocated buffer comfortably fits a single decoded
    // token; backends emit at most a few dozen bytes per callback.
    char cleaned_buf[512];
    const char* cleaned = llm_strip_eos_tokens(token, cleaned_buf, sizeof(cleaned_buf));
    const bool cleaned_empty = (cleaned[0] == '\0');

    // Track first token time and emit first token event only for the first
    // non-empty cleaned chunk so TTFT does not get charged to a leading
    // sentinel that the user never observes.
    if (!ctx->first_token_recorded && !cleaned_empty) {
        ctx->first_token_recorded = true;
        ctx->first_token_time = std::chrono::steady_clock::now();

        // Record t4 (first token) for benchmark timing
        if (ctx->timing_out != nullptr) {
            ctx->timing_out->t4_first_token_ms = rac_monotonic_now_ms();
        }

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

    // Accumulate text and track token count. Only the cleaned text reaches
    // ctx->full_text — the raw backend token is intentionally discarded so
    // downstream consumers (e.g. complete_callback's final_result.text)
    // never see sentinel artifacts either.
    if (!cleaned_empty) {
        ctx->full_text += cleaned;
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

    // v2 close-out Phase G-2: fan-out the token as an LLMStreamEvent to
    // any proto-byte subscribers. `is_final=false` on every per-token
    // event; the terminal is_final=true event is emitted by the
    // generate_stream() caller once the engine returns (below). Pure-
    // sentinel chunks are suppressed entirely so subscribers don't have
    // to filter empty events themselves.
    if (!cleaned_empty) {
        rac::llm::dispatch_llm_stream_event(ctx->component_handle, cleaned,
                                            /*is_final*/ false,
                                            /*kind*/ 1 /* ANSWER */,
                                            /*token_id*/ 0,
                                            /*logprob*/ 0.0f,
                                            /*finish_reason*/ nullptr,
                                            /*error_message*/ nullptr);
    }

    // Forward only non-empty cleaned tokens to the user callback so the
    // example/SDK rendering layer never has to strip these sentinels.
    if (!cleaned_empty && ctx->token_callback) {
        return ctx->token_callback(cleaned, ctx->user_data);
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

    component->cancel_requested.store(false, std::memory_order_relaxed);

    // Generate unique ID for this generation
    std::string generation_id = generate_unique_id();
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "No model loaded - cannot generate stream");

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

        rac::llm::dispatch_llm_stream_event(handle, "", /*is_final*/ true, 0, 0, 0.0f,
                                            /*finish_reason*/ "error",
                                            /*error_message*/ "No model loaded");

        if (error_callback) {
            error_callback(result, "No model loaded", user_data);
        }
        return result;
    }

    // Check if streaming is supported
    rac_llm_info_t info;
    result = rac_llm_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        RAC_LOG_ERROR("LLM.Component", "Streaming not supported");

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

        rac::llm::dispatch_llm_stream_event(handle, "", /*is_final*/ true, 0, 0, 0.0f,
                                            /*finish_reason*/ "error",
                                            /*error_message*/ "Streaming not supported");

        if (error_callback) {
            error_callback(RAC_ERROR_NOT_SUPPORTED, "Streaming not supported", user_data);
        }
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO("LLM.Component", "Starting streaming generation");

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
    ctx.cancel_flag = &component->cancel_requested;
    ctx.timing_out = nullptr;  // No benchmark timing for regular generate_stream
    ctx.component_handle = handle;
    // Pre-allocate to avoid repeated reallocations during streaming
    ctx.full_text.reserve(2048);

    // Perform streaming generation
    result = rac_llm_generate_stream(service, prompt, effective_options, llm_stream_token_callback,
                                     &ctx);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Streaming generation failed");
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

        // v2 close-out Phase G-2: terminal error event on the proto stream.
        rac::llm::dispatch_llm_stream_event(handle,
                                            /*token*/ "",
                                            /*is_final*/ true,
                                            /*kind*/ 0 /* UNSPECIFIED */,
                                            /*token_id*/ 0,
                                            /*logprob*/ 0.0f,
                                            /*finish_reason*/ "error",
                                            /*error_message*/ "Streaming generation failed");

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
    if (!final_result.text) {
        RAC_LOG_ERROR("LLM.Component", "Failed to allocate result text");
        if (error_callback) {
            error_callback(RAC_ERROR_OUT_OF_MEMORY, "Failed to allocate result text", user_data);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    final_result.prompt_tokens = ctx.prompt_tokens;
    final_result.completion_tokens =
        ctx.token_count > 0 ? ctx.token_count
                            : (ctx.full_text.empty() ? 0 : estimate_tokens(ctx.full_text.c_str()));
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

    // v2 close-out Phase G-2: terminal success event on the proto stream.
    // BUG-STREAMING-003: emit finish_reason="length" when max_tokens was exhausted
    // (matches OpenAI chat.completions contract — proto is modeled after it).
    const char* finish_reason_str = "stop";
    if (component->cancel_requested.load()) {
        finish_reason_str = "cancelled";
    } else if (effective_options->max_tokens > 0 &&
               ctx.token_count >= effective_options->max_tokens) {
        finish_reason_str = "length";
    }
    rac::llm::dispatch_llm_stream_event(handle,
                                        /*token*/ "",
                                        /*is_final*/ true,
                                        /*kind*/ 1 /* ANSWER */,
                                        /*token_id*/ 0,
                                        /*logprob*/ 0.0f,
                                        /*finish_reason*/ finish_reason_str,
                                        /*error_message*/ nullptr);

    // Free the duplicated text
    free(final_result.text);

    RAC_LOG_INFO("LLM.Component", "Streaming generation completed");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_llm_component_generate_stream_with_timing(
    rac_handle_t handle, const char* prompt, const rac_llm_options_t* options,
    rac_llm_component_token_callback_fn token_callback,
    rac_llm_component_complete_callback_fn complete_callback,
    rac_llm_component_error_callback_fn error_callback, void* user_data,
    rac_benchmark_timing_t* timing_out) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!prompt)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Initialize timing if provided
    if (timing_out != nullptr) {
        rac_benchmark_timing_init(timing_out);
        // Record t0 (request start) - first thing after validation
        timing_out->t0_request_start_ms = rac_monotonic_now_ms();
    }

    // Generate unique ID for this generation
    std::string generation_id = generate_unique_id();
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "No model loaded - cannot generate stream");

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

        if (timing_out != nullptr) {
            timing_out->status = RAC_BENCHMARK_STATUS_ERROR;
            timing_out->error_code = result;
            timing_out->t6_request_end_ms = rac_monotonic_now_ms();
        }

        if (error_callback) {
            error_callback(result, "No model loaded", user_data);
        }
        return result;
    }

    // Check if streaming is supported
    rac_llm_info_t info;
    result = rac_llm_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        RAC_LOG_ERROR("LLM.Component", "Streaming not supported");

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

        if (timing_out != nullptr) {
            timing_out->status = RAC_BENCHMARK_STATUS_ERROR;
            timing_out->error_code = RAC_ERROR_NOT_SUPPORTED;
            timing_out->t6_request_end_ms = rac_monotonic_now_ms();
        }

        if (error_callback) {
            error_callback(RAC_ERROR_NOT_SUPPORTED, "Streaming not supported", user_data);
        }
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO("LLM.Component", "Starting streaming generation with timing");

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
    ctx.timing_out = timing_out;  // Pass timing for t4 capture in callback
    ctx.cancel_flag = &component->cancel_requested;
    ctx.component_handle = handle;

    // Perform streaming generation with timing
    // Note: Backend timing (t2, t3, t5) will be captured if backend supports it
    result = rac_llm_generate_stream_with_timing(service, prompt, effective_options,
                                                 llm_stream_token_callback, &ctx, timing_out);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Streaming generation failed");
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

        if (timing_out != nullptr) {
            timing_out->status = RAC_BENCHMARK_STATUS_ERROR;
            timing_out->error_code = result;
            timing_out->t6_request_end_ms = rac_monotonic_now_ms();
        }

        // v2 close-out Phase G-2: terminal error event on the proto stream.
        rac::llm::dispatch_llm_stream_event(handle, "", /*is_final*/ true, /*kind*/ 0, 0, 0.0f,
                                            /*finish_reason*/ "error",
                                            /*error_message*/ "Streaming generation failed");

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
    if (final_result.text == nullptr) {
        RAC_LOG_ERROR("LLM.Component", "strdup failed for result text");
        if (timing_out != nullptr) {
            timing_out->status = RAC_BENCHMARK_STATUS_ERROR;
            timing_out->error_code = RAC_ERROR_OUT_OF_MEMORY;
            timing_out->t6_request_end_ms = rac_monotonic_now_ms();
        }
        if (error_callback) {
            error_callback(RAC_ERROR_OUT_OF_MEMORY, "Failed to allocate result text", user_data);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Use actual backend token counts if available, fall back to estimates
    if (timing_out != nullptr && timing_out->prompt_tokens > 0) {
        final_result.prompt_tokens = timing_out->prompt_tokens;
    } else {
        final_result.prompt_tokens = ctx.prompt_tokens;
    }

    if (timing_out != nullptr && timing_out->output_tokens > 0) {
        final_result.completion_tokens = timing_out->output_tokens;
    } else {
        final_result.completion_tokens = estimate_tokens(ctx.full_text.c_str());
    }

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

    // Record t6 (request end) before complete callback.
    // Backfill prompt/output tokens when backend didn't populate them (fallback path)
    // so downstream decode-TPS and CSV/JSON stats are computed from estimates, not zero.
    if (timing_out != nullptr) {
        if (timing_out->prompt_tokens <= 0) {
            timing_out->prompt_tokens = final_result.prompt_tokens;
        }
        if (timing_out->output_tokens <= 0) {
            timing_out->output_tokens = final_result.completion_tokens;
        }
        timing_out->t6_request_end_ms = rac_monotonic_now_ms();
        timing_out->status = RAC_BENCHMARK_STATUS_SUCCESS;
        timing_out->error_code = RAC_SUCCESS;
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

    // v2 close-out Phase G-2: terminal success event on the proto stream.
    // BUG-STREAMING-003: emit finish_reason="length" when max_tokens was exhausted
    // (matches OpenAI chat.completions contract — proto is modeled after it).
    const char* finish_reason_str_t = "stop";
    if (component->cancel_requested.load()) {
        finish_reason_str_t = "cancelled";
    } else if (effective_options->max_tokens > 0 &&
               ctx.token_count >= effective_options->max_tokens) {
        finish_reason_str_t = "length";
    }
    rac::llm::dispatch_llm_stream_event(handle, "", /*is_final*/ true, /*kind*/ 1 /* ANSWER */, 0,
                                        0.0f,
                                        /*finish_reason*/ finish_reason_str_t,
                                        /*error_message*/ nullptr);

    // Free the duplicated text
    free(final_result.text);

    RAC_LOG_INFO("LLM.Component", "Streaming generation with timing completed");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_llm_component_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);

    // Set atomic cancel flag so the streaming token callback can observe it
    // without holding component->mtx (which generate_stream is holding).
    component->cancel_requested.store(true, std::memory_order_relaxed);

    // Use acquire/release to pin the service for the duration of the cancel call,
    // preventing use-after-free if destroy races with cancel.
    // Do NOT acquire component->mtx — generate_stream() holds it during streaming.
    rac_handle_t service = nullptr;
    rac_result_t acq = rac_lifecycle_acquire_service(component->lifecycle, &service);
    if (acq == RAC_SUCCESS && service) {
        rac_llm_cancel(service);
        rac_lifecycle_release_service(component->lifecycle);
    }

    RAC_LOG_INFO("LLM.Component", "Generation cancellation requested");

    return RAC_SUCCESS;
}

// =============================================================================
// LORA ADAPTER API
// =============================================================================

extern "C" rac_result_t rac_llm_component_load_lora(rac_handle_t handle, const char* adapter_path,
                                                    float scale) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        RAC_LOG_ERROR("LLM.Component", "Cannot load LoRA adapter: no model loaded");
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
        RAC_LOG_ERROR("LLM.Component", "Cannot remove LoRA adapter: no model loaded");
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

    // Verify file exists and is a valid GGUF
    {
        std::ifstream file(adapter_path, std::ios::binary);
        if (!file.is_open()) {
            *out_error = rac_strdup("Adapter file not found");
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        uint32_t magic = 0;
        file.read(reinterpret_cast<char*>(&magic), sizeof(magic));
        if (!file || magic != 0x46554747u) {  // "GGUF" in little-endian
            *out_error = rac_strdup("Adapter file is not a valid GGUF file");
            return RAC_ERROR_INVALID_ARGUMENT;
        }
    }

    // Verify the backend supports LoRA
    auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
    if (!llm_service->ops || !llm_service->ops->load_lora) {
        *out_error = rac_strdup("Backend does not support LoRA adapters");
        return RAC_ERROR_NOT_SUPPORTED;
    }

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
