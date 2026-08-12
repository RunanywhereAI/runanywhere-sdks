/** @file rac_rerank_component.h @brief Lifecycle-owning reranking component. */

#ifndef RAC_FEATURES_RERANK_RAC_RERANK_COMPONENT_H
#define RAC_FEATURES_RERANK_RAC_RERANK_COMPONENT_H

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/features/rerank/rac_rerank_service.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_API rac_result_t rac_rerank_component_create(rac_handle_t* out_handle);
RAC_API rac_bool_t rac_rerank_component_is_loaded(rac_handle_t handle);
RAC_API const char* rac_rerank_component_get_model_id(rac_handle_t handle);
RAC_API rac_result_t rac_rerank_component_load_model(rac_handle_t handle, const char* model_path,
                                                     const char* model_id, const char* model_name);
RAC_API rac_result_t rac_rerank_component_unload(rac_handle_t handle);
RAC_API rac_lifecycle_state_t rac_rerank_component_get_state(rac_handle_t handle);
RAC_API rac_result_t rac_rerank_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics);
RAC_API void rac_rerank_component_destroy(rac_handle_t handle);

/** SDK-facing ABI over runanywhere.v1.RerankRequest → RerankResult. */
RAC_API rac_result_t rac_rerank_component_rerank_proto(rac_handle_t handle,
                                                       const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_RERANK_RAC_RERANK_COMPONENT_H */
