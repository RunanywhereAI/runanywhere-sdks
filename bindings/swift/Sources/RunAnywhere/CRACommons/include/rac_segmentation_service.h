/** @file rac_segmentation_service.h @brief Semantic segmentation engine service interface. */

#ifndef RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_SERVICE_H
#define RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_SERVICE_H

#include <stddef.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_segmentation_types.h"
#include "rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_segmentation_service_ops {
    rac_result_t (*initialize)(void* impl, const char* model_path);
    /**
     * Produce a source-dimension class mask. Every pointer returned in
     * out_result MUST use a malloc/free-compatible allocator and remains
     * caller-owned on both success and partial failure.
     */
    rac_result_t (*segment)(void* impl, const rac_segmentation_image_t* image,
                            const rac_segmentation_options_t* options,
                            rac_segmentation_result_t* out_result);
    rac_result_t (*cleanup)(void* impl);
    void (*destroy)(void* impl);
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_segmentation_service_ops_t;

typedef struct rac_segmentation_service {
    const rac_segmentation_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_segmentation_service_t;

RAC_API rac_result_t rac_segmentation_create(const char* model_id, rac_handle_t* out_handle);
RAC_API rac_result_t rac_segmentation_initialize(rac_handle_t handle, const char* model_path);
RAC_API rac_result_t rac_segmentation_segment(rac_handle_t handle,
                                              const rac_segmentation_image_t* image,
                                              const rac_segmentation_options_t* options,
                                              rac_segmentation_result_t* out_result);
RAC_API rac_result_t rac_segmentation_cleanup(rac_handle_t handle);
RAC_API void rac_segmentation_destroy(rac_handle_t handle);

/** SDK-facing ABI over runanywhere.v1.SegmentationRequest/Result. */
RAC_API rac_result_t rac_segmentation_segment_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                              size_t request_proto_size,
                                                              rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_SERVICE_H */
