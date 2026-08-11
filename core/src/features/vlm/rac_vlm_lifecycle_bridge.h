#ifndef RAC_FEATURES_VLM_RAC_VLM_LIFECYCLE_BRIDGE_H
#define RAC_FEATURES_VLM_RAC_VLM_LIFECYCLE_BRIDGE_H

#include "rac/core/rac_error.h"
#include "rac/features/vlm/rac_vlm_service.h"

namespace rac::vlm {

struct LifecycleVlmRef {
    const rac_vlm_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

rac_result_t acquire_lifecycle_vlm(LifecycleVlmRef* out_ref);
void release_lifecycle_vlm(LifecycleVlmRef* ref);

void clear_lifecycle_vlm_cancel(LifecycleVlmRef* ref);
void request_lifecycle_vlm_cancel(LifecycleVlmRef* ref);
bool lifecycle_vlm_cancel_requested(const LifecycleVlmRef* ref);

}  // namespace rac::vlm

#endif  // RAC_FEATURES_VLM_RAC_VLM_LIFECYCLE_BRIDGE_H
