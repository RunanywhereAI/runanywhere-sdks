/**
 * @file rac_connect_transport.h
 * @brief Platform-neutral channel transport vtable for RunAnywhere Connect.
 *
 * Commons owns Connect protocol messages, role/session policy, and dispatch.
 * Platform SDKs provide discovery plus a channel adapter through this ABI.
 * Endpoint bytes are opaque to commons: Bonjour, Android NSD, a future
 * Windows discovery provider, and a future relay may each use their native
 * endpoint representation without changing the Connect state machine.
 *
 * The operations are synchronous by contract and may block. SDKs must invoke
 * the public dispatch functions from a worker/transport queue, never from a UI
 * thread. Every logical payload is one complete protobuf frame; stream
 * segmentation and reassembly belong to the adapter.
 */

#ifndef RAC_CONNECT_TRANSPORT_H
#define RAC_CONNECT_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RAC_CONNECT_TRANSPORT_ABI_VERSION ((uint32_t)1u)

typedef uint64_t rac_connect_channel_t;
#define RAC_CONNECT_INVALID_CHANNEL ((rac_connect_channel_t)0u)

/**
 * Opaque endpoint token produced by a platform discovery adapter.
 *
 * The bytes are borrowed for the duration of open(). Commons never parses or
 * persists them.
 */
typedef struct rac_connect_endpoint {
    const uint8_t* data;
    size_t size;
} rac_connect_endpoint_t;

/**
 * Platform channel operations.
 *
 * open/send/receive/close are mandatory. init/destroy are optional lifecycle
 * hooks. The adapter must be thread-safe because commons may dispatch on more
 * than one worker.
 */
typedef struct rac_connect_transport_ops {
    uint32_t abi_version;
    size_t struct_size;

    rac_result_t (*open)(void* user_data, const rac_connect_endpoint_t* endpoint,
                         rac_connect_channel_t* out_channel);
    rac_result_t (*send)(void* user_data, rac_connect_channel_t channel, const uint8_t* payload,
                         size_t payload_size);
    rac_result_t (*receive)(void* user_data, rac_connect_channel_t channel,
                            rac_proto_buffer_t* out_payload);
    rac_result_t (*close)(void* user_data, rac_connect_channel_t channel);

    rac_result_t (*init)(void* user_data);
    void (*destroy)(void* user_data);
} rac_connect_transport_ops_t;

/**
 * Install or replace the process-wide Connect transport.
 *
 * The vtable is copied during registration. Passing NULL unregisters the
 * active adapter. Replaced adapters are destroyed only after all in-flight
 * calls release their registry snapshot.
 */
RAC_API rac_result_t rac_connect_transport_register(const rac_connect_transport_ops_t* ops,
                                                    void* user_data);

RAC_API rac_bool_t rac_connect_transport_is_registered(void);

/** Dispatch one operation through the currently registered adapter. */
RAC_API rac_result_t rac_connect_transport_open(const rac_connect_endpoint_t* endpoint,
                                                rac_connect_channel_t* out_channel);
RAC_API rac_result_t rac_connect_transport_send(rac_connect_channel_t channel,
                                                const uint8_t* payload, size_t payload_size);
RAC_API rac_result_t rac_connect_transport_receive(rac_connect_channel_t channel,
                                                   rac_proto_buffer_t* out_payload);
RAC_API rac_result_t rac_connect_transport_close(rac_connect_channel_t channel);

#ifdef __cplusplus
}
#endif

#endif  // RAC_CONNECT_TRANSPORT_H
