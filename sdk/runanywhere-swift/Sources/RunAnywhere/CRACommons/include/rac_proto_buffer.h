/**
 * @file rac_proto_buffer.h
 * @brief Shared C ABI ownership helpers for serialized proto byte buffers.
 */

#ifndef RAC_PROTO_BUFFER_H
#define RAC_PROTO_BUFFER_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_proto_buffer {
    uint8_t* data;
    size_t size;
    rac_result_t status;
    char* error_message;
} rac_proto_buffer_t;

RAC_API void rac_proto_buffer_init(rac_proto_buffer_t* buffer);
RAC_API rac_result_t rac_proto_buffer_copy(const uint8_t* data,
                                           size_t size,
                                           rac_proto_buffer_t* out_buffer);
RAC_API rac_result_t rac_proto_buffer_set_error(rac_proto_buffer_t* buffer,
                                                rac_result_t status,
                                                const char* error_message);
RAC_API void rac_proto_buffer_free(rac_proto_buffer_t* buffer);
RAC_API rac_result_t rac_proto_buffer_copy_to_raw(const uint8_t* data,
                                                  size_t size,
                                                  uint8_t** data_out,
                                                  size_t* size_out);
RAC_API void rac_proto_buffer_free_data(uint8_t* data);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PROTO_BUFFER_H */
