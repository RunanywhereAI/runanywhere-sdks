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

/**
 * Validate a typed remote cancellation request before the platform host
 * runtime cancels the matching in-flight generation. The request must belong
 * to an active Connect session and name a non-empty request id.
 */
RAC_API rac_result_t rac_connect_host_validate_cancel_proto(const uint8_t* request_bytes,
                                                            size_t request_size,
                                                            rac_proto_buffer_t* out_validation);

/* ===========================================================================
 * Cluster Orchestration (Issue #541: Local AI Cluster / Pipeline Sharding)
 * =========================================================================== */

/**
 * Start a local AI cluster coordinator session from a serialized
 * runanywhere.v1.ClusterStartRequest. Validates peer assignments and returns
 * the active ClusterState.
 */
RAC_API rac_result_t rac_connect_cluster_start_proto(const uint8_t* request_bytes,
                                                     size_t request_size,
                                                     rac_proto_buffer_t* out_cluster_state);

/**
 * Join a cluster as a peer from a serialized runanywhere.v1.ClusterJoinRequest.
 * Checks the peer appears in the cluster's layer assignments and, when it advertises
 * a non-zero max_layers, that its assigned span fits within it; returns a
 * ClusterStartResponse echoing the peer's capability.
 */
RAC_API rac_result_t rac_connect_cluster_join_proto(const uint8_t* request_bytes,
                                                    size_t request_size,
                                                    rac_proto_buffer_t* out_response);

/**
 * Stop an active cluster coordinator session and clear peer states.
 */
RAC_API rac_result_t rac_connect_cluster_stop_proto(const uint8_t* request_bytes,
                                                    size_t request_size,
                                                    rac_proto_buffer_t* out_cluster_state);

/**
 * Validate an intermediate activation tensor payload between pipeline stages.
 * Accepts ClusterActivation and verifies cluster binding, valid layer boundaries,
 * tensor dimensions, element format (dtype), and exact byte count matching
 * seq_len * hidden_size * element_size in row-major little-endian format.
 * (Validation only; transport occurs out-of-band).
 */
RAC_API rac_result_t
rac_connect_cluster_validate_activation_proto(const uint8_t* request_bytes,
                                              size_t request_size,
                                              rac_proto_buffer_t* out_validation);

/**
 * Decoded activation tensor representation in host memory.
 */
typedef struct rac_connect_decoded_activation {
    uint32_t dtype;          /**< ClusterActivationDtype enum value */
    uint32_t seq_len;        /**< Sequence length dimension */
    uint32_t hidden_size;    /**< Hidden size dimension */
    size_t element_count;    /**< seq_len * hidden_size */
    size_t element_size;     /**< 2 for FP16/BF16, 4 for FP32 */
    size_t total_bytes;      /**< element_count * element_size */
} rac_connect_decoded_activation_t;

/**
 * Decode an intermediate activation tensor payload from wire bytes into host memory.
 *
 * Reads ClusterActivation.dtype first, validates that the payload byte count
 * matches seq_len * hidden_size * element_size in row-major order, and
 * byte-swaps elements on big-endian hosts from wire little-endian to native
 * host byte order.
 *
 * If expected_dtype is not 0 (CLUSTER_ACTIVATION_DTYPE_UNSPECIFIED), verifies
 * that the activation's dtype matches expected_dtype, rejecting a mismatch with
 * RAC_ERROR_INVALID_FORMAT.
 *
 * @param activation_bytes Serialized runanywhere.v1.ClusterActivation bytes.
 * @param activation_size Size of activation_bytes.
 * @param expected_dtype Expected ClusterActivationDtype (or 0 to accept any valid declared dtype).
 * @param out_host_tensor Output buffer for the decoded host-endian tensor bytes (owned by caller, free with rac_proto_buffer_free).
 * @param out_metadata Optional pointer to receive tensor dimensions and dtype metadata.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_FORMAT if dtype is unspecified/unknown or doesn't match expected_dtype or payload size mismatch, RAC_ERROR_INVALID_ARGUMENT on dimension overflow or invalid parameters.
 */
RAC_API rac_result_t
rac_connect_cluster_decode_activation_proto(const uint8_t* activation_bytes,
                                            size_t activation_size,
                                            uint32_t expected_dtype,
                                            rac_proto_buffer_t* out_host_tensor,
                                            rac_connect_decoded_activation_t* out_metadata);

#ifdef __cplusplus
}
#endif

#endif  // RAC_CONNECT_H
