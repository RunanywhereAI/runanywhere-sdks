/**
 * @file rac_error_proto.h
 * @brief Canonical mapping from a `rac_result_t` error code to a serialized
 *        `runanywhere.v1.SDKError` proto buffer.
 *
 * Platform SDKs (Swift, Kotlin, Flutter, RN, Web) all need to convert an
 * incoming negative `rac_result_t` into a typed, structured error payload
 * containing:
 *   - the proto `ErrorCode` (positive magnitude of the C ABI value),
 *   - the proto `ErrorCategory` (the 9-bucket coarse routing enum from
 *     `idl/errors.proto`),
 *   - a non-empty human-readable message,
 *   - the original signed `rac_result_t` for round-trip in `c_abi_code`.
 *
 * Before this header existed every SDK reimplemented the mapping in its own
 * language (e.g. Swift's `CommonsErrorMapping.swift`, ~470 LOC of switches);
 * those files now collapse to a single `rac_result_to_proto_error()` call and
 * a proto deserialization step.
 *
 * The implementation lives in `src/core/rac_error_proto.cpp` and uses the
 * existing internal helpers `rac_error_message()` (in `rac_error.h`) and a
 * shared `rac::foundation::rac_result_to_proto_category()` mapper, also used
 * by the event publisher.
 *
 * Memory ownership: on success the caller owns `out_proto->data` and must
 * release it with `rac_proto_buffer_free()`. On failure `out_proto->data` is
 * NULL and `out_proto->status` carries the negative `rac_result_t` reason.
 */

#ifndef RAC_ERROR_PROTO_H
#define RAC_ERROR_PROTO_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Serialize a `rac_result_t` error code into a populated `SDKError`
 *        proto buffer.
 *
 * Populates `out_proto` with a serialized `runanywhere.v1.SDKError` containing:
 *   - `code`        — proto ErrorCode = abs(`code`), including unknown values;
 *                     INT32_MIN maps to ERROR_CODE_UNKNOWN because its positive
 *                     magnitude cannot be represented by the int32 proto enum.
 *   - `category`    — derived from the 18 ranges in rac_error_categories.def
 *                     through -999; non-negative and unmapped codes are UNSPECIFIED.
 *   - `message`     — `rac_error_message(code)`; never empty for a valid code.
 *   - `c_abi_code`  — the original signed `code`, for lossless round-tripping.
 *   - `timestamp_ms`— absent (zero) — populated by event publishers, not here.
 *   - `severity`    — ERROR_SEVERITY_ERROR.
 *
 * On `RAC_SUCCESS` input this function writes an SDKError with code/category
 * UNSPECIFIED (and the normal message/severity fields), returning `RAC_SUCCESS`. Callers
 * that wish to suppress emission of a "success" SDKError should test
 * `code == RAC_SUCCESS` themselves before calling.
 *
 * @param code      Error code to map (any `rac_result_t`).
 * @param out_proto Output buffer to populate. Must be non-NULL. Existing
 *                  contents are released before being repopulated.
 *
 * @return `RAC_SUCCESS` on a successfully serialized SDKError. Returns
 *         `RAC_ERROR_INVALID_ARGUMENT` if `out_proto` is NULL.
 *         Returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` if commons was built with
 *         the protobuf runtime disabled (RAC_HAVE_PROTOBUF undefined). Returns
 *         `RAC_ERROR_EVENT_PUBLISH_FAILED` if proto serialization itself fails
 *         (extremely unlikely — only on out-of-memory).
 */
RAC_API rac_result_t rac_result_to_proto_error(rac_result_t code, rac_proto_buffer_t* out_proto);

#ifdef __cplusplus
}
#endif

#endif /* RAC_ERROR_PROTO_H */
