/**
 * @file rac_llm_structured_output.h
 * @brief Proto-byte structured-output C ABI.
 *
 * Structured-output parser structs and helpers are implementation details.
 * SDK consumers use generated protobuf requests and results exclusively.
 */

#ifndef RAC_LLM_STRUCTURED_OUTPUT_H
#define RAC_LLM_STRUCTURED_OUTPUT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_API rac_result_t rac_structured_output_parse_proto(const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_structured_output_generate_proto(const uint8_t* request_proto_bytes,
                                                          size_t request_proto_size,
                                                          rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_structured_output_generate_stream_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_bytes_callback_fn callback, void* user_data);

RAC_API rac_result_t rac_structured_output_prepare_prompt_proto(const uint8_t* request_proto_bytes,
                                                                size_t request_proto_size,
                                                                rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_structured_output_validate_proto(const uint8_t* request_proto_bytes,
                                                          size_t request_proto_size,
                                                          rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_STRUCTURED_OUTPUT_H */
