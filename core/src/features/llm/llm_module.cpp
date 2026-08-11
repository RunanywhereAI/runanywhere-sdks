/**
 * @file llm_module.cpp
 * @brief Unified LLM feature module.
 *
 * W4 component unification: merges the former
 *   - llm_component.cpp        (legacy handle-based component path; mirrors
 *                               Swift's LLMCapability.swift)
 *   - rac_llm_proto_service.cpp (lifecycle-owned handle-less generated-proto
 *                               C ABI: rac_llm_generate_proto / _stream / cancel)
 * into a single translation unit so one TU owns both the component path and the
 * modern handle-less proto path. Each exported entry point still owns its own
 * event emission and they never co-fire for one request.
 *
 * IMPORTANT: This is a direct merge of the two source files. The component
 * section is a direct translation of Swift's LLMCapability; do NOT add features
 * not present in the Swift code. The proto section owns the dlsym-bound,
 * handle-less verbs (rac_llm_generate_proto / _stream / cancel) — their names
 * MUST NOT change (all 5 SDKs bind them by name).
 */

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <limits>
#include <mutex>
#include <random>
#include <string>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "features/common/special_token_filter.h"
#include "features/llm/llm_thinking_tags_internal.h"
#include "features/llm/rac_llm_lifecycle_bridge.h"
// BUG-STREAMING-001: the canonical 13-field LLM stream emitter shared with the
// registry-backed path (rac_llm_stream.cpp). The component section invokes
// `rac::llm::dispatch_llm_stream_event()` once per token and once on terminal
// events so any collectors registered via rac_llm_set_stream_proto_callback()
// see the full decoded sequence. The proto section calls
// `rac::llm::serialize_llm_stream_event()` directly.
#include "features/llm/llm_stream_metrics_internal.h"
#include "features/llm/json_schema_to_gbnf_internal.h"
#include "features/llm/llm_thinking_directive_internal.h"
#include "features/llm/llm_thinking_stream_internal.h"
#include "features/llm/rac_llm_stream_internal.h"
#include "features/llm/structured_output_internal.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "sdk_events.pb.h"
#include "tool_calling.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

extern "C" void rac_lora_forget_component_state(rac_handle_t handle);

// =============================================================================
// COMPONENT SECTION (formerly llm_component.cpp)
// =============================================================================

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
// The stream timing arithmetic now lives in
// features/llm/llm_stream_metrics_internal.h so it can be unit-tested against
// synthetic timings. It replaces a `completion_tokens / (total − ttft)` figure
// that read 612-1594 tok/s against an engine doing 57 — see that header for why.
using rac::llm::compute_stream_timing;
using rac::llm::StreamTimingMetrics;
using rac::llm::StreamTokenTiming;

// A local trim helper lived here to nudge the streaming terminal result into
// agreement with the unary splitter. Do not bring it back: that result is now
// produced BY the unary splitter (dispatch_terminal_once), and a second,
// parallel definition of "agrees with unary" is precisely what drifted.

/** Last-resort chars/4 estimate. Callers MUST set counts_estimated when used. */
static int32_t estimate_tokens(const char* text) {
    if (!text)
        return 1;
    size_t len = strlen(text);
    int32_t tokens = static_cast<int32_t>((len + 3) / 4);
    return tokens > 0 ? tokens : 1;  // Minimum 1 token
}

/** Prefer ABI-v9 engine totals; false means the caller must estimate + flag. */
static bool try_engine_stream_token_counts(const rac_llm_service_ops_t* ops, void* impl,
                                           rac_llm_token_counts_t* out) {
    if (!ops || !ops->get_stream_token_counts || !impl || !out) {
        return false;
    }
    *out = {};
    return ops->get_stream_token_counts(impl, out) == RAC_SUCCESS;
}

/**
 * Resolve stream prompt/completion counts.
 * 1) ops->get_stream_token_counts when non-NULL and successful
 * 2) accumulated tokens_in_delta for completion
 * 3) estimate_tokens as last resort (caller must treat as estimated)
 */
static void resolve_stream_token_counts(const rac_llm_service_ops_t* ops, void* impl,
                                        const char* prompt, const char* completion_text,
                                        int32_t delta_completion_tokens, int32_t* out_prompt,
                                        int32_t* out_completion, bool* out_estimated) {
    rac_llm_token_counts_t engine{};
    if (try_engine_stream_token_counts(ops, impl, &engine)) {
        *out_prompt = engine.prompt_tokens;
        *out_completion = engine.completion_tokens;
        *out_estimated = false;
        return;
    }

    *out_estimated = true;
    *out_prompt = estimate_tokens(prompt);
    if (delta_completion_tokens > 0) {
        *out_completion = delta_completion_tokens;
    } else if (completion_text && completion_text[0] != '\0') {
        *out_completion = estimate_tokens(completion_text);
    } else {
        *out_completion = 0;
    }
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

#if defined(RAC_HAVE_PROTOBUF)

// ---------------------------------------------------------------------------
// LLM event emit helpers. Build the canonical GenerationEvent / ModelEvent and
// publish through the destination router (sdk_event_publish.h). generation_id is
// carried on the SDKEvent envelope session_id (telemetry groups by session_id).
// These centralize the per-event field mapping so the many call sites stay thin.
// ---------------------------------------------------------------------------

void emit_llm_model_load(runanywhere::v1::ModelEventKind kind, const char* model_id,
                         const char* model_name, rac_inference_framework_t framework,
                         double duration_ms, const char* error) {
    runanywhere::v1::ModelEvent m;
    m.set_kind(kind);
    if (model_id)
        m.set_model_id(model_id);
    if (model_name)
        m.set_model_name(model_name);
    m.set_framework(static_cast<runanywhere::v1::InferenceFramework>(rac::events::framework_to_proto_int(framework)));
    if (duration_ms > 0.0)
        m.set_duration_ms(static_cast<int64_t>(duration_ms));
    if (error)
        m.set_error(error);
    rac::events::publish(runanywhere::v1::SDK_COMPONENT_LLM, runanywhere::v1::EVENT_CATEGORY_MODEL,
                         std::move(m));
}

void emit_llm_generation_started(const char* generation_id, const char* model_id,
                                 const char* model_name, bool is_streaming,
                                 rac_inference_framework_t framework, float temperature,
                                 int32_t max_tokens, int32_t context_length) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_STARTED);
    if (model_id)
        g.set_model_id(model_id);
    if (model_name)
        g.set_model_name(model_name);
    g.set_is_streaming(is_streaming);
    g.set_framework(static_cast<runanywhere::v1::InferenceFramework>(rac::events::framework_to_proto_int(framework)));
    g.set_temperature(temperature);
    g.set_max_tokens(max_tokens);
    g.set_context_length(context_length);
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id);
}

void emit_llm_generation_completed(const char* generation_id, const char* model_id,
                                   const char* model_name, int32_t input_tokens,
                                   int32_t output_tokens, double duration_ms,
                                   double tokens_per_second, bool is_streaming,
                                   double time_to_first_token_ms,
                                   rac_inference_framework_t framework, float temperature,
                                   int32_t max_tokens, int32_t context_length,
                                   double prompt_eval_time_ms = 0.0) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED);
    if (model_id)
        g.set_model_id(model_id);
    if (model_name)
        g.set_model_name(model_name);
    g.set_input_tokens(input_tokens);
    g.set_output_tokens(output_tokens);
    g.set_total_duration_ms(static_cast<int64_t>(duration_ms));
    g.set_tokens_per_second(tokens_per_second);
    g.set_is_streaming(is_streaming);
    g.set_time_to_first_token_ms(static_cast<int64_t>(time_to_first_token_ms));
    if (prompt_eval_time_ms > 0.0) {
        g.set_prefill_duration_ms(static_cast<int64_t>(prompt_eval_time_ms));
    }
    g.set_framework(static_cast<runanywhere::v1::InferenceFramework>(rac::events::framework_to_proto_int(framework)));
    g.set_temperature(temperature);
    g.set_max_tokens(max_tokens);
    g.set_context_length(context_length);
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id);
}

void emit_llm_generation_failed(const char* generation_id, const char* model_id,
                                const char* model_name, const char* error) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_FAILED);
    if (model_id)
        g.set_model_id(model_id);
    if (model_name)
        g.set_model_name(model_name);
    if (error)
        g.set_error(error);
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id);
}

void emit_llm_first_token(const char* generation_id, const char* model_id, const char* model_name,
                          double time_to_first_token_ms, rac_inference_framework_t framework) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED);
    if (model_id)
        g.set_model_id(model_id);
    if (model_name)
        g.set_model_name(model_name);
    g.set_time_to_first_token_ms(static_cast<int64_t>(time_to_first_token_ms));
    g.set_framework(static_cast<runanywhere::v1::InferenceFramework>(rac::events::framework_to_proto_int(framework)));
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id);
}

void emit_llm_streaming_update(const char* generation_id, int32_t tokens_generated) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_STREAMING_UPDATE);
    g.set_output_tokens(tokens_generated);
    // STREAMING_UPDATE is too chatty for telemetry — PUBLIC stream only.
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id, rac::events::legacy_destination_public());
}

#endif  // RAC_HAVE_PROTOBUF

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
    return rac::features::create_lifecycle_component<rac_llm_component>(
        out_handle, RAC_RESOURCE_TYPE_LLM_MODEL, "LLM.Lifecycle", llm_create_service,
        llm_destroy_service, "LLM.Component", "LLM component created");
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
    // Spin-wait for any in-flight
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
    // Drain any in-flight dispatcher invocation
    // bound to the previous model before swapping in the new service. The
    // unset above clears the slot but a concurrent dispatcher that already
    // copied the slot keeps running until it finishes; spin-wait until that
    // pending invocation has returned so the user_data captured by the
    // previous registration can be safely freed.
    rac_llm_proto_quiesce();

    // Emit model load started event
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_model_load(runanywhere::v1::MODEL_EVENT_KIND_LOAD_STARTED, model_id, model_name,
                        component->actual_framework, /*duration_ms=*/0.0, /*error=*/nullptr);
#endif

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
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_model_load(runanywhere::v1::MODEL_EVENT_KIND_LOAD_FAILED, model_id, model_name,
                            component->actual_framework, load_duration_ms, "Model load failed");
#endif
    } else {
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_model_load(runanywhere::v1::MODEL_EVENT_KIND_LOAD_COMPLETED, model_id, model_name,
                            component->actual_framework, load_duration_ms, /*error=*/nullptr);
#endif
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
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name, "No model loaded");
#endif

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
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_generation_started(generation_id.c_str(), model_id, model_name,
                                /*is_streaming=*/false, component->actual_framework,
                                effective_options->temperature, effective_options->max_tokens,
                                context_length);
#endif

    auto start_time = std::chrono::steady_clock::now();

    // Perform generation
    result = rac_llm_generate(service, prompt, effective_options, out_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Generation failed");
        rac_lifecycle_track_error(component->lifecycle, result, "generate");

        // Emit generation failed event
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name,
                                   "Generation failed");
