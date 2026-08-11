#ifndef RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H
#define RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H

#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_service.h"

namespace rac::llm {

struct LifecycleLlmRef {
    const rac_llm_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    bool supports_lora = false;
    // Backend capability: the engine honors rac_llm_options_t.grammar
    // (grammar-constrained decoding). Set by the lifecycle accessor per framework.
    // Defaults false so every non-grammar engine (llama.cpp/onnx/cloud) is
    // unaffected; only backends that actually consume options.grammar set it true.
    bool supports_grammar = false;
    /**
     * Whether the registry row says this model reasons. Gates the "/no_think"
     * directive: suppressing thinking on a model that cannot think is not a
     * no-op, it is unexplained text in the prompt.
     */
    bool supports_thinking = false;
    /**
     * True when ModelInfo.thinking_pattern.template_prefills_open_tag is set:
     * the chat template already emitted the opening think tag into the prompt
     * (qhexrt gen_prefill / DeepSeek-R1-Distill heuristic), so the stream
     * begins inside reasoning.
     */
    bool template_prefills_open_tag = false;
    void* opaque = nullptr;
};

rac_result_t acquire_lifecycle_llm(LifecycleLlmRef* out_ref);
void release_lifecycle_llm(LifecycleLlmRef* ref);

// Cheap capability probe used BEFORE a generation (e.g. at tool-loop entry, to pick the
// prompt format): true iff the currently-loaded LLM's framework honors grammar-constrained
// decoding (QHexRT). Acquires + releases the lifecycle ref internally; false if none loaded.
bool lifecycle_llm_supports_grammar();

// Model id of the currently-loaded LLM ("" if none). Used to derive the
// tool-call format when the caller left ToolCallingOptions.format UNSPECIFIED.
// Acquires + releases the lifecycle ref internally.
std::string lifecycle_llm_model_id();

void clear_lifecycle_llm_cancel(LifecycleLlmRef* ref);
void request_lifecycle_llm_cancel(LifecycleLlmRef* ref);
bool lifecycle_llm_cancel_requested(const LifecycleLlmRef* ref);

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H
