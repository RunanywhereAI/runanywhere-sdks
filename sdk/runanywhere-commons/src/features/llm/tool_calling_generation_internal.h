#ifndef RAC_FEATURES_LLM_TOOL_CALLING_GENERATION_INTERNAL_H
#define RAC_FEATURES_LLM_TOOL_CALLING_GENERATION_INTERNAL_H

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include "features/llm/llm_thinking_directive_internal.h"
#include "features/llm/llm_thinking_tags_internal.h"
#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/features/llm/rac_llm_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "tool_calling.pb.h"

#include "infrastructure/events/sdk_event_publish.h"
#endif

namespace rac::llm::tool_calling {

struct GenerationState {
    int32_t max_tokens = 0;
    float temperature = 0.0f;
    float top_p = 0.0f;
    std::string system_prompt;
    // Optional per-step stop marker. The synchronous generate call only
    // borrows this string, so it is safe to expose through rac_llm_options_t.
    std::string stop_sequence;
    bool disable_thinking = false;
    bool thinking_tags_resolved = false;
    std::string thinking_open_tag;
    std::string thinking_close_tag;
    // Prior conversation turns as a flat alternating list [user0, asst0, ...],
    // EXCLUDING the current turn. Owned here (not borrowed) so it survives the
    // GenerationState copies the loop makes per step / for follow-ups; each
    // run_generate_once flattens it into rac_llm_options_t.history. Unlike
    // llm_module's history normalizer, this is already current-turn-free and
    // pre-alternated, so run_generate_once forwards it as-is (no trailing pop).
    std::vector<std::string> history;
    // Names of the tools advertised this turn (RUN-80). Used ONLY to build the
    // QHexRT grammar spec ("toolcall_opt:<names>") when the backend supports
    // grammar-constrained decoding; empty ⇒ no grammar attached. Non-grammar
    // engines ignore it.
    std::vector<std::string> tool_names;
};

struct GenerationCancelBinding {
    std::mutex* active_ref_mu = nullptr;
    LifecycleLlmRef** active_ref = nullptr;
    std::atomic<bool>* cancel_requested = nullptr;
    bool* generation_started = nullptr;  // guarded by active_ref_mu
};

inline void split_display_text_and_thinking(const std::string& raw_text, std::string* out_text,
                                            std::string* out_thinking,
                                            const GenerationState& generation) {
    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    if (rac_llm_extract_thinking_with_tags(
            raw_text.c_str(),
            generation.thinking_open_tag.empty() ? nullptr : generation.thinking_open_tag.c_str(),
            generation.thinking_close_tag.empty() ? nullptr : generation.thinking_close_tag.c_str(),
            &response, &response_len, &thinking, &thinking_len) != RAC_SUCCESS) {
        if (out_text) {
            *out_text = raw_text;
        }
        if (out_thinking) {
            out_thinking->clear();
        }
        return;
    }

    if (out_text) {
        *out_text = response ? std::string(response, response_len) : std::string();
    }
    if (out_thinking) {
        *out_thinking =
            (thinking && thinking_len > 0) ? std::string(thinking, thinking_len) : std::string();
    }
}

#if defined(RAC_HAVE_PROTOBUF)
inline GenerationState generation_for_tool_step(const GenerationState& base, uint32_t iteration,
                                                bool has_tool_choice,
                                                runanywhere::v1::ToolChoiceMode tool_choice,
                                                runanywhere::v1::ToolCallFormatName format) {
    GenerationState step = base;
    const bool forced_decision = iteration == 1 && has_tool_choice &&
                                 tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC;
    if (!forced_decision) {
        return step;
    }
    step.max_tokens = 192;
    step.temperature = 0.0f;
    step.top_p = 1.0f;
    step.disable_thinking = true;
    step.stop_sequence = format == runanywhere::v1::TOOL_CALL_FORMAT_NAME_LFM2 ? "<|tool_call_end|>"
                                                                               : "</tool_call>";
    return step;
}

inline void set_display_text_and_thinking(runanywhere::v1::ToolCallingResult* result,
                                          const std::string& raw_text,
                                          const GenerationState& generation) {
    if (!result) {
        return;
    }

    std::string display_text;
    std::string thinking_content;
    split_display_text_and_thinking(raw_text, &display_text, &thinking_content, generation);
    result->set_text(display_text);
    if (!thinking_content.empty()) {
        result->set_thinking_content(thinking_content);
    } else {
        result->clear_thinking_content();
    }
}
#endif

inline void publish_generation_completed_event(
    const LifecycleLlmRef& ref, const rac_llm_result_t& raw,
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::EventDestination destination = runanywhere::v1::EVENT_DESTINATION_UNSPECIFIED
#else
    int destination = 0
#endif
) {
#if defined(RAC_HAVE_PROTOBUF)
    // Tool-calling generate calls still need the canonical LLM telemetry path.
    runanywhere::v1::SDKEvent llm_event;
    if (destination != runanywhere::v1::EVENT_DESTINATION_UNSPECIFIED) {
        llm_event.set_destination(destination);
    }
    auto* gen = llm_event.mutable_generation();
    gen->set_kind(runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED);
    if (ref.model_id != nullptr && ref.model_id[0] != '\0') {
        gen->set_model_id(ref.model_id);
    }
    if (raw.completion_tokens > 0) {
        gen->set_tokens_count(raw.completion_tokens);
        gen->set_tokens_used(raw.completion_tokens);
    }
    if (raw.prompt_tokens > 0) {
        gen->set_input_tokens(raw.prompt_tokens);
    }
    if (raw.tokens_per_second > 0.0f) {
        gen->set_tokens_per_second(raw.tokens_per_second);
    }
    if (raw.time_to_first_token_ms > 0) {
        gen->set_time_to_first_token_ms(raw.time_to_first_token_ms);
    }
    (void)rac::events::publish(llm_event, runanywhere::v1::SDK_COMPONENT_LLM,
                               runanywhere::v1::EVENT_CATEGORY_LLM);
#else
    (void)ref;
    (void)raw;
    (void)destination;
#endif
}

// Aggregates the tool-calling loop's inner generations into ONE telemetry row
// per logical request. Per-iteration completed events go PUBLIC-only (UI parity);
// without this a single tool-calling request landed N unpaired "completed"
// telemetry rows — one per loop iteration.
struct GenerationTelemetryAgg {
    int64_t input_tokens{0};
    int64_t output_tokens{0};
    double tokens_per_second{0.0};
    int64_t time_to_first_token_ms{0};
    uint32_t generations{0};
    std::string model_id;
};

inline void publish_tool_loop_telemetry(const GenerationTelemetryAgg& agg) {
#if defined(RAC_HAVE_PROTOBUF)
    if (agg.generations == 0) {
        return;
    }
    runanywhere::v1::SDKEvent event;
    // Telemetry-only: the per-iteration PUBLIC events already served consumers.
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_TELEMETRY);
    (*event.mutable_properties())["iterations"] = std::to_string(agg.generations);
    auto* gen = event.mutable_generation();
    gen->set_kind(runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED);
    if (!agg.model_id.empty()) {
        gen->set_model_id(agg.model_id);
    }
    if (agg.output_tokens > 0) {
        gen->set_tokens_count(static_cast<int32_t>(agg.output_tokens));
        gen->set_tokens_used(static_cast<int32_t>(agg.output_tokens));
    }
    if (agg.input_tokens > 0) {
        gen->set_input_tokens(static_cast<int32_t>(agg.input_tokens));
    }
    if (agg.tokens_per_second > 0.0) {
        gen->set_tokens_per_second(agg.tokens_per_second);
    }
    if (agg.time_to_first_token_ms > 0) {
        gen->set_time_to_first_token_ms(agg.time_to_first_token_ms);
    }
    (void)rac::events::publish(event, runanywhere::v1::SDK_COMPONENT_LLM,
                               runanywhere::v1::EVENT_CATEGORY_LLM);
#else
    (void)agg;
#endif
}