#endif

        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    int64_t total_time_ms = duration.count();

    // Prefer backend-reported counts; chars/4 estimate is last resort only.
    RAC_LOG_DEBUG("LLM.Component", "Backend returned prompt_tokens=%d, completion_tokens=%d",
                  out_result->prompt_tokens, out_result->completion_tokens);

    if (out_result->prompt_tokens <= 0) {
        out_result->prompt_tokens = estimate_tokens(prompt);
        RAC_LOG_DEBUG("LLM.Component", "Estimated prompt_tokens=%d (backend did not report)",
                      out_result->prompt_tokens);
    }
    if (out_result->completion_tokens <= 0) {
        out_result->completion_tokens = estimate_tokens(out_result->text);
        RAC_LOG_DEBUG("LLM.Component", "Estimated completion_tokens=%d (backend did not report)",
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

    // Emit generation completed event. Real backend counts win; estimate only
    // fills zeros (this C result has no counts_estimated carrier — proto paths do).
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_generation_completed(
        generation_id.c_str(), model_id, model_name, out_result->prompt_tokens,
        out_result->completion_tokens, static_cast<double>(total_time_ms), tokens_per_second,
        /*is_streaming=*/false, /*time_to_first_token_ms=*/0, component->actual_framework,
        effective_options->temperature, effective_options->max_tokens, context_length,
        /*prompt_eval_time_ms=*/static_cast<double>(out_result->prompt_eval_time_ms));
#endif

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
    int32_t prompt_tokens = 0;
    bool counts_estimated = true;

    // Per-stream sentinel filter. Stateful on purpose: a backend may split
    // `<|im_end|>` across two callbacks, and neither half is recognisable on
    // its own.
    rac::tokens::StreamFilter filter;

    // Analytics event data
    std::string generation_id;
    const char* model_id;
    const char* model_name;
    rac_inference_framework_t framework;
    float temperature;
    int32_t max_tokens;
    // Accumulated tokens_in_delta from the engine (0 when engine cannot count).
    int32_t token_count = 0;

    std::atomic<bool>* cancel_flag;

    // Component handle for the proto-byte stream
    // dispatcher. Each delivered token fires a LLMStreamEvent to any
    // collector registered via rac_llm_set_stream_proto_callback().
    rac_handle_t component_handle;

    // Producer finish_reason from the widened rac_llm_stream_callback_fn
    // terminal (is_final=true). Empty until the engine reports one.
    std::string producer_finish_reason;
    bool producer_final_seen = false;
};

/**
 * Internal token callback that wraps user callback and tracks metrics.
 *
 * Every emitted token is run through the per-stream
 * `rac::tokens::StreamFilter` before it reaches the user callback or the
 * proto stream dispatcher. Backends occasionally leak EOS sentinels
 * (`<|im_end|>`, `<|eot_id|>`, `<end_of_utterance>`, …) which the example
 * apps used to strip locally; the regex-based example workaround in
 * `useVLMCamera.ts` is now obsolete because commons emits cleaned tokens
 * directly.
 */
static rac_bool_t llm_stream_token_callback(const char* token, rac_bool_t is_final,
                                            const char* finish_reason, int32_t tokens_in_delta, void* user_data) {
    auto* ctx = reinterpret_cast<llm_stream_context*>(user_data);

    if (ctx->cancel_flag && ctx->cancel_flag->load(std::memory_order_relaxed)) {
        return RAC_FALSE;
    }

    if (is_final) {
        ctx->producer_final_seen = true;
        if (finish_reason != nullptr && finish_reason[0] != '\0') {
            ctx->producer_finish_reason = finish_reason;
        }
    }

    // Strip tokenizer-internal sentinels before any caller observes the
    // chunk. The filter carries per-stream state because a sentinel a backend
    // splits over two callbacks (`"<|im_"` then `"end|>"`) is only
    // recognisable once the halves are joined; the unresolved prefix is held
    // here rather than delivered as the angle-bracket artifact. The terminal
    // releases whatever is still held — with nothing more coming, an
    // unfinished prefix is ordinary text. That released tail is why an empty
    // terminal is no longer short-circuited above: every delivery below is
    // already guarded on `cleaned`, so an empty final still forwards nothing.
    std::string cleaned = ctx->filter.feed(token);
    if (is_final) {
        cleaned += ctx->filter.flush();
    }
    const bool cleaned_empty = cleaned.empty();

    // Track first token time and emit first token event only for the first
    // non-empty cleaned chunk so TTFT does not get charged to a leading
    // sentinel that the user never observes.
    if (!ctx->first_token_recorded && !cleaned_empty) {
        ctx->first_token_recorded = true;
        ctx->first_token_time = std::chrono::steady_clock::now();

        // Calculate TTFT
        auto ttft_duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            ctx->first_token_time - ctx->start_time);
        double ttft_ms = static_cast<double>(ttft_duration.count());

        // Emit first token event
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_first_token(ctx->generation_id.c_str(), ctx->model_id, ctx->model_name, ttft_ms,
                             ctx->framework);
#endif
    }

    // Accumulate text and engine-reported delta counts. Only cleaned text
    // reaches ctx->full_text. tokens_in_delta may be >1 when the backend
    // coalesces; 0 means the engine could not count this callback.
    if (!cleaned_empty) {
        ctx->full_text += cleaned;
        if (tokens_in_delta > 0) {
            ctx->token_count += tokens_in_delta;
        }

        // Emit streaming update event (every 10 tokens to avoid spam)
        if (ctx->token_count > 0 && ctx->token_count % 10 == 0) {
#if defined(RAC_HAVE_PROTOBUF)
            emit_llm_streaming_update(ctx->generation_id.c_str(), ctx->token_count);
#endif
        }
    }

    // Fan-out the token as an LLMStreamEvent to
    // any proto-byte subscribers. `is_final=false` on every per-token
    // event; the terminal is_final=true event is emitted by the
    // generate_stream() caller once the engine returns (below). Pure-
    // sentinel chunks are suppressed entirely so subscribers don't have
    // to filter empty events themselves.
    if (!cleaned_empty) {
        rac::llm::LLMStreamEventParams event;
        event.token = cleaned.c_str();
        event.kind = 1;  // ANSWER
        rac::llm::dispatch_llm_stream_event(ctx->component_handle, event);
    }

    // Forward only non-empty cleaned tokens to the user callback so the
    // example/SDK rendering layer never has to strip these sentinels.
    if (!cleaned_empty && ctx->token_callback) {
        return ctx->token_callback(cleaned.c_str(), ctx->user_data);
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
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name, "No model loaded");
#endif

        rac::llm::LLMStreamEventParams event;
        event.is_final = true;
        event.finish_reason = "error";
        event.error_message = "No model loaded";
        rac::llm::dispatch_llm_stream_event(handle, event);

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
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name,
                                   "Streaming not supported");
#endif

        rac::llm::LLMStreamEventParams event;
        event.is_final = true;
        event.finish_reason = "error";
        event.error_message = "Streaming not supported";
        rac::llm::dispatch_llm_stream_event(handle, event);

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
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_generation_started(generation_id.c_str(), model_id, model_name, /*is_streaming=*/true,
                                component->actual_framework, effective_options->temperature,
                                effective_options->max_tokens, context_length);
#endif

    // Setup streaming context
    llm_stream_context ctx;
    ctx.token_callback = token_callback;
    ctx.complete_callback = complete_callback;
    ctx.error_callback = error_callback;
    ctx.user_data = user_data;
    ctx.start_time = std::chrono::steady_clock::now();
    ctx.first_token_recorded = false;
    ctx.prompt_tokens = 0;
    ctx.counts_estimated = true;
    ctx.generation_id = generation_id;
    ctx.model_id = model_id;
    ctx.model_name = model_name;
    ctx.framework = component->actual_framework;
    ctx.temperature = effective_options->temperature;
    ctx.max_tokens = effective_options->max_tokens;
    ctx.token_count = 0;
    ctx.cancel_flag = &component->cancel_requested;
    ctx.component_handle = handle;
    // Pre-allocate to avoid repeated reallocations during streaming
    ctx.full_text.reserve(2048);

    // Perform streaming generation
    result = rac_llm_generate_stream(service, prompt, effective_options, llm_stream_token_callback,
                                     &ctx);

    // Prefer engine stream totals; else delta accumulation / estimate.
    {
        auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
        resolve_stream_token_counts(llm_service ? llm_service->ops : nullptr,
                                    llm_service ? llm_service->impl : nullptr, prompt,
                                    ctx.full_text.c_str(), ctx.token_count, &ctx.prompt_tokens,
                                    &ctx.token_count, &ctx.counts_estimated);
    }

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Streaming generation failed");
        rac_lifecycle_track_error(component->lifecycle, result, "generateStream");

        // Emit generation failed event
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name,
                                   "Streaming generation failed");
#endif

        // Terminal error event on the proto stream.
        rac::llm::LLMStreamEventParams event;
        event.is_final = true;
        event.finish_reason = "error";
        event.error_message = "Streaming generation failed";
        rac::llm::dispatch_llm_stream_event(handle, event);

        if (error_callback) {
            error_callback(result, "Streaming generation failed", user_data);
        }
        return result;
    }

    // Prefer the producer finish_reason from the widened stream callback
    // (is_final + finish_reason). Fall back to the thread-local side channel
    // for engines still mid-migration. Do not invent "stop" with zero
    // evidence, and do not use a zero-tokens heuristic (mock backends
    // legitimately return empty completions).
    const bool saw_native_final =
        ctx.producer_final_seen || rac_llm_stream_final_signal_seen() == RAC_TRUE;

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
    final_result.completion_tokens = ctx.token_count;
    final_result.total_tokens = final_result.prompt_tokens + final_result.completion_tokens;
    final_result.total_time_ms = total_time_ms;

    int64_t raw_ttft_ms = 0;
    if (ctx.first_token_recorded) {
        raw_ttft_ms = std::chrono::duration_cast<std::chrono::milliseconds>(ctx.first_token_time -
                                                                            ctx.start_time)
                          .count();
    }
    const StreamTimingMetrics timing = rac::llm::compute_stream_timing_from_totals(
        total_time_ms, raw_ttft_ms, final_result.completion_tokens);
    final_result.time_to_first_token_ms = timing.ttft_ms;
    final_result.prompt_eval_time_ms = timing.prefill_ms;
    final_result.tokens_per_second = static_cast<float>(timing.decode_tokens_per_second);
    const double tokens_per_second = timing.decode_tokens_per_second;
    const double ttft_ms = static_cast<double>(timing.ttft_ms);

    if (complete_callback) {
        complete_callback(&final_result, user_data);
    }

    // Emit generation completed event
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_generation_completed(
        generation_id.c_str(), model_id, model_name, final_result.prompt_tokens,
        final_result.completion_tokens, static_cast<double>(total_time_ms), tokens_per_second,
        /*is_streaming=*/true, ttft_ms, component->actual_framework, effective_options->temperature,
        effective_options->max_tokens, context_length,
        /*prompt_eval_time_ms=*/static_cast<double>(final_result.prompt_eval_time_ms));
