/**
 * @file rac_uuid.h
 * @brief RunAnywhere Commons - UUID generation
 *
 * Single shared RFC-4122 version-4 UUID generator. Replaces the byte-identical
 * private generate_uuid() copies that previously lived in each feature's
 * analytics TU ({llm,stt,tts}_analytics.cpp).
 */

#ifndef RAC_UUID_H
#define RAC_UUID_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Write a lowercase RFC-4122 version-4 UUID into `out`.
 *
 * Format: 8-4-4-4-12 lowercase hex with the version nibble fixed to '4' and
 * the variant nibble in 8/9/a/b, e.g. "f47ac10b-58cc-4372-a567-0e02b2c3d479".
 * Writes 36 characters plus a NUL terminator, so `out_size` must be >= 37.
 *
 * Thread-safe (thread_local RNG).
 *
 * @param out Destination buffer.
 * @param out_size Capacity of `out`; must be >= 37.
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER if `out` is NULL, or
 *         RAC_ERROR_BUFFER_TOO_SMALL if `out_size` < 37.
 */
RAC_API rac_result_t rac_uuid_v4(char* out, size_t out_size);

#ifdef __cplusplus
}
#endif

#endif /* RAC_UUID_H */
