#pragma once

#include <memory>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/segmentation/rac_segmentation_confidence.h"

namespace rac::segmentation {

// Holds a registry lease until all models using this exact provider are gone.
// The optional callback is copied while the plugin and manifest are pinned.
struct ProviderContext {
    const rac_engine_vtable_t* vtable = nullptr;
    rac_result_t confidence_status = RAC_ERROR_NOT_SUPPORTED;
    rac_segmentation_confidence_ops_v1_t confidence_ops{};
    ~ProviderContext();
};

rac_result_t acquire_provider(const rac_engine_vtable_t* vtable,
                              std::shared_ptr<ProviderContext>* out_context);
std::shared_ptr<ProviderContext> service_provider(rac_handle_t handle);
rac_result_t segment_with_confidence(rac_segmentation_service_t* service,
                                     const ProviderContext* provider,
                                     const rac_segmentation_image_t* image,
                                     const rac_segmentation_options_t* options,
                                     rac_segmentation_result_t* out_result,
                                     rac_segmentation_confidence_mask_v1_t* out_confidence);

rac_result_t create_service(const char* model_id, const char* config_json,
                            rac_handle_t* out_handle);

}  // namespace rac::segmentation