#endif

    // Terminal success event on the proto stream.
    // BUG-STREAMING-003: emit finish_reason="length" when max_tokens was exhausted
    // (matches OpenAI chat.completions contract — proto is modeled after it).
    const char* finish_reason_str = "stop";
    if (component->cancel_requested.load(std::memory_order_relaxed)) {
        finish_reason_str = "cancelled";
    } else if (effective_options->max_tokens > 0 &&
               ctx.token_count >= effective_options->max_tokens) {
        finish_reason_str = "length";
    } else if (!ctx.producer_finish_reason.empty()) {
        finish_reason_str = ctx.producer_finish_reason.c_str();
    } else if (!saw_native_final) {
        // RAC_SUCCESS, not cancelled, not max-tokens — but no backend ever
        // reported a genuine terminal signal for this call. Report "unknown"
        // instead of fabricating "stop" with zero evidence.
        finish_reason_str = "unknown";
    }
    rac::llm::LLMStreamEventParams terminal_event;
    terminal_event.is_final = true;
    terminal_event.kind = 1;  // ANSWER
    terminal_event.finish_reason = finish_reason_str;
    rac::llm::dispatch_llm_stream_event(handle, terminal_event);

    // Free the duplicated text
    free(final_result.text);

    RAC_LOG_INFO("LLM.Component", "Streaming generation completed");

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
// ADAPTIVE CONTEXT API
// =============================================================================

/** Seed a component's adaptive KV context with a reusable system prompt. */
extern "C" rac_result_t rac_llm_component_inject_system_prompt(rac_handle_t handle,
                                                               const char* prompt) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!prompt)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        RAC_LOG_ERROR("LLM.Component", "Cannot inject system prompt: no model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    return rac_llm_inject_system_prompt(service, prompt);
}

/** Append text to a component's existing adaptive KV context. */
extern "C" rac_result_t rac_llm_component_append_context(rac_handle_t handle, const char* text) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!text)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        RAC_LOG_ERROR("LLM.Component", "Cannot append context: no model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    return rac_llm_append_context(service, text);
}

