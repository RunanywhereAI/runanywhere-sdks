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
    void* opaque = nullptr;
};

rac_result_t acquire_lifecycle_llm(LifecycleLlmRef* out_ref);
void release_lifecycle_llm(LifecycleLlmRef* ref);

void clear_lifecycle_llm_cancel(LifecycleLlmRef* ref);
void request_lifecycle_llm_cancel(LifecycleLlmRef* ref);
bool lifecycle_llm_cancel_requested(const LifecycleLlmRef* ref);

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_RAC_LLM_LIFECYCLE_BRIDGE_H
