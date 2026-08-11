/**
 * @file rac_proto_buffer.h
 * @brief Shared C ABI ownership helpers for serialized proto byte buffers.
 *
 * Canonical convention:
 *   - Serialized proto inputs use borrowed {const uint8_t*, size_t} pairs.
 *     NULL is valid only when size == 0.
 *   - Stream callback payloads use the same borrowed byte pair and are valid
 *     only for the duration of the callback. Retainers must copy.
 *   - Serialized proto outputs use rac_proto_buffer_t:
 *     {data, size, status, error_message}.
 *   - On output success, data is owned by the caller and must be released with
 *     rac_proto_buffer_free(). Empty success buffers have size == 0 and may
 *     still carry a non-NULL owned data sentinel to distinguish success from
 *     error/null output in older bridges.
 *   - On output failure, data == NULL, size == 0, status is a negative
 *     rac_result_t, and error_message is optional owned text.
 *   - rac_proto_buffer_free() is idempotent for the same struct instance.
 *
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

/**
 * @brief Borrowed serialized proto bytes.
 *
 * The caller owns the pointed-to memory. This view is used for input payloads
 * and stream callback payloads; retainers must copy through
 * rac_proto_buffer_copy().
 */
typedef struct rac_proto_bytes {
    const uint8_t* data;
    size_t size;
} rac_proto_bytes_t;

/**
 * @brief Common void-returning proto callback payload shape.
 *
 * The byte pair is borrowed and valid only for the callback invocation.
 * Feature-specific callbacks may add return semantics, but should keep this
 * payload ownership convention.
 */
typedef void (*rac_proto_bytes_callback_fn)(const uint8_t* proto_bytes, size_t proto_size,
                                            void* user_data);

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
 * @brief Validate borrowed serialized proto bytes.
 *
 * Returns RAC_SUCCESS when data may be parsed or copied. Empty bytes
 * (data == NULL, size == 0) are valid and represent a default proto message.
 * Non-empty NULL data and byte counts too large for protobuf ParseFromArray()
 * return RAC_ERROR_INVALID_ARGUMENT.
 */
RAC_API rac_result_t rac_proto_bytes_validate(const uint8_t* data, size_t size);

/**
 * @brief Return a non-NULL parse pointer for valid borrowed proto bytes.
 *
 * For size == 0 this returns a stable empty sentinel. For size > 0 this
 * returns data. Call rac_proto_bytes_validate() first when accepting external
 * input.
 */
RAC_API const void* rac_proto_bytes_data_or_empty(const uint8_t* data, size_t size);

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
RAC_API rac_result_t rac_proto_buffer_copy(const uint8_t* data, size_t size,
                                           rac_proto_buffer_t* out_buffer);

/**
 * @brief Move owned data out of a success buffer.
 *
 * On success, *data_out owns the previous buffer->data allocation and must be
 * freed with rac_proto_buffer_free_data().
 * The source buffer is reset to empty success. Error buffers are not moved and
 * return their status.
 */
RAC_API rac_result_t rac_proto_buffer_take_data(rac_proto_buffer_t* buffer, uint8_t** data_out,
                                                size_t* size_out);

/**
 * @brief Set a buffer to an error state with optional owned error text.
 *
 * buffer must be initialized with rac_proto_buffer_init() or be zeroed.
 */
RAC_API rac_result_t rac_proto_buffer_set_error(rac_proto_buffer_t* buffer, rac_result_t status,
                                                const char* error_message);

/**
 * @brief Free owned data/error fields and reset the struct to empty success.
 *
 * Safe to call repeatedly on the same initialized or previously freed buffer.
 */
RAC_API void rac_proto_buffer_free(rac_proto_buffer_t* buffer);

/**
 * @brief Free raw data moved out with rac_proto_buffer_take_data().
 *
 * This is NULL-safe. It is not idempotent for a non-NULL raw pointer because
 * the function cannot clear the caller's pointer.
 */
RAC_API void rac_proto_buffer_free_data(uint8_t* data);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PROTO_BUFFER_H */