// Emits the aggregate on every loop exit path (success, tool failure, cancel).
struct ToolLoopTelemetryScope {
    GenerationTelemetryAgg agg;
    ToolLoopTelemetryScope() = default;
    ToolLoopTelemetryScope(const ToolLoopTelemetryScope&) = delete;
    ToolLoopTelemetryScope& operator=(const ToolLoopTelemetryScope&) = delete;
    ~ToolLoopTelemetryScope() { publish_tool_loop_telemetry(agg); }
};

inline bool run_generate_once(GenerationState& generation,
                              const GenerationCancelBinding& cancel_binding,
                              const std::string& prompt, std::string* out_response,
                              rac_result_t* out_rc, GenerationTelemetryAgg* agg = nullptr) {
    LifecycleLlmRef ref;
    rac_result_t rc = acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        if (out_rc) {
            *out_rc = rc;
        }
        return false;
    }

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    if (generation.max_tokens > 0) {
        options.max_tokens = generation.max_tokens;
    }
    // 0.0 is an explicit greedy setting, not an "unset" sentinel. The old
    // >0 guard silently retained RAC_LLM_OPTIONS_DEFAULT.temperature (0.8),
    // making a caller-requested deterministic tool decision stochastic.
    options.temperature = generation.temperature;
    if (generation.top_p > 0.0f) {
        options.top_p = generation.top_p;
    }
    const char* stop_sequences[2] = {nullptr, nullptr};
    if (!generation.stop_sequence.empty()) {
        stop_sequences[0] = generation.stop_sequence.c_str();
        options.stop_sequences = stop_sequences;
        options.num_stop_sequences = 1;
    }
    options.streaming_enabled = RAC_FALSE;
    options.system_prompt =
        generation.system_prompt.empty() ? nullptr : generation.system_prompt.c_str();
    options.disable_thinking = generation.disable_thinking ? RAC_TRUE : RAC_FALSE;

    // Prior conversation turns (tool_calling.proto ToolCallingSessionCreateRequest.history).
    // Already excludes the current turn and is pre-alternated [user,asst,...], so unlike
    // llm_module's normalizer we forward it verbatim (no leading/trailing role fixups). The
    // pointer array must outlive ops->generate, so it lives in this call frame; the backing
    // strings are owned by generation.history.
    std::vector<const char*> history_ptrs;
    if (!generation.history.empty()) {
        history_ptrs.reserve(generation.history.size());
        for (const auto& turn : generation.history) {
            history_ptrs.push_back(turn.c_str());
        }
    }
    options.history = history_ptrs.empty() ? nullptr : history_ptrs.data();
    options.n_history = static_cast<int32_t>(history_ptrs.size());

    // QHexRT grammar-constrained tool decoding (RUN-80). When the backend honors
    // options.grammar AND a tool set is live, constrain decoding to "free chat OR
    // exactly one [name(args)] call over the enumerated tools" (ToolCallOptional).
    // This makes over-calling structurally impossible on QHexRT — the model can
    // still answer in plain text; it just cannot invent or misformat a call. The
    // spec string must outlive ops->generate (options.grammar aliases it), so it
    // lives in this call frame. supports_grammar is false for llama.cpp/onnx/cloud
    // (set per-framework in the lifecycle accessor), so options.grammar stays NULL
    // there and behavior is byte-for-byte unchanged for non-grammar engines.
    std::string grammar_spec;
    if (ref.supports_grammar && !generation.tool_names.empty()) {
        grammar_spec = "toolcall_opt:";
        for (size_t i = 0; i < generation.tool_names.size(); ++i) {
            if (i != 0) {
                grammar_spec += ',';
            }
            grammar_spec += generation.tool_names[i];
        }
        options.grammar = grammar_spec.c_str();
    }

    clear_lifecycle_llm_cancel(&ref);

    if (!ref.ops || !ref.ops->generate) {
        release_lifecycle_llm(&ref);
        if (out_rc) {
            *out_rc = RAC_ERROR_NOT_SUPPORTED;
        }
        return false;
    }

    if (!generation.thinking_tags_resolved) {
        (void)model_thinking_tags_from_registry(ref.model_id, &generation.thinking_open_tag,
                                                &generation.thinking_close_tag);
        generation.thinking_tags_resolved = true;
    }

    if (cancel_binding.active_ref_mu && cancel_binding.active_ref &&
        cancel_binding.cancel_requested && cancel_binding.generation_started) {
        bool cancelled_before_start = false;
        {
            std::lock_guard<std::mutex> guard(*cancel_binding.active_ref_mu);
            *cancel_binding.active_ref = &ref;
            *cancel_binding.generation_started = false;
            if (cancel_binding.cancel_requested->load(std::memory_order_acquire)) {
                *cancel_binding.active_ref = nullptr;
                cancelled_before_start = true;
            } else {
                *cancel_binding.generation_started = true;
            }
        }
        if (cancelled_before_start) {
            request_lifecycle_llm_cancel(&ref);
            release_lifecycle_llm(&ref);
            if (out_rc) {
                *out_rc = RAC_ERROR_CANCELLED;
            }
            return false;
        }
    }

    rac_llm_result_t raw{};
    const std::string effective_prompt =
        apply_no_think_directive(prompt, options.disable_thinking, ref.framework_name);
    rc = ref.ops->generate(ref.impl, effective_prompt.c_str(), &options, &raw);

    if (cancel_binding.active_ref_mu && cancel_binding.active_ref) {
        std::lock_guard<std::mutex> guard(*cancel_binding.active_ref_mu);
        if (cancel_binding.generation_started) {
            *cancel_binding.generation_started = false;
        }
        *cancel_binding.active_ref = nullptr;
    }

    if (cancel_binding.cancel_requested &&
        cancel_binding.cancel_requested->load(std::memory_order_acquire)) {
        rac_llm_result_free(&raw);
        release_lifecycle_llm(&ref);
        if (out_rc) {
            *out_rc = RAC_ERROR_CANCELLED;
        }
        return false;
    }

    if (rc != RAC_SUCCESS) {
        rac_llm_result_free(&raw);
        release_lifecycle_llm(&ref);
        if (out_rc) {
            *out_rc = rc;
        }
        return false;
    }

    if (out_response) {
        *out_response = raw.text ? raw.text : "";
    }
    if (agg) {
        agg->generations++;
        agg->input_tokens += raw.prompt_tokens;
        agg->output_tokens += raw.completion_tokens;
        if (agg->generations == 1) {
            agg->time_to_first_token_ms = raw.time_to_first_token_ms;
        }
        if (raw.tokens_per_second > 0.0f) {
            agg->tokens_per_second = raw.tokens_per_second;
        }
        if (agg->model_id.empty() && ref.model_id != nullptr) {
            agg->model_id = ref.model_id;
        }
#if defined(RAC_HAVE_PROTOBUF)
        publish_generation_completed_event(ref, raw, runanywhere::v1::EVENT_DESTINATION_PUBLIC);
#else
        publish_generation_completed_event(ref, raw);
#endif
    } else {
        publish_generation_completed_event(ref, raw);
    }

    rac_llm_result_free(&raw);
    release_lifecycle_llm(&ref);
    if (out_rc) {
        *out_rc = RAC_SUCCESS;
    }
    return true;
}

}  // namespace rac::llm::tool_calling

#endif  // RAC_FEATURES_LLM_TOOL_CALLING_GENERATION_INTERNAL_H