/** Generate from a component's accumulated adaptive context. */
extern "C" rac_result_t rac_llm_component_generate_from_context(
    rac_handle_t handle, const char* query, const rac_llm_options_t* options,
    rac_llm_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!query || !out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        RAC_LOG_ERROR("LLM.Component", "Cannot generate from context: no model loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    const rac_llm_options_t* effective_options = options ? options : &component->default_options;
    return rac_llm_generate_from_context(service, query, effective_options, out_result);
}

/** Clear all adaptive context retained by a component. */
extern "C" rac_result_t rac_llm_component_clear_context(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_llm_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        return RAC_SUCCESS;
    }

    return rac_llm_clear_context(service);
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

// =============================================================================
// PROTO SECTION (formerly rac_llm_proto_service.cpp)
//
// Lifecycle-owned LLM generated-proto C ABI. These verbs (rac_llm_generate_proto
// / _stream / cancel) are handle-less and dlsym-bound BY NAME by all 5 SDKs —
// the names MUST NOT change. They resolve the loaded model via the global
// registry (rac::llm::acquire_lifecycle_llm) rather than a component handle, and
// own their own event emission via publish_generation_event (never co-fire with
// the component path above for one request).
// =============================================================================

namespace {

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

#if defined(RAC_HAVE_PROTOBUF)

using runanywhere::v1::CancellationEventKind;
using runanywhere::v1::ErrorSeverity;
using runanywhere::v1::EventCategory;
using runanywhere::v1::GenerationEventKind;
using runanywhere::v1::LLMGenerateRequest;
using runanywhere::v1::LLMGenerationResult;
using runanywhere::v1::SDKEvent;
using runanywhere::v1::TokenKind;

// Defined below; replaces invalid UTF-8 with U+FFFD so model output is safe to
// store in proto `string` fields (llama.cpp can cut a multibyte char at
// max_tokens). Forward-declared so the emit helpers above its definition can
// use it.
std::string sanitize_utf8(const std::string& in);

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string make_event_id() {
    static std::atomic<uint64_t> counter{0};
    const uint64_t c = counter.fetch_add(1);
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(c));
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

void populate_event_envelope(SDKEvent* event, EventCategory category, ErrorSeverity severity) {
    event->set_id(make_event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(category);
    event->set_severity(severity);
    event->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_source("cpp");
}

rac_result_t publish_sdk_event(const SDKEvent& event) {
    // Route through the events layer so the event reaches the telemetry + log
    // sinks per its destination bitmask, not just the public proto stream.
    return rac::events::publish_prebuilt(event);
}

void publish_generation_event(GenerationEventKind kind, const char* prompt, const char* token,
                              const char* response, const char* error, const char* model_id,
                              int32_t token_count, int64_t latency_ms, int32_t input_tokens = 0,
                              const char* framework_name = nullptr, double tokens_per_second = 0.0,
                              double ttft_ms = 0.0, float temperature = -1.0f,
                              int32_t max_tokens = 0, int32_t context_length = 0,
                              bool is_streaming = false, double prompt_eval_time_ms = 0.0) {
    SDKEvent event;
    const bool failed = kind == runanywhere::v1::GENERATION_EVENT_KIND_FAILED;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_LLM,
                            failed ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                   : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_operation_id("llm.generate");
    // This proto-path emitter has no framework proto field wired; carry the
    // lifecycle ref's framework_name on the properties map (the kGeneration
    // telemetry extraction normalizes it via clean_framework). Without this,
    // LLM rows show no framework.
    if (framework_name != nullptr && framework_name[0] != '\0') {
        (*event.mutable_properties())["framework"] = framework_name;
    }
    auto* generation = event.mutable_generation();
    generation->set_kind(kind);
    if ((prompt != nullptr) && prompt[0] != '\0') {
        generation->set_prompt(prompt);
    }
    if ((token != nullptr) && token[0] != '\0') {
        generation->set_token(token);
    }
    if ((response != nullptr) && response[0] != '\0') {
        generation->set_response(sanitize_utf8(response));
    }
    if ((error != nullptr) && error[0] != '\0') {
        generation->set_error(error);
    }
    if ((model_id != nullptr) && model_id[0] != '\0') {
        generation->set_model_id(model_id);
    }
    if (token_count > 0) {
        generation->set_output_tokens(token_count);
    }
    if (latency_ms > 0) {
        generation->set_total_duration_ms(latency_ms);
    }
    if (input_tokens > 0) {
        generation->set_input_tokens(input_tokens);
    }
    // Completion metrics (proto-path parity with the component path's
    // emit_llm_generation_completed). All use existing GenerationEvent proto
    // fields; the kGeneration telemetry extraction already reads them.
    if (tokens_per_second > 0.0) {
        generation->set_tokens_per_second(tokens_per_second);
    }
    if (ttft_ms > 0.0) {
        generation->set_time_to_first_token_ms(static_cast<int64_t>(ttft_ms));
    }
    if (prompt_eval_time_ms > 0.0) {
        generation->set_prefill_duration_ms(static_cast<int64_t>(prompt_eval_time_ms));
    }
    // temperature 0.0 is a valid (greedy) setting, so the sentinel for "unset"
    // is a negative default — emit any non-negative value.
    if (temperature >= 0.0f) {
        generation->set_temperature(temperature);
    }
    if (max_tokens > 0) {
        generation->set_max_tokens(max_tokens);
    }
    if (context_length > 0) {
        generation->set_context_length(context_length);
    }
    generation->set_is_streaming(is_streaming);
    (void)publish_sdk_event(event);
}

// Best-effort context-length lookup for the handle-less proto path (the
// component path reads it from config; here we query the engine ops vtable).
int32_t lifecycle_context_length(const rac::llm::LifecycleLlmRef& ref) {
    if (ref.ops == nullptr || ref.ops->get_info == nullptr) {
        return 0;
    }
    rac_llm_info_t info{};
    if (ref.ops->get_info(ref.impl, &info) != RAC_SUCCESS) {
        return 0;
    }
    return info.context_length;
}

SDKEvent make_cancellation_event(CancellationEventKind kind, const char* reason,
                                 rac_bool_t user_initiated, ErrorSeverity severity) {
    SDKEvent event;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_CANCELLATION, severity);
    event.set_operation_id("llm.generate");
    auto* cancellation = event.mutable_cancellation();
    cancellation->set_kind(kind);
    cancellation->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    cancellation->set_operation_id("llm.generate");
    cancellation->set_reason((reason != nullptr) && reason[0] != '\0' ? reason : "user_requested");
    cancellation->set_user_initiated(user_initiated == RAC_TRUE);
    return event;
}

// Pick the system prompt from the sole generation-settings envelope.
std::string system_prompt_from_request(const LLMGenerateRequest& request) {
    if (request.has_options() && request.options().has_system_prompt() &&
        !request.options().system_prompt().empty()) {
        return request.options().system_prompt();
    }
    return {};
}

// LLMGenerateRequest.prompt and .history were both deleted (idl/llm_service.proto)
// in favor of a single `repeated ChatMessage messages`: the whole conversation,
// oldest first, ending with the turn the model must answer. This extracts that
// final turn's text — the direct replacement for the old bare `request.prompt()`
// call sites throughout this file. System turns never appear here; they travel
// on options.system_prompt exclusively.
const std::string& current_prompt_from_messages(const LLMGenerateRequest& request) {
    static const std::string kEmpty;
    const int count = request.messages_size();
    if (count == 0) {
        return kEmpty;
    }
    return request.messages(count - 1).content();
}

void thinking_tags_from_request_or_model(const LLMGenerateRequest& request,
                                         const rac::llm::LifecycleLlmRef& ref,
                                         std::string* out_open_tag, std::string* out_close_tag,
                                         bool* out_template_prefills_open_tag = nullptr) {
    if (out_open_tag) {
        out_open_tag->clear();
    }
    if (out_close_tag) {
        out_close_tag->clear();
    }
    if (out_template_prefills_open_tag) {
        // Default to the loaded model's stamped prefill signal; a per-call
        // ReasoningOptions.pattern may override below when the optional is set.
        *out_template_prefills_open_tag = ref.template_prefills_open_tag;
    }
    if (request.has_options() && request.options().has_reasoning() &&
        request.options().reasoning().has_pattern()) {
        const auto& pattern = request.options().reasoning().pattern();
        if (out_template_prefills_open_tag && pattern.has_template_prefills_open_tag()) {
            *out_template_prefills_open_tag = pattern.template_prefills_open_tag();
        }
        if (!pattern.open_tag().empty() && !pattern.close_tag().empty()) {
            if (out_open_tag) {
                *out_open_tag = pattern.open_tag();
            }
            if (out_close_tag) {
                *out_close_tag = pattern.close_tag();
            }
            return;
        }
    }
    bool registry_prefills = false;
    if (rac::llm::model_thinking_tags_from_registry(ref.model_id, out_open_tag, out_close_tag,
                                                    &registry_prefills)) {
        // Request did not supply a pattern (or only supplied the optional
        // prefill override above). Prefer the registry stamp when the lifecycle
        // ref has not already carried it (e.g. stale load before enrichment).
        if (out_template_prefills_open_tag && !ref.template_prefills_open_tag &&
            !(request.has_options() && request.options().has_reasoning() &&
              request.options().reasoning().has_pattern() &&
              request.options().reasoning().pattern().has_template_prefills_open_tag())) {
            *out_template_prefills_open_tag = registry_prefills;
        }
    }
}

// Fills `options` from `request`. The caller-owned `stop_storage`/`stop_ptrs`
// must outlive every generate/generate_stream dispatch that observes
// `options.stop_sequences` — they hold the backing memory the C ABI points
// into. Mirrors RALLMTypes+CppBridge.swift toRALLMGenerateRequest which
// copies stopSequences into the canonical proto request.
//
// `request.options()` is the sole generation-settings contract. When absent,
// retain RAC_LLM_OPTIONS_DEFAULT values.
//
// When a schema arm is present and must constrain decoding but cannot be
// compiled to GBNF, `*structured_error` is set (non-empty) and grammar is
// left empty — callers MUST fail the request rather than generate freely.
rac_llm_options_t
options_from_request(const LLMGenerateRequest& request, const std::string& system_prompt,
                     std::vector<std::string>& stop_storage, std::vector<const char*>& stop_ptrs,
                     std::string& grammar_storage, std::vector<std::string>& history_storage,
                     std::vector<const char*>& history_ptrs,
                     std::string* structured_error = nullptr) {
    if (structured_error) {
        structured_error->clear();
    }
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;

    const bool has_options = request.has_options();
    const auto& opts = request.options();

    // max_output_tokens proto3 zero means "unset → engine default".
    if (has_options && opts.max_output_tokens() > 0) {
        options.max_tokens = opts.max_output_tokens();
    }

    // temperature: when the canonical LLMGenerationOptions is set, pass its value through
    // unconditionally so the documented greedy-decoding sentinel (0.0) reaches the engine
    // (idl/llm_options.proto:49).
    if (has_options) {
        options.temperature = std::clamp(opts.temperature(), 0.0f, 2.0f);
    }

    // top_p: proto3 zero is the unset sentinel, 1.0 means no truncation
    // (idl/llm_options.proto:53). Gate the canonical field so an options
    // envelope carrying only another knob does not override top_p with zero.
    if (has_options && opts.top_p() > 0.0f) {
        options.top_p = opts.top_p();
    }

    // Thread the remaining sampling knobs the proto exposes
    // (idl/llm_options.proto) into the C ABI so they reach the engine vtable.
    // repetition_penalty was renamed repeat_penalty (same tag, mechanical
    // rename). For every field except repeat_penalty the proto3 zero IS the
    // documented "disabled" sentinel, so passing it through is identical to the
    // struct default. repeat_penalty uses 1.0 = "no penalty"; proto3 zero
    // means unset, so only override when positive (mirrors Swift's
    // RALLMTypes+CppBridge defaults, which carry repeatPenalty=1.0).
    options.top_k = has_options ? opts.top_k() : 0;
    const float repeat_penalty = has_options ? opts.repeat_penalty() : 0.0f;
    if (repeat_penalty > 0.0f) {
        options.repetition_penalty = repeat_penalty;
    }
    options.frequency_penalty = has_options ? opts.frequency_penalty() : 0.0f;
    options.presence_penalty = has_options ? opts.presence_penalty() : 0.0f;
    options.min_p = has_options ? opts.min_p() : 0.0f;
    options.seed = has_options ? opts.seed() : 0;
    // n_threads was deleted from LLMGenerationOptions (idl/llm_options.proto):
    // thread count is now a load-time-only decision the engine makes when it
    // builds its thread pool at model load, not a per-request override.
    // options.n_threads (the C ABI struct field) keeps its
    // RAC_LLM_OPTIONS_DEFAULT value (0 = backend default).
    options.disable_thinking =
        (has_options && opts.has_reasoning() &&
         opts.reasoning().mode() == runanywhere::v1::REASONING_MODE_OFF)
            ? RAC_TRUE
            : RAC_FALSE;

    // Structured-output constraint: honor an explicit grammar arm, otherwise
    // compile the schema arm to GBNF. VALIDATION_ONLY skips decoder constraint.
    // A present schema/grammar arm that fails to compile fails the call — never
    // silently degrade to free generation (structured_output.proto contract).
    grammar_storage.clear();
    if (has_options && opts.has_structured_output()) {
        const auto& so = opts.structured_output();
        const auto mode = so.has_mode() ? so.mode()
                                        : runanywhere::v1::STRUCTURED_OUTPUT_MODE_UNSPECIFIED;
        const bool constrain =
            mode != runanywhere::v1::STRUCTURED_OUTPUT_MODE_VALIDATION_ONLY;
        if (constrain) {
            if (so.has_grammar() && !so.grammar().empty()) {
                grammar_storage = so.grammar();
            } else if (so.has_schema() && !so.schema().empty()) {
                std::string compile_error;
                if (!rac::llm::json_schema_to_gbnf(so.schema(), &grammar_storage, &compile_error)) {
                    grammar_storage.clear();
                    if (structured_error) {
                        *structured_error =
                            compile_error.empty()
                                ? "StructuredOutputOptions.schema could not be compiled to GBNF"
                                : compile_error;
                    }
                }
            }
        }
    }
    options.grammar = grammar_storage.empty() ? nullptr : grammar_storage.c_str();

    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    stop_storage.clear();
    stop_ptrs.clear();

    const int stop_count = has_options ? opts.stop_sequences_size() : 0;
    if (stop_count > 0) {
        stop_storage.reserve(static_cast<size_t>(stop_count));
        for (const auto& seq : opts.stop_sequences()) {
            if (!seq.empty()) {
                stop_storage.push_back(seq);
            }
        }
        stop_ptrs.reserve(stop_storage.size());
        for (const auto& seq : stop_storage) {
            stop_ptrs.push_back(seq.c_str());
        }
    }
    options.stop_sequences = stop_ptrs.empty() ? nullptr : stop_ptrs.data();
    options.num_stop_sequences = stop_ptrs.size();

    // Prior conversation turns. LLMGenerateRequest.prompt and .history were
    // both deleted in favor of one `repeated ChatMessage messages` — the whole
    // conversation, oldest first, ending with the turn the model must answer
    // (idl/llm_service.proto). The last message IS the current prompt (see
    // current_prompt_from_messages()); everything before it is prior history.
    // The C ABI still carries a role-less alternating string array, so
    // normalize the proto roles before flattening: keep only user/assistant
    // turns, drop leading assistant turns, coalesce duplicate same-role turns.
    // (No trailing-user-turn pop needed here: unlike the old `history` field,
    // `messages` excludes the current turn by construction — the loop below
    // stops one message before the end.)
    history_storage.clear();
    history_ptrs.clear();
    const int message_count = request.messages_size();
    if (message_count > 1) {
        history_storage.reserve(static_cast<size_t>(message_count - 1));
        runanywhere::v1::MessageRole last_role = runanywhere::v1::MESSAGE_ROLE_UNSPECIFIED;
        for (int i = 0; i < message_count - 1; ++i) {
            const auto& msg = request.messages(i);
            const auto role = msg.role();
            if (role != runanywhere::v1::MESSAGE_ROLE_USER &&
                role != runanywhere::v1::MESSAGE_ROLE_ASSISTANT) {
                continue;
            }
            if (msg.content().empty()) {
                continue;
            }
            if (history_storage.empty() && role != runanywhere::v1::MESSAGE_ROLE_USER) {
                continue;
            }
            if (role == last_role) {
                history_storage.back().append("\n\n").append(msg.content());
            } else {
                history_storage.push_back(msg.content());
                last_role = role;
            }
        }
        history_ptrs.reserve(history_storage.size());
        for (const auto& turn : history_storage) {
            history_ptrs.push_back(turn.c_str());
        }
    }
    options.history = history_ptrs.empty() ? nullptr : history_ptrs.data();
    options.n_history = static_cast<int32_t>(history_ptrs.size());
    return options;
}

// Replace any invalid UTF-8 byte sequence with U+FFFD so the value is safe to
// store in a proto `string` field. llama.cpp can emit an incomplete trailing
// multibyte sequence when generation is cut at max_tokens; without this,
// protobuf serialization of LLMGenerationResult.text fails and the whole
// unary result is unparseable by the caller.
std::string sanitize_utf8(const std::string& in) {
    std::string out;
    out.reserve(in.size());
    const size_t n = in.size();
    size_t i = 0;
    auto is_cont = [&](size_t k) {
        return k < n && (static_cast<unsigned char>(in[k]) & 0xC0) == 0x80;
    };
    while (i < n) {
        const unsigned char c = static_cast<unsigned char>(in[i]);
        size_t len = 0;
        if (c < 0x80) {
            len = 1;
        } else if ((c & 0xE0) == 0xC0 && c >= 0xC2) {
            len = 2;
        } else if ((c & 0xF0) == 0xE0) {
            len = 3;
        } else if ((c & 0xF8) == 0xF0 && c <= 0xF4) {
            len = 4;
        }
        bool ok = len > 0;
        for (size_t k = 1; ok && k < len; ++k) {
            ok = is_cont(i + k);
        }
        if (ok) {
            out.append(in, i, len);
            i += len;
        } else {
            out.append("\xEF\xBF\xBD");  // U+FFFD replacement character
            i += 1;
        }
    }
    return out;
}

void set_result_from_raw(const rac::llm::LifecycleLlmRef& ref, const rac_llm_result_t& raw,
                         const char* response, size_t response_len, const char* thinking,
                         size_t thinking_len, int32_t thinking_tokens, int32_t response_tokens,
                         int32_t requested_max_tokens, LLMGenerationResult* out) {
    out->set_text(sanitize_utf8(response ? std::string(response, response_len) : std::string()));
    if (thinking && thinking_len > 0) {
        out->set_thinking_content(sanitize_utf8(std::string(thinking, thinking_len)));
    }
    out->mutable_usage()->set_input_tokens(raw.prompt_tokens);
    out->mutable_usage()->set_output_tokens(raw.completion_tokens);
    out->mutable_usage()->set_total_tokens(raw.total_tokens);
    out->set_model_used(ref.model_id ? ref.model_id : "");
    out->set_generation_time_ms(static_cast<double>(raw.total_time_ms));
    // ttft_ms moved from LLMGenerationResult onto the shared TokenUsage shape
    // (idl/token_usage.proto) — every result/metrics message now reports TTFT
    // there instead of its own bespoke field.
    if (raw.time_to_first_token_ms > 0) {
        out->mutable_usage()->set_ttft_ms(raw.time_to_first_token_ms);
    }
    if (raw.prompt_eval_time_ms > 0) {
        out->set_prompt_eval_time_ms(raw.prompt_eval_time_ms);
    }
    out->mutable_usage()->set_decode_tokens_per_second(static_cast<double>(raw.tokens_per_second));
    if ((ref.framework_name != nullptr) && ref.framework_name[0] != '\0') {
        out->set_framework(ref.framework_name);
    }
    // BUG-STREAMING-003: emit FINISH_REASON_LENGTH when max_tokens was exhausted
    // (matches OpenAI chat.completions contract — proto is modeled after it).
    // finish_reason widened from a bare string to the FinishReason enum
    // (idl/llm_options.proto).
    out->set_finish_reason((requested_max_tokens > 0 && raw.completion_tokens >= requested_max_tokens)
                               ? runanywhere::v1::FINISH_REASON_LENGTH
                               : runanywhere::v1::FINISH_REASON_STOP);
    out->set_thinking_tokens(thinking_tokens);
    out->set_response_tokens(response_tokens);
    out->set_executed_on(runanywhere::v1::EXECUTION_TARGET_ON_DEVICE);

    auto* perf = out->mutable_performance();
    perf->set_latency_ms(raw.total_time_ms);
    perf->mutable_usage()->set_decode_tokens_per_second(raw.tokens_per_second);
    perf->mutable_usage()->set_input_tokens(raw.prompt_tokens);
    perf->mutable_usage()->set_output_tokens(raw.completion_tokens);
}

void set_structured_output_if_present(const char* response, LLMGenerationResult* out,
                                      const rac_structured_output_config_t* config = nullptr,
                                      bool repair_attempted = false, int32_t repair_attempts = 0) {
    if (!response || !out) {
        return;
    }
    const auto* cursor = reinterpret_cast<const unsigned char*>(response);
    while (*cursor != '\0' && std::isspace(*cursor)) {
        ++cursor;
    }
    if (*cursor == '\0') {
        return;
    }
    rac_structured_output_validation_t validation{};
    if (rac_structured_output_validate(response, config, &validation) == RAC_SUCCESS) {
        auto* structured = out->mutable_structured_output_validation();
        structured->set_repair_attempted(repair_attempted);
        structured->set_repair_attempts(repair_attempts);
        if (validation.is_valid == RAC_TRUE && validation.extracted_json) {
            out->set_json_output(validation.extracted_json);
            structured->set_is_valid(true);
            structured->set_contains_json(true);
            structured->set_raw_output(sanitize_utf8(response));
            structured->set_extracted_json(validation.extracted_json);
        } else if (validation.error_message) {
            structured->set_is_valid(false);
            structured->set_contains_json(validation.extracted_json != nullptr);
            structured->set_raw_output(sanitize_utf8(response));
            if (validation.extracted_json) {
                structured->set_extracted_json(validation.extracted_json);
            }
            rac::foundation::populate_sdk_error(structured->mutable_error(),
                                                RAC_ERROR_VALIDATION_FAILED);
            structured->mutable_error()->set_message(validation.error_message);
        }
    }
    rac_structured_output_validation_free(&validation);
}

struct ProtoStreamContext {
    rac_llm_stream_proto_callback_fn callback = nullptr;
    void* user_data = nullptr;
    rac::llm::LifecycleLlmRef* ref = nullptr;
    // Same per-stream sentinel filter the handle-based path (llm_stream_context)
    // has carried for a while. This context backs the handle-LESS lifecycle ABI
    // — the one every SDK that is not iOS actually calls (Web/WASM, Kotlin JNI,
    // Flutter FFI, React Native) — so without it `<|im_end|>` reached chat
    // bubbles and TTS on four platforms while iOS was clean.
    rac::tokens::StreamFilter filter;
    uint64_t seq = 0;
    bool terminal_sent = false;
    bool first_token_sent = false;
    bool emit_thoughts = false;
    int32_t prompt_tokens = 0;
    int32_t token_count = 0;
    bool counts_estimated = true;
    std::string request_id;
    std::string conversation_id;
    std::string raw_text;
    std::string response_text;
    std::string thinking_text;
    std::string thinking_open_tag;
    std::string thinking_close_tag;
    std::string producer_finish_reason;
    bool producer_final_seen = false;

    // The incremental reasoning/content splitter. Owns the partial-delimiter
    // tail, so a `</think>` straddling two engine deltas is still recognised.
    rac::llm::ThinkingStreamSplitter splitter;
    // Reused across deltas so the hot path does not allocate a vector per token.
    std::vector<rac::llm::ThinkingStreamSegment> segments;

    // Timing observations, taken where deltas are PRODUCED rather than where
    // they are dispatched — a visibility flag must not move a latency metric.
    StreamTokenTiming timing;
    // Production time of the first delta the splitter withheld while deciding
    // whether the stream opened inside a prefilled reasoning block. If that text
    // turns out to be the answer, time-to-first-content is THIS instant, not the
    // instant the hold released it; otherwise it is discarded.
    int64_t provisional_content_ms = 0;
    // `started_ms` is duplicated on the context because many call sites below
    // read it directly for events; `timing.started_ms` is the same value.
    int64_t started_ms = 0;
    int64_t first_token_ms = 0;
};

// BUG-STREAMING-001 unification: `dispatch_stream_event` now delegates
// to `rac::llm::serialize_llm_stream_event` — the single canonical
// 13-field emitter shared with `rac_llm_stream.cpp`. All callers
// populate the same LLMStreamEvent shape so Swift iOS, Web, and Kotlin
// Android consumers see identical wire bytes for identical inputs.
//
// Optional `tool_call` populates proto field 18 on
// LLMStreamEvent (idl/llm_service.proto:179). Producers pass it on the
// synthesized TOOL_CALL boundary event when the streaming output contains
// a parseable tool call; non-tool-call events leave it nullptr so legacy
// streams are byte-for-byte identical.
void dispatch_stream_event(ProtoStreamContext* ctx, const char* token, bool is_final,
                           TokenKind kind, const char* finish_reason, const char* error_message,
                           const LLMGenerationResult* result = nullptr,
                           const runanywhere::v1::ToolCall* tool_call = nullptr) {
    if (!ctx || !ctx->callback) {
        return;
    }

    rac::llm::LLMStreamEventParams params;
    params.token = token ? token : "";
    params.is_final = is_final;
    params.kind = static_cast<int>(kind);
    params.finish_reason = finish_reason;
    params.error_message = error_message;
    params.request_id = ctx->request_id.empty() ? nullptr : ctx->request_id.c_str();
    params.conversation_id = ctx->conversation_id.empty() ? nullptr : ctx->conversation_id.c_str();
    params.completion_tokens_generated = ctx->token_count;
    params.elapsed_ms = now_ms() - ctx->started_ms;
    params.final_result = result;
    params.tool_call = tool_call;

    thread_local std::vector<uint8_t> scratch;
    if (!rac::llm::serialize_llm_stream_event(++ctx->seq, params, scratch)) {
        return;
    }
    ctx->callback(scratch.empty() ? nullptr : scratch.data(), scratch.size(), ctx->user_data);
}

// Parse the accumulated streaming response_text for a tool
// call boundary using the canonical commons parser (rac_tool_call_parse_proto
// over runanywhere.v1.ToolParseRequest/Result). Returns true and populates
// out_tool_call when a structured tool call is recognized; false when the
// output contains no tool-call markers. The parser is format-aware
// (DEFAULT <tool_call>JSON</tool_call> and LFM2 <|tool_call_start|>...) and
// requires no ToolCallingOptions on the request because LLMGenerateRequest
// does not carry tool definitions (idl/llm_service.proto:42-51) — auto-format
// detection is sufficient to surface the structured payload on the
// LLMStreamEvent.tool_call slot when the model emitted one.
bool parse_response_tool_call(const std::string& response_text,
                              runanywhere::v1::ToolCall* out_tool_call) {
    if (response_text.empty() || !out_tool_call) {
        return false;
    }
    runanywhere::v1::ToolParseRequest request;
    request.set_text(response_text);

    const size_t req_size = request.ByteSizeLong();
    std::vector<uint8_t> req_bytes(req_size);
    if (req_size > 0 &&
        !request.SerializeToArray(req_bytes.data(), static_cast<int>(req_bytes.size()))) {
        return false;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_parse_proto(req_bytes.empty() ? nullptr : req_bytes.data(),
                                                req_bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return false;
    }

    runanywhere::v1::ToolParseResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    rac_proto_buffer_free(&out);

    if (result.has_tool_call() && result.tool_calls_size() > 0) {
        *out_tool_call = result.tool_calls(0);
        return true;
    }
    return false;
}

void emit_stream_segment(ProtoStreamContext* ctx, const std::string& token, TokenKind kind) {
    if (!ctx || token.empty()) {
        return;
    }

    if (kind == runanywhere::v1::TOKEN_KIND_THOUGHT) {
        ctx->thinking_text += token;
    } else {
        ctx->response_text += token;
    }

    // Completion accounting is per ENGINE delta (see stream_token_callback), not
    // per post-split segment: the splitter can turn one delta into two segments
    // or hold it back entirely, and counting segments here is what let the token
    // total drift from what the engine actually produced.
    if (kind == runanywhere::v1::TOKEN_KIND_THOUGHT && !ctx->emit_thoughts) {
        return;
    }
    if (!ctx->first_token_sent) {
        ctx->first_token_sent = true;
        // Kept as the first DISPATCHED token for the event stream's sake, while
        // `timing.first_token_ms` records the first PRODUCED token. Reporting
        // the dispatched time as TTFT is the defect this separation fixes.
        ctx->first_token_ms = now_ms();
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED,
                                 nullptr, token.c_str(), nullptr, nullptr, ctx->ref->model_id, 1,
                                 ctx->timing.first_token_ms - ctx->started_ms);
    }
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED, nullptr,
                             token.c_str(), nullptr, nullptr, ctx->ref->model_id, ctx->token_count,
                             0);
    dispatch_stream_event(ctx, token.c_str(), false, kind, nullptr, nullptr);
}

/** Applies one classified segment from the splitter to the stream context. */
void apply_thinking_segment(ProtoStreamContext* ctx,
                            const rac::llm::ThinkingStreamSegment& segment) {
    if (segment.reclassify_prior_content_as_reasoning) {
        // The splitter just proved that the reasoning region opened before the
        // first token (its opening tag was prefilled into the prompt), so
        // everything accumulated as answer so far is reasoning.
        //
        // This branch only runs for a model that declared NOTHING about
        // reasoning — one that did gets `set_hold_ambiguous_prefix` (or
        // `start_inside_reasoning` when template_prefills_open_tag is set),
        // which settles the same question before any delta is dispatched. Here
        // the deltas already handed to the callback keep the kind they were
        // sent with; a callback cannot be un-called, and the terminal result is
        // recomputed from the raw text regardless.
        ctx->thinking_text.insert(0, ctx->response_text);
        ctx->response_text.clear();
        // The content clock never actually started: every delta it was stamped
        // from was reasoning. Leaving it set is what collapsed
        // time-to-first-content into TTFT on exactly the models that prefill.
        ctx->timing.first_content_token_ms = 0;
        ctx->provisional_content_ms = 0;
    }
    if (segment.text.empty()) {
        return;
    }
    const bool reasoning = segment.channel == rac::llm::ThinkingChannel::kReasoning;
    if (reasoning) {
        // Whatever was withheld was reasoning after all; it must not be allowed
        // to back-date the first answer token.
        ctx->provisional_content_ms = 0;
    } else if (ctx->timing.first_content_token_ms == 0) {
        // Time to first CONTENT — the wait the user actually experiences, since
        // everything before it is reasoning they may never see. Stamped at the
        // channel boundary and never conflated with `ttft_ms`. Text released
        // from the ambiguity hold is dated from when the ENGINE produced it, not
        // from when the hold let go, or the hold itself would show up as
        // latency the model never spent.
        ctx->timing.first_content_token_ms =
            ctx->provisional_content_ms > 0 ? ctx->provisional_content_ms : now_ms();
        ctx->provisional_content_ms = 0;
    }
    emit_stream_segment(ctx, segment.text,
                        reasoning ? runanywhere::v1::TOKEN_KIND_THOUGHT
                                  : runanywhere::v1::TOKEN_KIND_ANSWER);
}

void consume_thinking_aware_text(ProtoStreamContext* ctx, const char* token, int64_t produced_ms) {
    if (!ctx || !token || token[0] == '\0') {
        return;
    }
    ctx->raw_text += token;
    ctx->segments.clear();
    ctx->splitter.push(token, &ctx->segments);
    for (const auto& segment : ctx->segments) {
        apply_thinking_segment(ctx, segment);
    }
    // Remember when the withheld run began. Recorded after the push so a delta
    // that both starts and ends the hold is dated by the hold's own release.
    if (ctx->provisional_content_ms == 0 && ctx->splitter.holding_ambiguous_prefix()) {
        ctx->provisional_content_ms = produced_ms;
    }
}

void flush_pending_stream_text(ProtoStreamContext* ctx) {
    if (!ctx) {
        return;
    }
    ctx->segments.clear();
    ctx->splitter.flush(&ctx->segments);
    for (const auto& segment : ctx->segments) {
        apply_thinking_segment(ctx, segment);
    }
}

void dispatch_terminal_once(ProtoStreamContext* ctx, const char* finish_reason,
                            const char* error_message) {
    if (!ctx || ctx->terminal_sent) {
        return;
    }
    flush_pending_stream_text(ctx);
    ctx->terminal_sent = true;

    // ONE authority for the split. The incremental splitter exists to decide
    // which channel each delta goes out on while the text is still arriving; it
    // is not a second opinion on the final answer. Re-splitting the accumulated
    // raw text through the same whole-text function the unary verb calls makes
    // the streaming terminal result byte-identical to the unary result for the
    // same generated text BY CONSTRUCTION. Accumulating the live segments
    // instead is what let the two drift — the stream kept trailing whitespace
    // the unary path trimmed, and the two disagreed about a second bare
    // `</think>` and about a second reasoning block.
    const char* split_answer = nullptr;
    size_t split_answer_len = 0;
    const char* split_reasoning = nullptr;
    size_t split_reasoning_len = 0;
    (void)rac_llm_extract_thinking_with_tags(
        ctx->raw_text.c_str(),
        ctx->thinking_open_tag.empty() ? nullptr : ctx->thinking_open_tag.c_str(),
        ctx->thinking_close_tag.empty() ? nullptr : ctx->thinking_close_tag.c_str(), &split_answer,
        &split_answer_len, &split_reasoning, &split_reasoning_len);
    // Written back so the completion/cancellation telemetry published after this
    // call reports the authoritative split rather than whatever the delta
    // boundaries happened to produce.
    ctx->response_text.assign(split_answer != nullptr ? split_answer : "", split_answer_len);
    ctx->thinking_text.assign(split_reasoning != nullptr ? split_reasoning : "",
                              split_reasoning_len);

    // Surface a structured tool call on LLMStreamEvent.tool_call
    // (proto field 18) when the streaming output contains one. The terminal
    // event still carries the same finish_reason / result; this emission is
    // an additional in-stream event with event_kind=LLM_STREAM_EVENT_KIND_TOOL_CALL
    // and tool_call=<parsed ToolCall>, mirroring the
    // TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED semantics from
    // tool_calling_session.cpp but on the canonical LLM stream so direct
    // consumers (Swift LLMStreamEvent.toolCall, Kotlin event.tool_call, etc.)
    // observe the structured payload without parsing the raw token text.
    if (error_message == nullptr || error_message[0] == '\0') {
        runanywhere::v1::ToolCall parsed_tool_call;
        if (parse_response_tool_call(ctx->response_text, &parsed_tool_call)) {
            dispatch_stream_event(ctx, /*token=*/"", /*is_final=*/false,
                                  runanywhere::v1::TOKEN_KIND_TOOL_CALL,
                                  /*finish_reason=*/nullptr, /*error_message=*/nullptr,
                                  /*result=*/nullptr, &parsed_tool_call);
        }
    }

    // LLMStreamFinalResult was deleted (idl/llm_service.proto): the stream's
    // terminal result is now the same LLMGenerationResult the unary call
    // returns, carried on LLMStreamEvent.result (fresh tag 22).
    LLMGenerationResult final_result;
    const std::string& answer_text = ctx->response_text;
    const std::string& reasoning_text = ctx->thinking_text;
    final_result.set_text(answer_text);
    if (!reasoning_text.empty()) {
        final_result.set_thinking_content(reasoning_text);
    }

    ctx->timing.started_ms = ctx->started_ms;
    ctx->timing.completed_ms = now_ms();
    StreamTimingMetrics timing = compute_stream_timing(ctx->timing);

    // Per-channel token counts. Apportioned by character ratio through the same
    // helper the unary path uses, so the two paths cannot disagree; the engine
    // does not tell us which side of `</think>` each delta fell on.
    int32_t reasoning_tokens = 0;
    int32_t content_tokens = ctx->timing.total_tokens;
    (void)rac_llm_split_thinking_tokens(ctx->timing.total_tokens, answer_text.c_str(),
                                        reasoning_text.empty() ? nullptr : reasoning_text.c_str(),
                                        &reasoning_tokens, &content_tokens);
    final_result.set_thinking_tokens(reasoning_tokens);
    final_result.set_response_tokens(content_tokens);
    rac::llm::set_content_rate(&timing, ctx->timing, content_tokens);

    auto* usage = final_result.mutable_usage();
    usage->set_input_tokens(ctx->prompt_tokens);
    usage->set_output_tokens(ctx->timing.total_tokens);
    usage->set_total_tokens(ctx->prompt_tokens + ctx->timing.total_tokens);
    // Honest provenance: true only when we fell back to estimate / delta-only.
    usage->set_counts_estimated(ctx->counts_estimated);
    final_result.set_generation_time_ms(static_cast<double>(timing.wall_ms));
    if (timing.ttft_ms > 0) {
        usage->set_ttft_ms(timing.ttft_ms);
    }
    if (timing.prefill_ms > 0) {
        usage->set_prefill_ms(timing.prefill_ms);
        final_result.set_prompt_eval_time_ms(timing.prefill_ms);
    }
    if (timing.decode_tokens_per_second > 0.0) {
        usage->set_decode_tokens_per_second(timing.decode_tokens_per_second);
    }
    // Wire the three fields that were previously computed and discarded (C3).
    if (timing.time_to_first_content_token_ms > 0) {
        usage->set_time_to_first_content_token_ms(timing.time_to_first_content_token_ms);
    }
    if (timing.content_tokens_per_second > 0.0) {
        usage->set_content_tokens_per_second(timing.content_tokens_per_second);
    }
    usage->set_batch_buffered(timing.batch_buffered);
    // Decode window is measured (first produced delta to last). When the
    // backend batch-buffered, report wall as the honest decode_time_ms so
    // consumers that only read decode_time_ms still see a usable figure;
    // the batch_buffered flag on TokenUsage tells them which window it is.
    if (timing.batch_buffered || timing.decode_ms <= 0) {
        final_result.set_decode_time_ms(timing.wall_ms);
    } else {
        final_result.set_decode_time_ms(timing.decode_ms);
    }
    // finish_reason widened from a bare string to the FinishReason enum
    // (idl/llm_options.proto). Map the producer's plain-English reason
    // through the same helper the serializer uses for LLMStreamEvent so the
    // unary and streaming paths agree on one vocabulary.
    final_result.set_finish_reason(static_cast<runanywhere::v1::FinishReason>(
        rac::llm::finish_reason_from_string((finish_reason != nullptr) && finish_reason[0] != '\0'
                                                ? finish_reason
                                                : "stop")));
    if ((error_message != nullptr) && error_message[0] != '\0') {
        rac::foundation::populate_sdk_error(final_result.mutable_error(),
                                            RAC_ERROR_GENERATION_FAILED);
        final_result.mutable_error()->set_message(error_message);
    }

    dispatch_stream_event(ctx, "", true, runanywhere::v1::TOKEN_KIND_ANSWER, finish_reason,
                          error_message, &final_result);
}

rac_bool_t stream_token_callback(const char* token, rac_bool_t is_final, const char* finish_reason, int32_t tokens_in_delta, void* user_data) {
    auto* ctx = static_cast<ProtoStreamContext*>(user_data);
    if (!ctx || !ctx->ref) {
        return RAC_FALSE;
    }
    if (rac::llm::lifecycle_llm_cancel_requested(ctx->ref)) {
        return RAC_FALSE;
    }

    if (is_final) {
        ctx->producer_final_seen = true;
        if (finish_reason != nullptr && finish_reason[0] != '\0') {
            ctx->producer_finish_reason = finish_reason;
        }
    }

    // Strip tokenizer-internal sentinels before the thinking splitter, the
    // accumulated answer, or the caller ever sees the chunk. The filter is
    // stateful because a backend is free to split `<|im_end|>` across two
    // callbacks and neither half is recognisable alone; `flush()` on the
    // terminal releases a held prefix that turned out to be ordinary text.
    // An empty final still has to reach the flush, so this runs before the
    // old "empty final, nothing to do" short-circuit — every delivery below
    // is already guarded on the cleaned text being non-empty.
    std::string cleaned = ctx->filter.feed(token ? token : "");
    if (is_final) {
        cleaned += ctx->filter.flush();
    }
    if (cleaned.empty()) {
        return RAC_TRUE;
    }

    // Timed HERE at production. Count via tokens_in_delta (may be >1 when the
    // backend coalesces; 0 means the engine could not count this callback).
    const int64_t produced_ms = now_ms();
    if (ctx->timing.first_token_ms == 0) {
        ctx->timing.first_token_ms = produced_ms;
    }
    ctx->timing.last_token_ms = produced_ms;
    if (tokens_in_delta > 0) {
        ctx->timing.total_tokens += tokens_in_delta;
        ctx->token_count = ctx->timing.total_tokens;
    }

    consume_thinking_aware_text(ctx, cleaned.c_str(), produced_ms);
    return RAC_TRUE;
}

#endif  // RAC_HAVE_PROTOBUF

template <typename Op, typename... Args>
rac_result_t call_lifecycle_op(Op op, Args&&... args) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)op;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rc = (ref.ops && (ref.ops->*op))
             ? (ref.ops->*op)(ref.impl, std::forward<Args>(args)...)
             : RAC_ERROR_NOT_SUPPORTED;
    rac::llm::release_lifecycle_llm(&ref);
    return rc;
