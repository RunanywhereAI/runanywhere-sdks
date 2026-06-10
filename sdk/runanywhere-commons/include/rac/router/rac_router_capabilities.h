/**
 * @file rac_router_capabilities.h
 * @brief Proto-byte C ABI for engine-router capability queries.
 *
 * Replaces the per-SDK Kotlin / Swift / Dart / RN / Web
 * `SDKComponent → ModelCategory → framework` mapping with a single
 * commons-owned lookup backed by the engine-router plugin registry.
 *
 * Given a `runanywhere.v1.SDKComponent`, this ABI returns the ordered list of
 * `runanywhere.v1.InferenceFramework` values that the plugins currently
 * registered with the router can serve. Ordering matches the router's
 * priority-descending plugin scan; duplicate frameworks are removed while
 * preserving first-seen order.
 */

#ifndef RAC_ROUTER_CAPABILITIES_H
#define RAC_ROUTER_CAPABILITIES_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Resolve the set of inference frameworks that can serve `component`.
 *
 * Consumes serialized `runanywhere.v1.FrameworksForCapabilityRequest` bytes and
 * writes serialized `runanywhere.v1.FrameworksForCapabilityResponse` bytes to
 * `*out_response_bytes`. The caller owns the returned buffer and MUST free it
 * with `rac_router_frameworks_for_capability_proto_free()`.
 *
 * @param request_bytes      Serialized FrameworksForCapabilityRequest (may be empty).
 * @param request_size       Byte count for `request_bytes`.
 * @param out_response_bytes Output: allocated response proto bytes.
 * @param out_response_size  Output: response byte count.
 * @return RAC_SUCCESS on success (including empty-framework-list results),
 *         RAC_ERROR_NULL_POINTER when output pointers are NULL,
 *         RAC_ERROR_DECODING_ERROR when the request cannot be parsed,
 *         RAC_ERROR_ENCODING_ERROR when the response cannot be serialized,
 *         or RAC_ERROR_FEATURE_NOT_AVAILABLE when protobuf support is missing.
 */
RAC_API rac_result_t rac_router_frameworks_for_capability_proto(const uint8_t* request_bytes,
                                                                size_t request_size,
                                                                uint8_t** out_response_bytes,
                                                                size_t* out_response_size);

/**
 * @brief Free a buffer returned by
 *        `rac_router_frameworks_for_capability_proto()`. NULL-safe.
 */
RAC_API void rac_router_frameworks_for_capability_proto_free(uint8_t* response_bytes);

#ifdef __cplusplus
}
#endif

#endif /* RAC_ROUTER_CAPABILITIES_H */
