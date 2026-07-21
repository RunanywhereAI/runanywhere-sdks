/**
 * @file rac_connect.h
 * @brief Transport-independent host/client policy and session ABI.
 *
 * Commons owns the platform-role policy, protocol version, host session
 * registry, protobuf handshake, and remote invocation validation. Platform
 * SDKs own discovery, transport adapters, permissions, and user-visible state.
 */

#ifndef RAC_CONNECT_H
#define RAC_CONNECT_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Return the authoritative host/client role availability for a platform.
 *
 * Accepts ConnectPlatformPolicyRequest and returns ConnectPlatformPolicy.
 * Platform SDKs may use this to shape UI, while every C++ entrypoint still
 * enforces the same policy independently.
 */
RAC_API rac_result_t rac_connect_get_platform_policy_proto(const uint8_t* request_bytes,
                                                           size_t request_size,
                                                           rac_proto_buffer_t* out_platform_policy);

/**
 * Start the process-local host state from a serialized
 * runanywhere.v1.ConnectHostStartRequest.
 *
 * Commons evaluates the requested platform through its role policy, validates
 * the selected loaded model, generates an ephemeral host instance id, and
 * returns ConnectHostState.
 * The platform adapter publishes the returned discovery metadata only after
 * this call succeeds.
 */
RAC_API rac_result_t rac_connect_host_start_proto(const uint8_t* request_bytes, size_t request_size,
                                                  rac_proto_buffer_t* out_host_state);

/** Stop the process-local host state and invalidate every active session. */
RAC_API rac_result_t rac_connect_host_stop_proto(const uint8_t* request_bytes, size_t request_size,
                                                 rac_proto_buffer_t* out_host_state);

/**
 * Create a canonical client hello from ConnectClientStartRequest.
 *
 * Commons accepts only platforms whose client role is currently enabled. The
 * generated instance id is ephemeral and non-secret.
 */
RAC_API rac_result_t rac_connect_client_create_hello_proto(const uint8_t* request_bytes,
                                                           size_t request_size,
                                                           rac_proto_buffer_t* out_client_hello);

/**
 * Validate a client hello against the active host and return an accepted
 * or rejected ConnectHandshakeResponse. Accepted responses reserve a session
 * id in the commons host registry until closed or hosting stops.
 */
RAC_API rac_result_t rac_connect_host_accept_client_proto(const uint8_t* hello_bytes,
                                                          size_t hello_size,
                                                          rac_proto_buffer_t* out_response);

/**
 * Validate the host's ConnectHandshakeResponse on a client and return its
 * typed ConnectClientSessionState.
 */
RAC_API rac_result_t rac_connect_client_validate_host_proto(const uint8_t* response_bytes,
                                                            size_t response_size,
                                                            rac_proto_buffer_t* out_session_state);

/**
 * Release an active host session after its platform transport terminates.
 * Unknown session ids are rejected to keep the host registry authoritative.
 */
RAC_API rac_result_t rac_connect_host_close_session_proto(const uint8_t* request_bytes,
                                                          size_t request_size,
                                                          rac_proto_buffer_t* out_host_state);

/**
 * Validate a typed remote generation request before the platform host runtime
 * executes it. The request must belong to an active Connect session and name
 * the model published when the host started.
 */
RAC_API rac_result_t rac_connect_host_validate_invocation_proto(const uint8_t* request_bytes,
                                                                size_t request_size,
                                                                rac_proto_buffer_t* out_validation);

#ifdef __cplusplus
}
#endif

#endif  // RAC_CONNECT_H
