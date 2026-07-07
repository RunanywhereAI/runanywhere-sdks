/**
 * @file mlx_bundle_policy.h
 * @brief MLX folder-bundle resolution policy.
 */

#ifndef ENGINES_MLX_MLX_BUNDLE_POLICY_H
#define ENGINES_MLX_MLX_BUNDLE_POLICY_H

#include <stdint.h>
#include <string.h>

#include "rac/infrastructure/model_management/rac_bundle_policy.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline rac_bool_t mlx_is_bundle_manifest(const char* relative_path) {
    return (relative_path != NULL && strcmp(relative_path, "config.json") == 0) ? RAC_TRUE
                                                                                : RAC_FALSE;
}

static inline const rac_bundle_policy_t* mlx_bundle_policy(void) {
    static const rac_bundle_policy_t policy = {
        /* .struct_size                = */ (uint32_t)sizeof(rac_bundle_policy_t),
        /* .framework                  = */ RAC_FRAMEWORK_MLX,
        /* .model_format               = */ RAC_MODEL_FORMAT_SAFETENSORS,
        /* .manifest_extension         = */ ".json",
        /* .manifest_leaf_names_bundle = */ RAC_FALSE,
        /* .is_bundle_manifest         = */ mlx_is_bundle_manifest,
        /* .reserved_0                 = */ 0,
        /* .reserved_1                 = */ 0,
    };
    return &policy;
}

#ifdef __cplusplus
}
#endif

#endif  // ENGINES_MLX_MLX_BUNDLE_POLICY_H
