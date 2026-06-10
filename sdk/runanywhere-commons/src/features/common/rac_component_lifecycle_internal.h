/**
 * @file rac_component_lifecycle_internal.h
 * @brief Shared internal helper for single-backend component creation.
 *
 * The single-backend feature modules (llm/stt/tts/vlm/diffusion/embeddings)
 * all create their component identically: allocate the component struct, wire a
 * `rac_lifecycle_config_t`, call `rac_lifecycle_create()` with the feature's
 * create/destroy service callbacks, and publish the handle. Only the component
 * type, resource type, logger categories, and service callbacks differ.
 *
 * NOTE: only the *create* path is shared here. `*_component_configure` and
 * `*_component_destroy` are intentionally NOT factored out — they carry
 * per-module behavior (e.g. LLM's lora-state cleanup, VLM's quiesce-before-
 * destroy ordering, per-feature config option mapping) that is clearer and
 * safer kept explicit in each module.
 */

#ifndef RAC_FEATURES_COMMON_RAC_COMPONENT_LIFECYCLE_INTERNAL_H
#define RAC_FEATURES_COMMON_RAC_COMPONENT_LIFECYCLE_INTERNAL_H

#include <new>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"

namespace rac::features {

// ComponentT must be default-constructible and expose a `lifecycle` member of
// type rac_handle_t (every single-backend component struct satisfies this).
template <typename ComponentT>
inline rac_result_t create_lifecycle_component(rac_handle_t* out_handle,
                                               rac_resource_type_t resource_type,
                                               const char* logger_category,
                                               rac_lifecycle_create_service_fn create_fn,
                                               rac_lifecycle_destroy_service_fn destroy_fn,
                                               const char* component_log_cat,
                                               const char* created_message) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) ComponentT();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = resource_type;
    lifecycle_config.logger_category = logger_category;
    lifecycle_config.user_data = component;

    rac_result_t result =
        rac_lifecycle_create(&lifecycle_config, create_fn, destroy_fn, &component->lifecycle);
    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);
    RAC_LOG_INFO(component_log_cat, "%s", created_message);
    return RAC_SUCCESS;
}

}  // namespace rac::features

#endif  // RAC_FEATURES_COMMON_RAC_COMPONENT_LIFECYCLE_INTERNAL_H
