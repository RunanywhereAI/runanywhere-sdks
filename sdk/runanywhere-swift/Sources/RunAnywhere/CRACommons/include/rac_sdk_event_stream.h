/**
 * @file rac_sdk_event_stream.h
 * @brief Canonical SDKEvent proto-byte event stream.
 */

#ifndef RAC_SDK_EVENT_STREAM_H
#define RAC_SDK_EVENT_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rac_sdk_event_callback_fn)(const uint8_t* proto_bytes,
                                          size_t proto_size,
                                          void* user_data);

RAC_API uint64_t rac_sdk_event_subscribe(rac_sdk_event_callback_fn callback,
                                         void* user_data);
RAC_API void rac_sdk_event_unsubscribe(uint64_t subscription_id);
RAC_API rac_result_t rac_sdk_event_publish_proto(const uint8_t* proto_bytes,
                                                size_t proto_size);
RAC_API rac_result_t rac_sdk_event_poll(rac_proto_buffer_t* out_event);
RAC_API rac_result_t rac_sdk_event_publish_failure(rac_result_t error_code,
                                                  const char* message,
                                                  const char* component,
                                                  const char* operation,
                                                  rac_bool_t recoverable);
RAC_API void rac_sdk_event_clear_queue(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_SDK_EVENT_STREAM_H */
