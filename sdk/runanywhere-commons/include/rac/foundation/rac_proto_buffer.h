/**
 * @file rac_proto_buffer.h
 * @brief Shared C ABI ownership helpers for serialized proto byte buffers.
 *
 * Canonical convention:
 *   - Serialized proto payloads that cross the C ABI are represented as
 *     {data, size, status, error_message}.
 *   - On success, data is owned by the caller and must be released with
 *     rac_proto_buffer_free(). Empty success buffers have size == 0 and may
 *     still carry a non-NULL owned data sentinel to distinguish success from
 *     error/null output in older bridges.
 *   - On failure, data == NULL, size == 0, status is a negative rac_result_t,
 *     and error_message is optional owned text.
 *   - rac_proto_buffer_free() is idempotent for the same struct instance.
 *
 * Existing APIs that expose uint8_t** + size_t* remain source-compatible and
 * should allocate through rac_proto_buffer_copy_to_raw(); their scoped legacy
 * free functions should delegate to rac_proto_buffer_free_data().
 */

#ifndef RAC_PROTO_BUFFER_H
#define RAC_PROTO_BUFFER_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_proto_buffer {
    /** Owned serialized proto bytes, or NULL on error. */
    uint8_t* data;
    /** Number of meaningful bytes in data. May be 0 for an empty proto. */
    size_t size;
    /** RAC_SUCCESS on success, or a negative rac_result_t on failure. */
    rac_result_t status;
    /** Optional owned error text. Free via rac_proto_buffer_free(). */
    char* error_message;
} rac_proto_buffer_t;

/**
 * @brief Initialize a proto buffer to the empty success state.
 */
RAC_API void rac_proto_buffer_init(rac_proto_buffer_t* buffer);

/**
 * @brief Copy serialized proto bytes into an owned C ABI buffer.
 *
 * out_buffer must be initialized with rac_proto_buffer_init() or be zeroed.
 * Passing data == NULL is valid only when size == 0, producing an explicit
 * empty success buffer.
 */
RAC_API rac_result_t rac_proto_buffer_copy(const uint8_t* data,
                                           size_t size,
                                           rac_proto_buffer_t* out_buffer);

/**
 * @brief Set a buffer to an error state with optional owned error text.
 *
 * buffer must be initialized with rac_proto_buffer_init() or be zeroed.
 */
RAC_API rac_result_t rac_proto_buffer_set_error(rac_proto_buffer_t* buffer,
                                                rac_result_t status,
                                                const char* error_message);

/**
 * @brief Free owned data/error fields and reset the struct to empty success.
 *
 * Safe to call repeatedly on the same initialized or previously freed buffer.
 */
RAC_API void rac_proto_buffer_free(rac_proto_buffer_t* buffer);

/**
 * @brief Compatibility helper for legacy uint8_t** + size_t* C ABI functions.
 *
 * On success, *data_out owns the returned allocation and *size_out is the
 * meaningful byte count. Free with rac_proto_buffer_free_data() or the
 * legacy scoped free function that delegates to it.
 */
RAC_API rac_result_t rac_proto_buffer_copy_to_raw(const uint8_t* data,
                                                  size_t size,
                                                  uint8_t** data_out,
                                                  size_t* size_out);

/**
 * @brief Free raw data returned by rac_proto_buffer_copy_to_raw().
 *
 * This is NULL-safe. It is not idempotent for a non-NULL raw pointer because
 * the function cannot clear the caller's pointer.
 */
RAC_API void rac_proto_buffer_free_data(uint8_t* data);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PROTO_BUFFER_H */
