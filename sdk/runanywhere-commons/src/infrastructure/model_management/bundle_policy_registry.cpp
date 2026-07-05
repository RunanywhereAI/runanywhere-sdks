/**
 * @file bundle_policy_registry.cpp
 * @brief Per-framework bundle-policy registry (see rac_bundle_policy.h).
 *
 * Meyers-singleton map + mutex so registration is safe from plugin static
 * initializers (same rationale as the plugin registry). The registry stores
 * caller-owned pointers; policies must outlive the process (plugin
 * .rodata / function-local statics).
 */

#include "rac/infrastructure/model_management/rac_bundle_policy.h"

#include <map>
#include <mutex>

#include "rac/core/rac_error.h"

namespace {

struct Registry {
    std::mutex mutex;
    std::map<rac_inference_framework_t, const rac_bundle_policy_t*> policies;
};

Registry& registry() {
    static Registry instance;
    return instance;
}

}  // namespace

extern "C" rac_result_t rac_bundle_policy_register(const rac_bundle_policy_t* policy) {
    if (policy == nullptr || policy->framework == RAC_FRAMEWORK_UNKNOWN) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (policy->struct_size != sizeof(rac_bundle_policy_t)) {
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }
    Registry& r = registry();
    std::lock_guard<std::mutex> lock(r.mutex);
    r.policies[policy->framework] = policy;  // same-framework re-register replaces
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_bundle_policy_unregister(rac_inference_framework_t framework) {
    Registry& r = registry();
    std::lock_guard<std::mutex> lock(r.mutex);
    r.policies.erase(framework);
    return RAC_SUCCESS;
}

extern "C" const rac_bundle_policy_t*
rac_bundle_policy_find(rac_inference_framework_t framework) {
    Registry& r = registry();
    std::lock_guard<std::mutex> lock(r.mutex);
    const auto it = r.policies.find(framework);
    return it == r.policies.end() ? nullptr : it->second;
}