#endif
}

}  // namespace

extern "C" {

rac_result_t rac_llm_generate_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                    rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "LLMGenerateRequest bytes are empty or too large");
    }

    LLMGenerateRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse LLMGenerateRequest");
    }
    // LLMGenerateRequest.prompt was deleted in favor of `repeated ChatMessage
    // messages` (idl/llm_service.proto): the current turn is the last message.
    const std::string prompt = current_prompt_from_messages(request);
    if (prompt.empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "LLMGenerateRequest.messages must end with a non-empty "
                                          "turn to answer");
    }

    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED, prompt.c_str(), nullptr,
                             nullptr, nullptr, ref.model_id, 0, 0, 0, ref.framework_name);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    std::string grammar_storage;
    std::vector<std::string> history_storage;
    std::vector<const char*> history_ptrs;
    std::string structured_error;
    rac_llm_options_t options =
        options_from_request(request, system_prompt, stop_storage, stop_ptrs, grammar_storage,
                             history_storage, history_ptrs, &structured_error);
    if (!structured_error.empty()) {
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          structured_error.c_str());
    }
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t raw{};
    // Apply the no-think directive at the prompt level when disable_thinking is
    // set (proto LLMGenerationOptions.disable_thinking). Telemetry/events below
    // keep the original prompt; only the engine sees the directive.
    const std::string effective_prompt = rac::llm::apply_no_think_directive(
        prompt, options.disable_thinking, ref.framework, ref.supports_thinking);
    const int64_t started = now_ms();
    rc = (ref.ops && ref.ops->generate)
             ? ref.ops->generate(ref.impl, effective_prompt.c_str(), &options, &raw)
             : RAC_ERROR_NOT_SUPPORTED;
    const int64_t elapsed = now_ms() - started;

    if (rc != RAC_SUCCESS) {
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED, prompt.c_str(),
                                 nullptr, nullptr, rac_error_message(rc), ref.model_id, 0, elapsed, 0,
                                 ref.framework_name);
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    // Sentinel-free before the thinking splitter runs, matching the streaming
    // sibling. A leaked `<|im_end|>` here is not cosmetic: this text is what
    // the non-streaming SDK verbs return and what the voice agent hands to
    // TTS, so the artifact was rendered *and* spoken on every SDK that calls
    // the handle-less ABI.
    const std::string clean_text = rac::tokens::strip_special_tokens(raw.text ? raw.text : "");
    const char* raw_text = clean_text.c_str();
    std::string thinking_open_tag;
    std::string thinking_close_tag;
    thinking_tags_from_request_or_model(request, ref, &thinking_open_tag, &thinking_close_tag);
    (void)rac_llm_extract_thinking_with_tags(
        raw_text, thinking_open_tag.empty() ? nullptr : thinking_open_tag.c_str(),
        thinking_close_tag.empty() ? nullptr : thinking_close_tag.c_str(), &response,
        &response_len, &thinking, &thinking_len);
    std::string response_text =
        response ? std::string(response, response_len) : std::string();
    const std::string thinking_text =
        thinking ? std::string(thinking, thinking_len) : std::string();
    const char* response_cstr = response_text.c_str();
    const char* thinking_cstr = thinking_text.empty() ? nullptr : thinking_text.c_str();

    int32_t thinking_tokens = 0;
    int32_t response_tokens = raw.completion_tokens;
    bool counts_estimated = false;
    if (raw.prompt_tokens <= 0) {
        raw.prompt_tokens = estimate_tokens(prompt.c_str());
        counts_estimated = true;
    }
    if (raw.completion_tokens <= 0) {
        raw.completion_tokens = clean_text.empty() ? 0 : estimate_tokens(clean_text.c_str());
        raw.total_tokens = raw.prompt_tokens + raw.completion_tokens;
        response_tokens = raw.completion_tokens;
        counts_estimated = true;
    } else if (raw.total_tokens <= 0) {
        raw.total_tokens = raw.prompt_tokens + raw.completion_tokens;
    }
    (void)rac_llm_split_thinking_tokens(raw.completion_tokens, response_cstr, thinking_cstr,
                                        &thinking_tokens, &response_tokens);

    LLMGenerationResult result;
    set_result_from_raw(ref, raw, response_cstr, response_text.size(), thinking_cstr,
                        thinking_text.size(), thinking_tokens, response_tokens, options.max_tokens,
                        &result);
    if (counts_estimated) {
        result.mutable_usage()->set_counts_estimated(true);
        if (result.has_performance() && result.performance().has_usage()) {
            result.mutable_performance()->mutable_usage()->set_counts_estimated(true);
        }
    }

    rac_structured_output_config_t structured_config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    std::string schema_storage;
    bool want_repair = false;
    if (request.has_options() && request.options().has_structured_output()) {
        const auto& so = request.options().structured_output();
        if (so.has_schema() && !so.schema().empty()) {
            schema_storage = so.schema();
            structured_config.json_schema = schema_storage.c_str();
        }
        structured_config.include_schema_in_prompt =
            so.has_include_schema_in_prompt() ? (so.include_schema_in_prompt() ? RAC_TRUE : RAC_FALSE)
                                              : RAC_TRUE;
        want_repair = so.has_mode() &&
                      so.mode() == runanywhere::v1::STRUCTURED_OUTPUT_MODE_REPAIR &&
                      structured_config.json_schema != nullptr;
    }
    set_structured_output_if_present(
        response_cstr, &result,
        structured_config.json_schema ? &structured_config : nullptr);

    // One-retry repair policy (commons-owned). Platform SDKs must not invent a
    // second repair pass around generate().
    if (want_repair && result.has_structured_output_validation() &&
        !result.structured_output_validation().is_valid()) {
        const std::string repair_prompt = rac::llm::structured_output_repair_prompt(
            prompt, response_text, schema_storage);
        const std::string effective_repair = rac::llm::apply_no_think_directive(
            repair_prompt, options.disable_thinking, ref.framework, ref.supports_thinking);
        rac_llm_result_free(&raw);
        raw = {};
        const rac_result_t repair_rc =
            (ref.ops && ref.ops->generate)
                ? ref.ops->generate(ref.impl, effective_repair.c_str(), &options, &raw)
                : RAC_ERROR_NOT_SUPPORTED;
        if (repair_rc == RAC_SUCCESS) {
            const std::string repair_clean =
                rac::tokens::strip_special_tokens(raw.text ? raw.text : "");
            response = nullptr;
            response_len = 0;
            thinking = nullptr;
            thinking_len = 0;
            (void)rac_llm_extract_thinking_with_tags(
                repair_clean.c_str(),
                thinking_open_tag.empty() ? nullptr : thinking_open_tag.c_str(),
                thinking_close_tag.empty() ? nullptr : thinking_close_tag.c_str(), &response,
                &response_len, &thinking, &thinking_len);
            response_text =
                response ? std::string(response, response_len) : std::string();
            const std::string repair_thinking =
                thinking ? std::string(thinking, thinking_len) : std::string();
            response_cstr = response_text.c_str();
            thinking_tokens = 0;
            response_tokens = raw.completion_tokens;
            (void)rac_llm_split_thinking_tokens(
                raw.completion_tokens, response_cstr,
                repair_thinking.empty() ? nullptr : repair_thinking.c_str(), &thinking_tokens,
                &response_tokens);
            result.Clear();
            set_result_from_raw(ref, raw, response_cstr, response_text.size(),
                                repair_thinking.empty() ? nullptr : repair_thinking.c_str(),
                                repair_thinking.size(), thinking_tokens, response_tokens,
                                options.max_tokens, &result);
            set_structured_output_if_present(response_cstr, &result, &structured_config,
                                             /*repair_attempted=*/true,
                                             /*repair_attempts=*/1);
        }
    } else if (result.has_structured_output_validation()) {
        result.mutable_structured_output_validation()->set_repair_attempted(false);
        result.mutable_structured_output_validation()->set_repair_attempts(0);
    }

    publish_generation_event(
        runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED, prompt.c_str(), nullptr, response_cstr,
        nullptr, ref.model_id, raw.completion_tokens,
        raw.total_time_ms > 0 ? raw.total_time_ms : elapsed, raw.prompt_tokens,
        ref.framework_name, static_cast<double>(raw.tokens_per_second),
        static_cast<double>(raw.time_to_first_token_ms), options.temperature, options.max_tokens,
        lifecycle_context_length(ref), /*is_streaming=*/false,
        /*prompt_eval_time_ms=*/static_cast<double>(raw.prompt_eval_time_ms));

    rac_llm_result_free(&raw);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_llm_generate_stream_proto(const uint8_t* request_proto_bytes,
                                           size_t request_proto_size,
                                           rac_llm_stream_proto_callback_fn callback,
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
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    LLMGenerateRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    // LLMGenerateRequest.prompt was deleted in favor of `repeated ChatMessage
    // messages` (idl/llm_service.proto): the current turn is the last message.
    const std::string prompt = current_prompt_from_messages(request);
    if (prompt.empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!ref.ops || !ref.ops->generate_stream) {
        rac::llm::release_lifecycle_llm(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED, prompt.c_str(), nullptr,
                             nullptr, nullptr, ref.model_id, 0, 0, 0, ref.framework_name);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    std::string grammar_storage;
    std::vector<std::string> history_storage;
    std::vector<const char*> history_ptrs;
    std::string structured_error;
    rac_llm_options_t options =
        options_from_request(request, system_prompt, stop_storage, stop_ptrs, grammar_storage,
                             history_storage, history_ptrs, &structured_error);
    if (!structured_error.empty()) {
        rac::llm::release_lifecycle_llm(&ref);
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    options.streaming_enabled = RAC_TRUE;

    ProtoStreamContext ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.started_ms = now_ms();
    ctx.prompt_tokens = 0;
    ctx.counts_estimated = true;
    ctx.emit_thoughts = request.has_options() && request.options().has_reasoning() &&
                        request.options().reasoning().include_in_output();
    ctx.request_id = request.request_id();
    ctx.conversation_id = request.conversation_id();
    bool template_prefills_open_tag = false;
    thinking_tags_from_request_or_model(request, ref, &ctx.thinking_open_tag,
                                        &ctx.thinking_close_tag, &template_prefills_open_tag);
    // A model-declared pair is tried first, with the built-ins kept behind it so
    // a model that ignores its own pattern still splits.
    if (!ctx.thinking_open_tag.empty() && !ctx.thinking_close_tag.empty()) {
        std::vector<rac::llm::ThinkingTagPair> pairs;
        pairs.push_back({ctx.thinking_open_tag, ctx.thinking_close_tag});
        for (auto& builtin : rac::llm::default_thinking_tag_pairs()) {
            pairs.push_back(std::move(builtin));
        }
        ctx.splitter.set_pairs(std::move(pairs));
        // Reasoning chat templates such as Qwen/Bonsai/maple may append the
        // opening tag to the PROMPT and generate only the reasoning body plus
        // the closing tag, so the stream can begin inside reasoning with nothing
        // in the text to say so.
        //
        // A declared pair does NOT prove that happened: normalize_thinking_
        // capability() fills a default `<think>`/`</think>` pattern into every
        // model with supports_thinking, so the pair is a capability. The typed
        // signal is ThinkingTagPattern.template_prefills_open_tag (plumbed from
        // the qhexrt bundle's gen_prefill, or the DeepSeek-R1-Distill name
        // heuristic). When that optional is true, assert start_inside_reasoning()
        // — live answer deltas must not wait on a hold. When unset, arm the
        // ambiguous HOLD: right when the model does reason (hold ends at
        // `</think>`), and complete (if late) when it does not. disable_thinking
        // means no reasoning is coming, so there is nothing to hold for.
        if (options.disable_thinking == RAC_FALSE) {
            if (template_prefills_open_tag) {
                ctx.splitter.start_inside_reasoning();
            } else {
                ctx.splitter.set_hold_ambiguous_prefix(true);
            }
        }
    }

    // Defensive: catch any C++ exception that escapes the engine vtable.
    // Each backend (llamacpp, onnx, etc.) already wraps its inference call in
    // try/catch, but we wrap here too so a misbehaving engine (or a future
    // backend that forgets) can never propagate `__cxa_throw` across the
    // extern "C" boundary into the platform SDK. On WASM this would surface
    // as an opaque `WebAssembly.Exception` (no `.message`) in JS; on native
    // SDKs it would be undefined behaviour through a C ABI return.
    const std::string effective_prompt = rac::llm::apply_no_think_directive(
        prompt, options.disable_thinking, ref.framework, ref.supports_thinking);
    // See rac_llm_stream_reset_final_signal() in rac_llm_service.h: reset
    // right before the call the same way rac_llm_generate_stream() does,
    // since this path calls ref.ops->generate_stream() directly rather than
    // through that wrapper.
    rac_llm_stream_reset_final_signal();
    try {
        rc = ref.ops->generate_stream(ref.impl, effective_prompt.c_str(), &options,
                                      stream_token_callback, &ctx);
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        rc = RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception escaped LLM engine generate_stream");
        rc = RAC_ERROR_INFERENCE_FAILED;
    }

    // Prefer engine stream totals; else delta accumulation / estimate.
    {
        int32_t resolved_prompt = 0;
        int32_t resolved_completion = 0;
        bool estimated = true;
        resolve_stream_token_counts(ref.ops, ref.impl, prompt.c_str(), ctx.raw_text.c_str(),
                                    ctx.timing.total_tokens, &resolved_prompt, &resolved_completion,
                                    &estimated);
        ctx.prompt_tokens = resolved_prompt;
        ctx.timing.total_tokens = resolved_completion;
        ctx.token_count = resolved_completion;
        ctx.counts_estimated = estimated;
    }

    const bool cancelled = rac::llm::lifecycle_llm_cancel_requested(&ref) ||
                           rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        dispatch_terminal_once(&ctx, "cancelled", nullptr);
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCELLED,
                                 prompt.c_str(), nullptr, ctx.response_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count, now_ms() - ctx.started_ms,
                                 0, ref.framework_name);
        rc = RAC_SUCCESS;
    } else if (rc != RAC_SUCCESS) {
        dispatch_terminal_once(&ctx, "error", rac_error_message(rc));
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 prompt.c_str(), nullptr, ctx.response_text.c_str(),
                                 rac_error_message(rc), ref.model_id, ctx.token_count,
                                 now_ms() - ctx.started_ms, 0, ref.framework_name);
    } else {
        // Prefer producer finish_reason from the widened stream callback,
        // then max_tokens → "length", then the side-channel fallback, else
        // "unknown". Do not invent "stop" with zero evidence.
        const char* finish_reason;
        if (options.max_tokens > 0 && ctx.token_count >= options.max_tokens) {
            finish_reason = "length";
        } else if (!ctx.producer_finish_reason.empty()) {
            finish_reason = ctx.producer_finish_reason.c_str();
        } else if (ctx.producer_final_seen || rac_llm_stream_final_signal_seen() == RAC_TRUE) {
            finish_reason = "stop";
        } else {
            finish_reason = "unknown";
        }
        dispatch_terminal_once(&ctx, finish_reason, nullptr);
        const int64_t stream_elapsed = now_ms() - ctx.started_ms;
        // The same observations dispatch_terminal_once already used, so the
        // telemetry event and the terminal result cannot report different rates.
        const StreamTimingMetrics stream_timing = compute_stream_timing(ctx.timing);
        // GENERATION_EVENT_KIND_STREAM_COMPLETED was deleted (idl/sdk_events.proto):
        // streaming completion now folds into COMPLETED, discriminated by
        // is_streaming below (matches the non-streaming completion event).
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED,
                                 prompt.c_str(), nullptr, ctx.response_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count, stream_elapsed,
                                 ctx.prompt_tokens, ref.framework_name,
                                 stream_timing.decode_tokens_per_second,
                                 static_cast<double>(stream_timing.ttft_ms), options.temperature,
                                 options.max_tokens, lifecycle_context_length(ref),
                                 /*is_streaming=*/true,
                                 /*prompt_eval_time_ms=*/static_cast<double>(stream_timing.prefill_ms));
    }

    rac::llm::release_lifecycle_llm(&ref);
    return rc;
