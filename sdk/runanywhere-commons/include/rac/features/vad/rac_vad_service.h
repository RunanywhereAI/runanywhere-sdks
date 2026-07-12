/**
 * @file rac_vad_service.h
 * @brief VAD engine contract and generated-proto lifecycle ABI.
 */

#ifndef RAC_VAD_SERVICE_H
#define RAC_VAD_SERVICE_H

#include "rac/features/vad/rac_vad_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Backend operations installed in rac_engine_vtable_t::vad_ops. */
typedef struct rac_vad_service_ops {
    rac_result_t (*process)(void* impl, const float* samples, size_t num_samples,
                            rac_bool_t* out_is_speech);
    rac_result_t (*start)(void* impl);
    rac_result_t (*stop)(void* impl);
    rac_result_t (*reset)(void* impl);
    rac_result_t (*set_threshold)(void* impl, float threshold);
    rac_bool_t (*is_speech_active)(void* impl);
    void (*destroy)(void* impl);
    rac_result_t (*initialize)(void* impl, const char* model_path);
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_vad_service_ops_t;

/** Commons-owned wrapper around a selected VAD engine implementation. */
typedef struct rac_vad_service {
    const rac_vad_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_vad_service_t;

RAC_API rac_result_t rac_vad_process_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                     size_t request_proto_size,
                                                     rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_vad_configure_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_vad_start_lifecycle_proto(rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_vad_stop_lifecycle_proto(rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_vad_reset_lifecycle_proto(rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif  // RAC_VAD_SERVICE_H
