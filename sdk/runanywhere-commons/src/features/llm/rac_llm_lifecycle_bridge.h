#ifndef RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H
#define RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H

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
    void* opaque = nullptr;
};

rac_result_t acquire_lifecycle_llm(LifecycleLlmRef* out_ref);
void release_lifecycle_llm(LifecycleLlmRef* ref);

// Cheap capability probe used BEFORE a generation (e.g. at tool-loop entry, to pick the
// prompt format): true iff the currently-loaded LLM's framework honors grammar-constrained
// decoding (QHexRT). Acquires + releases the lifecycle ref internally; false if none loaded.
bool lifecycle_llm_supports_grammar();

void clear_lifecycle_llm_cancel(LifecycleLlmRef* ref);
void request_lifecycle_llm_cancel(LifecycleLlmRef* ref);
bool lifecycle_llm_cancel_requested(const LifecycleLlmRef* ref);

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H
