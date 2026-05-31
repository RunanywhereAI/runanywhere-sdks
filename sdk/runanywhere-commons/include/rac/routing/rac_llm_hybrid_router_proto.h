/**
 * @file rac_llm_hybrid_router_proto.h
 * @brief Proto-byte C ABI for the LLM hybrid router.
 *
 * Mirrors the struct-based public API in rac_llm_hybrid_router.h, but takes
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
 *
 * Every binding (Kotlin JNI, Swift, Flutter FFI, RN, Web emscripten)
 * targets this proto-byte surface. The struct-based API remains for
 * in-process C++ callers (tests, sample apps embedding commons directly).
 */

#ifndef RAC_LLM_HYBRID_ROUTER_PROTO_H
#define RAC_LLM_HYBRID_ROUTER_PROTO_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Attach (or detach if @p service is NULL) the offline-side LLM service.
 *
 * @param handle              Router handle from rac_llm_hybrid_router_create.
 * @param service             Service to attach, or NULL to clear the slot.
 * @param descriptor_bytes    Serialized runanywhere.v1.HybridModelDescriptor.
 *                            Ignored when @p service is NULL.
 * @param descriptor_size     Length of @p descriptor_bytes in bytes.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_llm_hybrid_router_set_offline_service_proto(
    rac_handle_t       handle,
    rac_llm_service_t* service,
    const uint8_t*     descriptor_bytes,
    size_t             descriptor_size);

/** Symmetric to rac_llm_hybrid_router_set_offline_service_proto. */
RAC_API rac_result_t rac_llm_hybrid_router_set_online_service_proto(
    rac_handle_t       handle,
    rac_llm_service_t* service,
    const uint8_t*     descriptor_bytes,
    size_t             descriptor_size);

/**
 * Install / replace the routing policy.
 *
 * @param handle        Router handle.
 * @param policy_bytes  Serialized runanywhere.v1.HybridRoutingPolicy.
 * @param policy_size   Length of @p policy_bytes.
 */
RAC_API rac_result_t rac_llm_hybrid_router_set_policy_proto(
    rac_handle_t   handle,
    const uint8_t* policy_bytes,
    size_t         policy_size);

/**
 * Dispatch one text-generation request through the router.
 *
 * Builds the per-request routing context from the
 * `rac_hybrid_device_state` vtable snapshot (is_online, battery_percent,
 * thermal_throttled). HybridRoutingContext on the wire currently carries
 * no caller-supplied fields; future per-call hints can be added there.
 *
 * The output is a serialized runanywhere.v1.HybridLlmGenerateResponse.
 * On success, @p *out_response_bytes points at a heap allocation that
 * the caller MUST release via rac_llm_hybrid_router_proto_buffer_free.
 * On failure, @p *out_response_bytes is set to NULL and @p
 * *out_response_size to 0.
 *
 * @param handle              Router handle.
 * @param request_bytes       Serialized runanywhere.v1.HybridLlmGenerateRequest.
 * @param request_size        Length of @p request_bytes.
 * @param out_response_bytes  Receives heap-allocated response bytes.
 * @param out_response_size   Receives length of @p *out_response_bytes.
 */
RAC_API rac_result_t rac_llm_hybrid_router_generate_proto(
    rac_handle_t   handle,
    const uint8_t* request_bytes,
    size_t         request_size,
    uint8_t**      out_response_bytes,
    size_t*        out_response_size);

/**
 * Release a buffer returned by rac_llm_hybrid_router_generate_proto.
 * NULL-safe.
 */
RAC_API void rac_llm_hybrid_router_proto_buffer_free(uint8_t* response_bytes);

/**
 * Per-token callback fired during streaming. Return RAC_TRUE to keep
 * receiving tokens; RAC_FALSE asks the engine to stop the stream early.
 *
 * @param token      NUL-terminated UTF-8 token text; lifetime is the
 *                   duration of the call.
 * @param user_data  Opaque cookie passed by the binding.
 */
typedef rac_bool_t (*rac_hybrid_stream_token_fn)(const char* token, void* user_data);

/**
 * End-of-stream callback fired exactly once after the stream terminates
 * (success, cancellation, or failure including failed-fallback).
 *
 * @param rc                The final native rc returned by
 *                          rac_llm_hybrid_router_generate_stream.
 * @param response_bytes    Serialized runanywhere.v1.HybridLlmGenerateResponse.
 *                          The `text` field is empty (tokens were delivered
 *                          via @ref rac_hybrid_stream_token_fn) and `routing`
 *                          carries the final HybridRoutedMetadata. Owned by
 *                          the callee for the duration of the callback only.
 * @param response_size     Length of @p response_bytes.
 * @param user_data         Same cookie passed to generate_stream_proto.
 */
typedef void (*rac_hybrid_stream_done_fn)(rac_result_t   rc,
                                          const uint8_t* response_bytes,
                                          size_t         response_size,
                                          void*          user_data);

/**
 * Streaming variant of rac_llm_hybrid_router_generate_proto. Tokens flow
 * through @p on_token; the final routing metadata is delivered to
 * @p on_done. Returns the same rc as @p on_done so callers that don't
 * need the proto envelope can short-circuit.
 *
 * @param handle          Router handle.
 * @param request_bytes   Serialized runanywhere.v1.HybridLlmGenerateRequest.
 * @param request_size    Length of @p request_bytes.
 * @param on_token        Per-token callback (non-NULL).
 * @param on_done         End-of-stream callback (may be NULL).
 * @param user_data       Opaque cookie forwarded to both callbacks.
 */
RAC_API rac_result_t rac_llm_hybrid_router_generate_stream_proto(
    rac_handle_t                handle,
    const uint8_t*              request_bytes,
    size_t                      request_size,
    rac_hybrid_stream_token_fn  on_token,
    rac_hybrid_stream_done_fn   on_done,
    void*                       user_data);

#ifdef __cplusplus
}
#endif

#endif  // RAC_LLM_HYBRID_ROUTER_PROTO_H