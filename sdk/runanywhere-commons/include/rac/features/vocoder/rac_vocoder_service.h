/** @file rac_vocoder_service.h @brief Mel vocoder engine service interface. */

#ifndef RAC_FEATURES_VOCODER_RAC_VOCODER_SERVICE_H
#define RAC_FEATURES_VOCODER_RAC_VOCODER_SERVICE_H

#include <stddef.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/vocoder/rac_vocoder_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_vocoder_service_ops {
    rac_result_t (*initialize)(void* impl, const char* model_path);
    /** Returned fields are malloc/free-compatible and caller-owned. */
    rac_result_t (*vocode)(void* impl, const rac_vocoder_input_t* input,
                           rac_vocoder_result_t* out_result);
    rac_result_t (*cleanup)(void* impl);
    void (*destroy)(void* impl);
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_vocoder_service_ops_t;

typedef struct rac_vocoder_service {
    const rac_vocoder_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_vocoder_service_t;

RAC_API rac_result_t rac_vocoder_create(const char* model_id, rac_handle_t* out_handle);
RAC_API rac_result_t rac_vocoder_initialize(rac_handle_t handle, const char* model_path);
RAC_API rac_result_t rac_vocoder_vocode(rac_handle_t handle, const rac_vocoder_input_t* input,
                                        rac_vocoder_result_t* out_result);
RAC_API rac_result_t rac_vocoder_cleanup(rac_handle_t handle);
RAC_API void rac_vocoder_destroy(rac_handle_t handle);

/** Handle-free SDK ABI over runanywhere.v1.VocoderRequest/Result. */
RAC_API rac_result_t rac_vocoder_vocode_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                        size_t request_proto_size,
                                                        rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_VOCODER_RAC_VOCODER_SERVICE_H */
