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
#include <atomic>
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
#include "features/llm/rac_llm_lifecycle_bridge.h"
// BUG-STREAMING-001: the canonical 13-field LLM stream emitter shared with the
// registry-backed path (rac_llm_stream.cpp). The component section invokes
// `rac::llm::dispatch_llm_stream_event()` once per token and once on terminal
// events so any collectors registered via rac_llm_set_stream_proto_callback()
// see the full decoded sequence. The proto section calls
// `rac::llm::serialize_llm_stream_event()` directly.
#include "features/llm/llm_thinking_directive_internal.h"
#include "features/llm/rac_llm_stream_internal.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_component.h"
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
    m.set_framework(rac::events::framework_to_proto_int(framework));
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
    g.set_framework(rac::events::framework_to_proto_int(framework));
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
                                   int32_t max_tokens, int32_t context_length) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED);
    if (model_id)
        g.set_model_id(model_id);
    if (model_name)
        g.set_model_name(model_name);
    g.set_input_tokens(input_tokens);
    g.set_tokens_used(output_tokens);
    g.set_latency_ms(static_cast<int64_t>(duration_ms));
    g.set_duration_ms(duration_ms);
    g.set_tokens_per_second(tokens_per_second);
    g.set_is_streaming(is_streaming);
    g.set_time_to_first_token_ms(static_cast<int64_t>(time_to_first_token_ms));
    g.set_framework(rac::events::framework_to_proto_int(framework));
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
    g.set_first_token_latency_ms(static_cast<int64_t>(time_to_first_token_ms));
    g.set_framework(rac::events::framework_to_proto_int(framework));
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id);
}

void emit_llm_streaming_update(const char* generation_id, int32_t tokens_generated) {
    runanywhere::v1::GenerationEvent g;
    g.set_kind(runanywhere::v1::GENERATION_EVENT_KIND_STREAMING_UPDATE);
    g.set_tokens_count(tokens_generated);
    // STREAMING_UPDATE is too chatty for telemetry — PUBLIC stream only.
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_LLM,
                                      runanywhere::v1::EVENT_CATEGORY_LLM, std::move(g),
                                      generation_id, rac::events::legacy_destination_public());
}

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// EOS / SPECIAL TOKEN STRIPPING
// =============================================================================

/**
 * Strip tokenizer-internal special tokens from a streamed LLM token before
 * the value reaches user callbacks or downstream proto subscribers.
 *
 * Backends occasionally leak end-of-utterance / end-of-text sentinels into
 * the streaming callback when the runtime swallow path missed them (notably
 * SmolVLM, Qwen-VL, Llama-3 — see B-RN-14-001). Without this
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
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_generation_completed(
        generation_id.c_str(), model_id, model_name, estimate_tokens(prompt),
        out_result->completion_tokens, static_cast<double>(total_time_ms), tokens_per_second,
        /*is_streaming=*/false, /*time_to_first_token_ms=*/0, component->actual_framework,
        effective_options->temperature, effective_options->max_tokens, context_length);
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

    // Component handle for the proto-byte stream
    // dispatcher. Each delivered token fires a LLMStreamEvent to any
    // collector registered via rac_llm_set_stream_proto_callback().
    rac_handle_t component_handle;
};