#endif
}

rac_result_t rac_llm_cancel_proto(rac_proto_buffer_t* out_event) {
    if (!out_event) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_event);
#else
    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        SDKEvent failed = make_cancellation_event(runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED,
                                                  "no lifecycle LLM model loaded", RAC_TRUE,
                                                  runanywhere::v1::ERROR_SEVERITY_ERROR);
        (void)publish_sdk_event(failed);
        return rac_proto_buffer_set_error(out_event, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::request_lifecycle_llm_cancel(&ref);
    // GENERATION_EVENT_KIND_CANCEL_REQUESTED was deleted from GenerationEventKind
    // (idl/sdk_events.proto): cancel-requested now travels only on the
    // canonical CancellationEvent taxonomy below.
    SDKEvent requested = make_cancellation_event(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED,
                                                 "user_requested", RAC_TRUE,
                                                 runanywhere::v1::ERROR_SEVERITY_INFO);
    (void)publish_sdk_event(requested);
    if (ref.ops && ref.ops->cancel) {
        rc = ref.ops->cancel(ref.impl);
    } else {
        rc = RAC_SUCCESS;
    }

    SDKEvent event = make_cancellation_event(
        rc == RAC_SUCCESS ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                          : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED,
        rc == RAC_SUCCESS ? "user_requested" : rac_error_message(rc), RAC_TRUE,
        rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                          : runanywhere::v1::ERROR_SEVERITY_ERROR);
    (void)publish_sdk_event(event);
    rac_result_t copy_rc = copy_proto(event, out_event);
    rac::llm::release_lifecycle_llm(&ref);
    return rc == RAC_SUCCESS ? copy_rc : rc;
#endif
}


