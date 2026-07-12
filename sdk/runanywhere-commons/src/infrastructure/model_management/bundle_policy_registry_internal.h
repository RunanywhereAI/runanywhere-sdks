#ifndef RAC_INFRASTRUCTURE_MODEL_MANAGEMENT_BUNDLE_POLICY_REGISTRY_INTERNAL_H
#define RAC_INFRASTRUCTURE_MODEL_MANAGEMENT_BUNDLE_POLICY_REGISTRY_INTERNAL_H

#include "rac/infrastructure/model_management/rac_bundle_policy.h"

namespace rac::infra::bundle_policy {

const rac_bundle_policy_t* find(rac_inference_framework_t framework);

}  // namespace rac::infra::bundle_policy

#endif  // RAC_INFRASTRUCTURE_MODEL_MANAGEMENT_BUNDLE_POLICY_REGISTRY_INTERNAL_H