/**
 * Internal token callback that wraps user callback and tracks metrics.
 *
 * Every emitted token is run through
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

    // Accumulate text and track token count. Only the cleaned text reaches
    // ctx->full_text — the raw backend token is intentionally discarded so
    // downstream consumers (e.g. complete_callback's final_result.text)
    // never see sentinel artifacts either.
    if (!cleaned_empty) {
        ctx->full_text += cleaned;
        ctx->token_count++;

        // Emit streaming update event (every 10 tokens to avoid spam)
        if (ctx->token_count % 10 == 0) {
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
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name, "No model loaded");
#endif

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
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name,
                                   "Streaming not supported");
#endif

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
    ctx.prompt_tokens = estimate_tokens(prompt);
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

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("LLM.Component", "Streaming generation failed");
        rac_lifecycle_track_error(component->lifecycle, result, "generateStream");

        // Emit generation failed event
#if defined(RAC_HAVE_PROTOBUF)
        emit_llm_generation_failed(generation_id.c_str(), model_id, model_name,
                                   "Streaming generation failed");
#endif

        // Terminal error event on the proto stream.
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
#if defined(RAC_HAVE_PROTOBUF)
    emit_llm_generation_completed(
        generation_id.c_str(), model_id, model_name, final_result.prompt_tokens,
        final_result.completion_tokens, static_cast<double>(total_time_ms), tokens_per_second,
        /*is_streaming=*/true, ttft_ms, component->actual_framework, effective_options->temperature,
        effective_options->max_tokens, context_length);
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
using runanywhere::v1::LLMStreamFinalResult;
using runanywhere::v1::SDKEvent;
using runanywhere::v1::TokenKind;

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
                              const char* framework_name = nullptr,
                              double tokens_per_second = 0.0, double ttft_ms = 0.0,
                              float temperature = -1.0f, int32_t max_tokens = 0,
                              int32_t context_length = 0, bool is_streaming = false) {
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
        generation->set_response(response);
    }
    if ((error != nullptr) && error[0] != '\0') {
        generation->set_error(error);
    }
    if ((model_id != nullptr) && model_id[0] != '\0') {
        generation->set_model_id(model_id);
    }
    if (token_count > 0) {
        generation->set_tokens_count(token_count);
        generation->set_tokens_used(token_count);
    }
    if (latency_ms > 0) {
        generation->set_latency_ms(latency_ms);
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

// Pick the canonical system_prompt from the embedded
// LLMGenerationOptions when set, falling back to the legacy inline field.
std::string system_prompt_from_request(const LLMGenerateRequest& request) {
    if (request.has_options() && request.options().has_system_prompt() &&
        !request.options().system_prompt().empty()) {
        return request.options().system_prompt();
    }
    return request.system_prompt();
}

// Fills `options` from `request`. The caller-owned `stop_storage`/`stop_ptrs`
// must outlive every generate/generate_stream dispatch that observes
// `options.stop_sequences` — they hold the backing memory the C ABI points
// into. Mirrors RALLMTypes+CppBridge.swift toRALLMGenerateRequest which
// copies stopSequences into the canonical proto request.
//
// Prefer values from the canonical `request.options()` embedded
// LLMGenerationOptions message when set; fall back to the legacy inline
// scalar fields for backwards compatibility with callers that have not
// yet migrated.
rac_llm_options_t options_from_request(const LLMGenerateRequest& request,
                                       const std::string& system_prompt,
                                       std::vector<std::string>& stop_storage,
                                       std::vector<const char*>& stop_ptrs,
                                       std::string& grammar_storage,
                                       std::vector<std::string>& history_storage,
                                       std::vector<const char*>& history_ptrs) {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;

    const bool has_options = request.has_options();
    const auto& opts = request.options();

    // max_tokens proto3 zero means "unset → engine default" (idl/llm_options.proto:45-47).
    const int max_tokens =
        (has_options && opts.max_tokens() > 0) ? opts.max_tokens() : request.max_tokens();
    if (max_tokens > 0) {
        options.max_tokens = max_tokens;
    }

    // temperature: when the canonical LLMGenerationOptions is set, pass its value through
    // unconditionally so the documented greedy-decoding sentinel (0.0) reaches the engine
    // (idl/llm_options.proto:49). Mirrors RALLMTypes+CppBridge.swift:53. The legacy inline
    // scalar still uses `> 0.0f` so an unmigrated caller that left the field zero gets the
    // engine default (0.8) instead of accidental greedy decoding.
    if (has_options) {
        options.temperature = std::clamp(opts.temperature(), 0.0f, 2.0f);
    } else if (request.temperature() > 0.0f) {
        options.temperature = std::clamp(request.temperature(), 0.0f, 2.0f);
    }

    // top_p: proto3 zero is the unset sentinel, 1.0 means no truncation
    // (idl/llm_options.proto:53). Gate both canonical and legacy fields so a
    // canonical-only knob (for example disable_thinking) does not accidentally
    // override the engine default with top_p=0.
    if (has_options && opts.top_p() > 0.0f) {
        options.top_p = opts.top_p();
    } else if (request.top_p() > 0.0f) {
        options.top_p = request.top_p();
    }

    // Thread the remaining sampling knobs the proto exposes
    // (idl/llm_options.proto) into the C ABI so they reach the engine vtable.
    // For every field except repetition_penalty the proto3 zero IS the
    // documented "disabled" sentinel, so passing it through is identical to the
    // struct default. repetition_penalty uses 1.0 = "no penalty"; proto3 zero
    // means unset, so only override when positive (mirrors Swift's
    // RALLMTypes+CppBridge defaults, which carry repetitionPenalty=1.0).
    // Prefer the canonical embedded options; fall back to the legacy inline
    // scalars for callers that have not migrated to `request.options()`.
    options.top_k = has_options ? opts.top_k() : request.top_k();
    const float repetition_penalty =
        has_options ? opts.repetition_penalty() : request.repetition_penalty();
    if (repetition_penalty > 0.0f) {
        options.repetition_penalty = repetition_penalty;
    }
    options.frequency_penalty =
        has_options ? opts.frequency_penalty() : request.frequency_penalty();
    options.presence_penalty = has_options ? opts.presence_penalty() : request.presence_penalty();
    options.min_p = has_options ? opts.min_p() : request.min_p();
    options.seed = has_options ? opts.seed() : request.seed();
    options.n_threads = has_options ? opts.n_threads() : request.n_threads();
    options.disable_thinking = (has_options && opts.disable_thinking()) ? RAC_TRUE : RAC_FALSE;

    grammar_storage = has_options ? opts.grammar() : request.grammar();
    options.grammar = grammar_storage.empty() ? nullptr : grammar_storage.c_str();

    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    stop_storage.clear();
    stop_ptrs.clear();

    const auto& canonical_stop_sequences = (has_options && opts.stop_sequences_size() > 0)
                                               ? opts.stop_sequences()
                                               : request.stop_sequences();
    const int stop_count = canonical_stop_sequences.size();
    if (stop_count > 0) {
        stop_storage.reserve(static_cast<size_t>(stop_count));
        for (const auto& seq : canonical_stop_sequences) {
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

    // Prior conversation turns (idl-chat: LLMGenerateRequest.history, repeated
    // ChatMessage). The C ABI still carries a role-less alternating string
    // array, so normalize the proto roles before flattening: keep only
    // user/assistant turns, drop leading assistant turns, coalesce duplicate
    // same-role turns, and drop a trailing user turn so the current prompt
    // remains the next user message.
    history_storage.clear();
    history_ptrs.clear();
    const int history_count = request.history_size();
    if (history_count > 0) {
        history_storage.reserve(static_cast<size_t>(history_count));
        runanywhere::v1::MessageRole last_role =
            runanywhere::v1::MESSAGE_ROLE_UNSPECIFIED;
        for (const auto& msg : request.history()) {
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
        if (last_role == runanywhere::v1::MESSAGE_ROLE_USER && !history_storage.empty()) {
            history_storage.pop_back();
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

void set_result_from_raw(const rac::llm::LifecycleLlmRef& ref, const rac_llm_result_t& raw,
                         const char* response, size_t response_len, const char* thinking,
                         size_t thinking_len, int32_t thinking_tokens, int32_t response_tokens,
                         int32_t requested_max_tokens, LLMGenerationResult* out) {
    out->set_text(response ? std::string(response, response_len) : std::string());
    if (thinking && thinking_len > 0) {
        out->set_thinking_content(std::string(thinking, thinking_len));
    }
    out->set_input_tokens(raw.prompt_tokens);
    out->set_tokens_generated(raw.completion_tokens);
    out->set_total_tokens(raw.total_tokens);
    out->set_model_used(ref.model_id ? ref.model_id : "");
    out->set_generation_time_ms(static_cast<double>(raw.total_time_ms));
    if (raw.time_to_first_token_ms > 0) {
        out->set_ttft_ms(static_cast<double>(raw.time_to_first_token_ms));
    }
    out->set_tokens_per_second(static_cast<double>(raw.tokens_per_second));
    if ((ref.framework_name != nullptr) && ref.framework_name[0] != '\0') {
        out->set_framework(ref.framework_name);
    }
    // BUG-STREAMING-003: emit finish_reason="length" when max_tokens was exhausted
    // (matches OpenAI chat.completions contract — proto is modeled after it).
    out->set_finish_reason(
        (requested_max_tokens > 0 && raw.completion_tokens >= requested_max_tokens) ? "length"
                                                                                    : "stop");
    out->set_thinking_tokens(thinking_tokens);
    out->set_response_tokens(response_tokens);
    out->set_executed_on(runanywhere::v1::EXECUTION_TARGET_ON_DEVICE);

    auto* perf = out->mutable_performance();
    perf->set_latency_ms(raw.total_time_ms);
    perf->set_throughput_tokens_per_sec(raw.tokens_per_second);
    perf->set_prompt_tokens(raw.prompt_tokens);
    perf->set_completion_tokens(raw.completion_tokens);
}

void set_structured_output_if_present(const char* response, LLMGenerationResult* out) {
    if (!response || !out) {
        return;
    }
    rac_structured_output_validation_t validation{};
    if (rac_structured_output_validate(response, nullptr, &validation) == RAC_SUCCESS) {
        if (validation.is_valid == RAC_TRUE && validation.extracted_json) {
            out->set_json_output(validation.extracted_json);
            auto* structured = out->mutable_structured_output_validation();
            structured->set_is_valid(true);
            structured->set_contains_json(true);
            structured->set_raw_output(response);
            structured->set_extracted_json(validation.extracted_json);
        } else if (validation.error_message) {
            auto* structured = out->mutable_structured_output_validation();
            structured->set_is_valid(false);
            structured->set_contains_json(false);
            structured->set_raw_output(response);
            structured->set_error_message(validation.error_message);
        }
    }
    rac_structured_output_validation_free(&validation);
}

struct ProtoStreamContext {
    rac_llm_stream_proto_callback_fn callback = nullptr;
    void* user_data = nullptr;
    rac::llm::LifecycleLlmRef* ref = nullptr;
    uint64_t seq = 0;
    bool terminal_sent = false;
    bool first_token_sent = false;
    bool inside_thinking = false;
    bool emit_thoughts = false;
    int64_t started_ms = 0;
    int64_t first_token_ms = 0;
    int32_t prompt_tokens = 0;
    int32_t token_count = 0;
    std::string request_id;
    std::string conversation_id;
    std::string raw_text;
    std::string pending_text;
    std::string response_text;
    std::string thinking_text;
};

size_t matching_tag_suffix_len(const std::string& text, const char* const* tags,
                               size_t tags_count) {
    size_t best = 0;
    for (size_t i = 0; i < tags_count; ++i) {
        const char* tag = tags[i];
        const size_t tag_len = std::strlen(tag);
        const size_t max_len = std::min(tag_len - 1, text.size());
        for (size_t len = 1; len <= max_len; ++len) {
            if (std::memcmp(text.data() + text.size() - len, tag, len) == 0) {
                best = std::max(best, len);
            }
        }
    }
    return best;
}

size_t find_earliest_tag(const std::string& text, const char* const* tags, size_t tags_count,
                         const char** out_tag) {
    size_t best = std::string::npos;
    const char* best_tag = nullptr;
    for (size_t i = 0; i < tags_count; ++i) {
        const size_t pos = text.find(tags[i]);
        if (pos != std::string::npos && pos < best) {
            best = pos;
            best_tag = tags[i];
        }
    }
    if (out_tag) {
        *out_tag = best_tag;
    }
    return best;
}

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
                           const LLMStreamFinalResult* result = nullptr,
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
        if (!ctx->emit_thoughts) {
            return;
        }
    } else {
        ctx->response_text += token;
    }

    ctx->token_count += 1;
    if (!ctx->first_token_sent) {
        ctx->first_token_sent = true;
        ctx->first_token_ms = now_ms();
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED,
                                 nullptr, token.c_str(), nullptr, nullptr, ctx->ref->model_id, 1,
                                 ctx->first_token_ms - ctx->started_ms);
    }
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED, nullptr,
                             token.c_str(), nullptr, nullptr, ctx->ref->model_id, ctx->token_count,
                             0);
    dispatch_stream_event(ctx, token.c_str(), false, kind, nullptr, nullptr);
}

void consume_thinking_aware_text(ProtoStreamContext* ctx, const char* token) {
    static const char* const kOpenTags[] = {"<think>", "<thinking>"};
    static const char* const kCloseTags[] = {"</think>", "</thinking>"};
    if (!ctx || !token || token[0] == '\0') {
        return;
    }

    ctx->raw_text += token;
    ctx->pending_text += token;
    while (!ctx->pending_text.empty()) {
        if (ctx->inside_thinking) {
            const char* close_tag = nullptr;
            const size_t close_pos =
                find_earliest_tag(ctx->pending_text, kCloseTags,
                                  sizeof(kCloseTags) / sizeof(kCloseTags[0]), &close_tag);
            if (close_pos != std::string::npos) {
                emit_stream_segment(ctx, ctx->pending_text.substr(0, close_pos),
                                    runanywhere::v1::TOKEN_KIND_THOUGHT);
                ctx->pending_text.erase(0, close_pos + std::strlen(close_tag));
                ctx->inside_thinking = false;
                continue;
            }

            const size_t keep = matching_tag_suffix_len(ctx->pending_text, kCloseTags,
                                                        sizeof(kCloseTags) / sizeof(kCloseTags[0]));
            const size_t emit_len = ctx->pending_text.size() - keep;
            if (emit_len == 0) {
                break;
            }
            emit_stream_segment(ctx, ctx->pending_text.substr(0, emit_len),
                                runanywhere::v1::TOKEN_KIND_THOUGHT);
            ctx->pending_text.erase(0, emit_len);
            continue;
        }

        const char* open_tag = nullptr;
        const size_t open_pos = find_earliest_tag(
            ctx->pending_text, kOpenTags, sizeof(kOpenTags) / sizeof(kOpenTags[0]), &open_tag);
        if (open_pos != std::string::npos) {
            emit_stream_segment(ctx, ctx->pending_text.substr(0, open_pos),
                                runanywhere::v1::TOKEN_KIND_ANSWER);
            ctx->pending_text.erase(0, open_pos + std::strlen(open_tag));
            ctx->inside_thinking = true;
            continue;
        }

        const size_t keep = matching_tag_suffix_len(ctx->pending_text, kOpenTags,
                                                    sizeof(kOpenTags) / sizeof(kOpenTags[0]));
        const size_t emit_len = ctx->pending_text.size() - keep;
        if (emit_len == 0) {
            break;
        }
        emit_stream_segment(ctx, ctx->pending_text.substr(0, emit_len),
                            runanywhere::v1::TOKEN_KIND_ANSWER);
        ctx->pending_text.erase(0, emit_len);
    }
}

void flush_pending_stream_text(ProtoStreamContext* ctx) {
    if (!ctx || ctx->pending_text.empty()) {
        return;
    }
    emit_stream_segment(ctx, ctx->pending_text,
                        ctx->inside_thinking ? runanywhere::v1::TOKEN_KIND_THOUGHT
                                             : runanywhere::v1::TOKEN_KIND_ANSWER);
    ctx->pending_text.clear();
}

void dispatch_terminal_once(ProtoStreamContext* ctx, const char* finish_reason,
                            const char* error_message) {
    if (!ctx || ctx->terminal_sent) {
        return;
    }
    flush_pending_stream_text(ctx);
    ctx->terminal_sent = true;

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

    LLMStreamFinalResult final_result;
    final_result.set_text(ctx->response_text);
    if (!ctx->thinking_text.empty()) {
        final_result.set_thinking_content(ctx->thinking_text);
    }
    final_result.set_prompt_tokens(ctx->prompt_tokens);
    final_result.set_completion_tokens(ctx->token_count);
    final_result.set_total_tokens(ctx->prompt_tokens + ctx->token_count);
    const int64_t total_time_ms = now_ms() - ctx->started_ms;
    final_result.set_total_time_ms(total_time_ms);
    if (ctx->first_token_ms > 0) {
        final_result.set_time_to_first_token_ms(ctx->first_token_ms - ctx->started_ms);
    }
    if (total_time_ms > 0 && ctx->token_count > 0) {
        final_result.set_tokens_per_second(static_cast<float>(
            static_cast<double>(ctx->token_count) / (static_cast<double>(total_time_ms) / 1000.0)));
    }
    final_result.set_finish_reason(
        (finish_reason != nullptr) && finish_reason[0] != '\0' ? finish_reason : "stop");
    if ((error_message != nullptr) && error_message[0] != '\0') {
        final_result.set_error_message(error_message);
    }

    dispatch_stream_event(ctx, "", true, runanywhere::v1::TOKEN_KIND_ANSWER, finish_reason,
                          error_message, &final_result);
}

rac_bool_t stream_token_callback(const char* token, void* user_data) {
    auto* ctx = static_cast<ProtoStreamContext*>(user_data);
    if (!ctx || !ctx->ref) {
        return RAC_FALSE;
    }
    if (rac::llm::lifecycle_llm_cancel_requested(ctx->ref)) {
        return RAC_FALSE;
    }

    const char* safe_token = token ? token : "";
    consume_thinking_aware_text(ctx, safe_token);
    return RAC_TRUE;
}

#endif  // RAC_HAVE_PROTOBUF

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
    if (request.prompt().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "LLMGenerateRequest.prompt is required");
    }

    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED,
                             request.prompt().c_str(), nullptr, nullptr, nullptr, ref.model_id, 0, 0,
                             0, ref.framework_name);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    std::string grammar_storage;
    std::vector<std::string> history_storage;
    std::vector<const char*> history_ptrs;
    rac_llm_options_t options = options_from_request(
        request, system_prompt, stop_storage, stop_ptrs, grammar_storage, history_storage,
        history_ptrs);
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t raw{};
    // Apply the no-think directive at the prompt level when disable_thinking is
    // set (proto LLMGenerationOptions.disable_thinking). Telemetry/events below
    // keep the original prompt; only the engine sees the directive.
    const std::string effective_prompt =
        rac::llm::apply_no_think_directive(request.prompt(), options.disable_thinking);
    const int64_t started = now_ms();
    rc = (ref.ops && ref.ops->generate)
             ? ref.ops->generate(ref.impl, effective_prompt.c_str(), &options, &raw)
             : RAC_ERROR_NOT_SUPPORTED;
    const int64_t elapsed = now_ms() - started;

    if (rc != RAC_SUCCESS) {
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 request.prompt().c_str(), nullptr, nullptr, rac_error_message(rc),
                                 ref.model_id, 0, elapsed, 0, ref.framework_name);
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    const char* raw_text = raw.text ? raw.text : "";
    (void)rac_llm_extract_thinking(raw_text, &response, &response_len, &thinking, &thinking_len);

    int32_t thinking_tokens = 0;
    int32_t response_tokens = raw.completion_tokens;
    (void)rac_llm_split_thinking_tokens(raw.completion_tokens, response, thinking, &thinking_tokens,
                                        &response_tokens);

    LLMGenerationResult result;
    set_result_from_raw(ref, raw, response, response_len, thinking, thinking_len, thinking_tokens,
                        response_tokens, options.max_tokens, &result);
    set_structured_output_if_present(response, &result);

    publish_generation_event(
        runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED, request.prompt().c_str(), nullptr,
        response, nullptr, ref.model_id, raw.completion_tokens,
        raw.total_time_ms > 0 ? raw.total_time_ms : elapsed,
        raw.prompt_tokens > 0 ? raw.prompt_tokens : estimate_tokens(request.prompt().c_str()),
        ref.framework_name, static_cast<double>(raw.tokens_per_second),
        static_cast<double>(raw.time_to_first_token_ms), options.temperature, options.max_tokens,
        lifecycle_context_length(ref), /*is_streaming=*/false);

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
    if (request.prompt().empty()) {
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
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED,
                             request.prompt().c_str(), nullptr, nullptr, nullptr, ref.model_id, 0, 0,
                             0, ref.framework_name);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    std::string grammar_storage;
    std::vector<std::string> history_storage;
    std::vector<const char*> history_ptrs;
    rac_llm_options_t options = options_from_request(
        request, system_prompt, stop_storage, stop_ptrs, grammar_storage, history_storage,
        history_ptrs);
    options.streaming_enabled = RAC_TRUE;

    ProtoStreamContext ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.started_ms = now_ms();
    ctx.prompt_tokens = estimate_tokens(request.prompt().c_str());
    ctx.emit_thoughts = request.emit_thoughts();
    ctx.request_id = request.request_id();
    ctx.conversation_id = request.conversation_id();

    // Defensive: catch any C++ exception that escapes the engine vtable.
    // Each backend (llamacpp, onnx, etc.) already wraps its inference call in
    // try/catch, but we wrap here too so a misbehaving engine (or a future
    // backend that forgets) can never propagate `__cxa_throw` across the
    // extern "C" boundary into the platform SDK. On WASM this would surface
    // as an opaque `WebAssembly.Exception` (no `.message`) in JS; on native
    // SDKs it would be undefined behaviour through a C ABI return.
    const std::string effective_prompt =
        rac::llm::apply_no_think_directive(request.prompt(), options.disable_thinking);
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

    const bool cancelled = rac::llm::lifecycle_llm_cancel_requested(&ref) ||
                           rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        dispatch_terminal_once(&ctx, "cancelled", nullptr);
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCELLED,
                                 request.prompt().c_str(), nullptr, ctx.response_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count, now_ms() - ctx.started_ms,
                                 0, ref.framework_name);
        rc = RAC_SUCCESS;
    } else if (rc != RAC_SUCCESS) {
        dispatch_terminal_once(&ctx, "error", rac_error_message(rc));
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 request.prompt().c_str(), nullptr, ctx.response_text.c_str(),
                                 rac_error_message(rc), ref.model_id, ctx.token_count,
                                 now_ms() - ctx.started_ms, 0, ref.framework_name);
    } else {
        // Mirror the OpenAI-style finish_reason
        // contract from llm_component.cpp:867-884 and rac_llm_generate_proto's
        // set_result_from_raw — when the backend stopped because it generated
        // the requested max_tokens, the terminal proto event must report
        // "length" rather than "stop". Without this gate every successful
        // streaming proto generation looks like a natural stop, which breaks
        // OpenAI parity for direct streaming proto callers (JNI, Web, etc.)
        // and diverges from the non-streaming proto path.
        const char* finish_reason =
            (options.max_tokens > 0 && ctx.token_count >= options.max_tokens) ? "length" : "stop";
        dispatch_terminal_once(&ctx, finish_reason, nullptr);
        const int64_t stream_elapsed = now_ms() - ctx.started_ms;
        publish_generation_event(
            runanywhere::v1::GENERATION_EVENT_KIND_STREAM_COMPLETED, request.prompt().c_str(),
            nullptr, ctx.response_text.c_str(), nullptr, ref.model_id, ctx.token_count,
            stream_elapsed, ctx.prompt_tokens, ref.framework_name,
            (ctx.token_count > 0 && stream_elapsed > 0)
                ? ctx.token_count * 1000.0 / static_cast<double>(stream_elapsed)
                : 0.0,
            ctx.first_token_ms > ctx.started_ms
                ? static_cast<double>(ctx.first_token_ms - ctx.started_ms)
                : 0.0,
            options.temperature, options.max_tokens, lifecycle_context_length(ref),
            /*is_streaming=*/true);
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
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCEL_REQUESTED, nullptr,
                             nullptr, nullptr, nullptr, ref.model_id, 0, 0);
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

}  // extern "C"
