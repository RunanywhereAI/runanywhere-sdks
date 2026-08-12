/**
 * @file rac_stt_hybrid_router_proto.h
 * @brief Proto-byte C ABI for the STT hybrid router.
 *
 * Mirrors the struct-based public API in rac_stt_hybrid_router.h, but takes
 * the descriptor / policy / request / response as serialised
 * `runanywhere.v1.Hybrid*` proto bytes.
 *
 * Why a separate proto-byte ABI: rac_commons is built with
 * -fvisibility=hidden on release, which means the C++ protobuf-generated
 * `runanywhere::v1::*` symbols inside rac_commons.so are not visible to
 * other libraries in the process (e.g. librunanywhere_jni.so). Bindings
 * therefore cannot construct proto messages on their side and pass them
 * through — they pass raw bytes, and these wrappers do the parse / build
 * inside rac_commons where the symbols are local.
 */

#ifndef RAC_STT_HYBRID_ROUTER_PROTO_H
#define RAC_STT_HYBRID_ROUTER_PROTO_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Attach (or detach if @p service is NULL) the offline-side STT service.
 *
 * @param handle              Router handle from rac_stt_hybrid_router_create.
 * @param service             Service to attach, or NULL to clear the slot.
 * @param descriptor_bytes    Serialized runanywhere.v1.HybridModelDescriptor.
 *                            Ignored when @p service is NULL.
 * @param descriptor_size     Length of @p descriptor_bytes in bytes.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_stt_hybrid_router_set_offline_service_proto(
    rac_handle_t handle, rac_stt_service_t* service, const uint8_t* descriptor_bytes,
    size_t descriptor_size);

/** Symmetric to rac_stt_hybrid_router_set_offline_service_proto. */
RAC_API rac_result_t rac_stt_hybrid_router_set_online_service_proto(rac_handle_t handle,
                                                                    rac_stt_service_t* service,
                                                                    const uint8_t* descriptor_bytes,
                                                                    size_t descriptor_size);

/**
 * Install / replace the routing policy.
 *
 * @param handle        Router handle.
 * @param policy_bytes  Serialized runanywhere.v1.HybridRoutingPolicy.
 * @param policy_size   Length of @p policy_bytes.
 */
RAC_API rac_result_t rac_stt_hybrid_router_set_policy_proto(rac_handle_t handle,
                                                            const uint8_t* policy_bytes,
                                                            size_t policy_size);

/**
 * Dispatch one transcribe request through the router.
 *
 * Builds the per-request routing context from the
 * `rac_hybrid_device_state` vtable snapshot (is_online, battery_percent,
 * thermal_throttled). HybridRoutingContext on the wire currently carries
 * no caller-supplied fields; future per-call hints can be added there.
 *
 * The output is a serialized runanywhere.v1.HybridSttTranscribeResponse.
 * On success, @p *out_response_bytes points at a heap allocation that
 * the caller MUST release via rac_stt_hybrid_router_proto_buffer_free.
 * On failure, @p *out_response_bytes is set to NULL and @p
 * *out_response_size to 0.
 *
 * @param handle              Router handle.
 * @param request_bytes       Serialized runanywhere.v1.HybridSttTranscribeRequest.
 * @param request_size        Length of @p request_bytes.
 * @param out_response_bytes  Receives heap-allocated response bytes.
 * @param out_response_size   Receives length of @p *out_response_bytes.
 */
RAC_API rac_result_t rac_stt_hybrid_router_transcribe_proto(rac_handle_t handle,
                                                            const uint8_t* request_bytes,
                                                            size_t request_size,
                                                            uint8_t** out_response_bytes,
                                                            size_t* out_response_size);

/**
 * Release a buffer returned by rac_stt_hybrid_router_transcribe_proto.
 * NULL-safe.
 */
RAC_API void rac_stt_hybrid_router_proto_buffer_free(uint8_t* response_bytes);

#ifdef __cplusplus
}
#endif

#endif  // RAC_STT_HYBRID_ROUTER_PROTO_H
