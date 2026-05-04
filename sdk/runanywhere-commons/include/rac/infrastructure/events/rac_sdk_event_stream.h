/**
 * @file rac_sdk_event_stream.h
 * @brief Canonical SDKEvent proto-byte event stream.
 *
 * Platform SDKs subscribe to this stream to receive serialized
 * runanywhere.v1.SDKEvent bytes. Callback memory is owned by commons and is
 * valid only for the duration of the callback; retainers must copy it.
 * Polling returns an owned rac_proto_buffer_t that callers release with
 * rac_proto_buffer_free().
 */

#ifndef RAC_SDK_EVENT_STREAM_H
#define RAC_SDK_EVENT_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rac_sdk_event_callback_fn)(const uint8_t* proto_bytes,
                                          size_t proto_size,
                                          void* user_data);

/**
 * @brief Subscribe to serialized runanywhere.v1.SDKEvent bytes.
 *
 * @return Subscription id, or 0 when callback is NULL.
 */
RAC_API uint64_t rac_sdk_event_subscribe(rac_sdk_event_callback_fn callback,
                                         void* user_data);

RAC_API void rac_sdk_event_unsubscribe(uint64_t subscription_id);

/**
 * @brief Publish serialized runanywhere.v1.SDKEvent bytes.
 *
 * The bytes are copied into the internal poll queue before callbacks run.
 */
RAC_API rac_result_t rac_sdk_event_publish_proto(const uint8_t* proto_bytes,
                                                size_t proto_size);

/**
 * @brief Poll the next queued SDKEvent.
 *
 * On success, out_event owns the returned data and must be freed with
 * rac_proto_buffer_free(). Returns RAC_ERROR_NOT_FOUND when the queue is empty.
 */
RAC_API rac_result_t rac_sdk_event_poll(rac_proto_buffer_t* out_event);

/**
 * @brief Publish a canonical failure event.
 */
RAC_API rac_result_t rac_sdk_event_publish_failure(rac_result_t error_code,
                                                  const char* message,
                                                  const char* component,
                                                  const char* operation,
                                                  rac_bool_t recoverable);

/**
 * @brief Test helper: clear queued events without changing subscriptions.
 */
RAC_API void rac_sdk_event_clear_queue(void);

#ifdef __cplusplus
}

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace rac {
namespace events {

rac_result_t publish_initialization_started(void);
rac_result_t publish_initialization_completed(void);
rac_result_t publish_initialization_failed(rac_result_t error_code, const char* message);
rac_result_t publish_shutdown(void);
rac_result_t publish_device_registered(const char* device_id);
rac_result_t publish_device_registration_failed(rac_result_t error_code, const char* message);
rac_result_t publish_device_registration_state_changed(bool registered);
rac_result_t publish_hardware_profile_completed(const uint8_t* profile_bytes, size_t profile_size);
rac_result_t publish_route_selected(rac_primitive_t primitive,
                                    const rac_engine_vtable_t* vtable,
                                    const char* reason);
rac_result_t publish_route_failed(rac_primitive_t primitive,
                                  rac_result_t error_code,
                                  const char* reason);

}  // namespace events
}  // namespace rac
#endif

#endif /* RAC_SDK_EVENT_STREAM_H */
