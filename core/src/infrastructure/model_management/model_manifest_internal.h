/**
 * @file model_manifest_internal.h
 * @brief Private model-folder manifest contract shared by commons TUs.
 */

#ifndef RAC_INFRA_MODEL_MANAGEMENT_MODEL_MANIFEST_INTERNAL_H
#define RAC_INFRA_MODEL_MANAGEMENT_MODEL_MANIFEST_INTERNAL_H

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

namespace rac::infra::model_manifest {

inline constexpr char kFilename[] = ".rac-manifest.binpb";

rac_result_t persist(rac_model_registry_handle_t handle, const char* model_id);

}  // namespace rac::infra::model_manifest

#endif  // RAC_INFRA_MODEL_MANAGEMENT_MODEL_MANIFEST_INTERNAL_H
