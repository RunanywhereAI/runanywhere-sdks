/**
 * @file rac_model_lifecycle.h
 * @brief Canonical model lifecycle C ABI over generated proto bytes.
 */

#ifndef RAC_CORE_MODEL_LIFECYCLE_H
#define RAC_CORE_MODEL_LIFECYCLE_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_proto_buffer.h"
#include "rac_model_registry.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_API rac_result_t rac_model_lifecycle_load_proto(
    rac_model_registry_handle_t registry,
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_model_lifecycle_unload_proto(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_model_lifecycle_current_model_proto(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_component_lifecycle_snapshot_proto(
    uint32_t component,
    rac_proto_buffer_t* out_snapshot);

RAC_API void rac_model_lifecycle_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_CORE_MODEL_LIFECYCLE_H */
