/**
 * @file rac_diarization_component.h
 * @brief Lifecycle-owning standalone speaker-diarization component.
 */

#ifndef RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_COMPONENT_H
#define RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_COMPONENT_H

#include "rac_diarization_service.h"
#include "rac_lifecycle.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_API rac_result_t rac_diarization_component_create(rac_handle_t* out_handle);
RAC_API rac_bool_t rac_diarization_component_is_loaded(rac_handle_t handle);
RAC_API const char* rac_diarization_component_get_model_id(rac_handle_t handle);
RAC_API rac_result_t rac_diarization_component_load_model(rac_handle_t handle,
                                                          const char* model_path,
                                                          const char* model_id,
                                                          const char* model_name);
RAC_API rac_result_t rac_diarization_component_unload(rac_handle_t handle);
RAC_API rac_lifecycle_state_t rac_diarization_component_get_state(rac_handle_t handle);
RAC_API rac_result_t rac_diarization_component_get_metrics(rac_handle_t handle,
                                                           rac_lifecycle_metrics_t* out_metrics);
RAC_API void rac_diarization_component_destroy(rac_handle_t handle);

/** Handle-based offline ABI, primarily for component tests/native consumers. */
RAC_API rac_result_t rac_diarization_component_diarize_proto(
    rac_handle_t handle, const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_COMPONENT_H */