/** Seed the lifecycle-owned LLM's adaptive context with a system prompt. */
rac_result_t rac_llm_inject_system_prompt_lifecycle(const char* prompt) {
    if (!prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return call_lifecycle_op(&rac_llm_service_ops_t::inject_system_prompt, prompt);
}

/** Append text to the lifecycle-owned LLM's adaptive context. */
rac_result_t rac_llm_append_context_lifecycle(const char* text) {
    if (!text) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return call_lifecycle_op(&rac_llm_service_ops_t::append_context, text);
}

/** Generate a protobuf result from the lifecycle-owned LLM's adaptive context. */
rac_result_t rac_llm_generate_from_context_proto(const uint8_t* request_proto_bytes,
                                                 size_t request_proto_size,
                                                 rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "LLMGenerateRequest bytes are empty or too large");
    }

    LLMGenerateRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse LLMGenerateRequest");
    }
    // LLMGenerateRequest.prompt was deleted in favor of `repeated ChatMessage
    // messages` (idl/llm_service.proto): the query for this adaptive-context
    // call is the last message's content.
    const std::string query = current_prompt_from_messages(request);

    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED, query.c_str(), nullptr,
                             nullptr, nullptr, ref.model_id, 0, 0);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    std::string grammar_storage;
    std::vector<std::string> history_storage;
    std::vector<const char*> history_ptrs;
    std::string structured_error;
    rac_llm_options_t options = options_from_request(
        request, system_prompt, stop_storage, stop_ptrs, grammar_storage, history_storage,
        history_ptrs, &structured_error);
    if (!structured_error.empty()) {
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          structured_error.c_str());
    }
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t raw{};
    const std::string effective_query = rac::llm::apply_no_think_directive(
        query, options.disable_thinking, ref.framework, ref.supports_thinking);
    const int64_t started = now_ms();
    rc = (ref.ops && ref.ops->generate_from_context)
             ? ref.ops->generate_from_context(ref.impl, effective_query.c_str(), &options, &raw)
             : RAC_ERROR_NOT_SUPPORTED;
    const int64_t elapsed = now_ms() - started;

    if (rc != RAC_SUCCESS) {
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED, query.c_str(),
                                 nullptr, nullptr, rac_error_message(rc), ref.model_id, 0, elapsed);
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    // Sentinel-free before the thinking splitter runs, matching the streaming
    // sibling. A leaked `<|im_end|>` here is not cosmetic: this text is what
    // the non-streaming SDK verbs return and what the voice agent hands to
    // TTS, so the artifact was rendered *and* spoken on every SDK that calls
    // the handle-less ABI.
    const std::string clean_text = rac::tokens::strip_special_tokens(raw.text ? raw.text : "");
    const char* raw_text = clean_text.c_str();
    std::string thinking_open_tag;
    std::string thinking_close_tag;
    thinking_tags_from_request_or_model(request, ref, &thinking_open_tag, &thinking_close_tag);
    (void)rac_llm_extract_thinking_with_tags(
        raw_text, thinking_open_tag.empty() ? nullptr : thinking_open_tag.c_str(),
        thinking_close_tag.empty() ? nullptr : thinking_close_tag.c_str(), &response,
        &response_len, &thinking, &thinking_len);
    const std::string response_text =
        response ? std::string(response, response_len) : std::string();
    const std::string thinking_text =
        thinking ? std::string(thinking, thinking_len) : std::string();
    const char* response_cstr = response_text.c_str();
    const char* thinking_cstr = thinking_text.empty() ? nullptr : thinking_text.c_str();

    int32_t thinking_tokens = 0;
    int32_t response_tokens = raw.completion_tokens;
    (void)rac_llm_split_thinking_tokens(raw.completion_tokens, response_cstr, thinking_cstr,
                                        &thinking_tokens, &response_tokens);

    LLMGenerationResult result;
    set_result_from_raw(ref, raw, response_cstr, response_text.size(), thinking_cstr,
                        thinking_text.size(), thinking_tokens, response_tokens, options.max_tokens,
                        &result);
    set_structured_output_if_present(response_cstr, &result);

    publish_generation_event(
        runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED, query.c_str(), nullptr, response_cstr,
        nullptr, ref.model_id, raw.completion_tokens,
        raw.total_time_ms > 0 ? raw.total_time_ms : elapsed, raw.prompt_tokens);

    rac_llm_result_free(&raw);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(result, out_result);
#endif
}

/** Clear adaptive context retained by the lifecycle-owned LLM. */
rac_result_t rac_llm_clear_context_lifecycle(void) {
    return call_lifecycle_op(&rac_llm_service_ops_t::clear_context);
}

}  // extern "C"
