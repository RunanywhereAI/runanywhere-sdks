/**
 * @file rac_tool_calling.h
 * @brief Generated-proto tool-calling C ABI.
 *
 * Commons owns parsing, validation, prompt formatting, orchestration, and
 * cancellation. SDKs exchange only serialized runanywhere.v1 messages; host
 * adapters own tool registration and side effects.
 */

#ifndef RAC_TOOL_CALLING_H
#define RAC_TOOL_CALLING_H

#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_API rac_result_t rac_tool_call_parse_proto(const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_tool_call_validate_proto(const uint8_t* request_proto_bytes,
                                                  size_t request_proto_size,
                                                  rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_tool_call_format_prompt_proto(const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_tool_value_to_json_proto(const uint8_t* in_tool_value_bytes,
                                                  size_t in_size,
                                                  rac_proto_buffer_t* out_string_proto);

RAC_API rac_result_t rac_tool_value_from_json_proto(const uint8_t* in_string_bytes,
                                                    size_t in_size,
                                                    rac_proto_buffer_t* out_tool_value);

typedef void (*rac_tool_calling_session_event_callback_fn)(const uint8_t* event_bytes,
                                                           size_t event_size,
                                                           void* user_data);

/**
 * Fired synchronously after a cancellable handle is created and before the
 * first generation begins. The callback must publish the handle promptly and
 * must not re-enter a rac_tool_calling_* API.
 */
typedef void (*rac_tool_calling_handle_published_callback_fn)(uint64_t handle, void* user_data);

RAC_API rac_result_t rac_tool_calling_session_create_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_tool_calling_session_event_callback_fn callback, void* user_data,
    rac_tool_calling_handle_published_callback_fn on_handle_published,
    void* on_handle_user_data);

RAC_API rac_result_t rac_tool_calling_session_step_with_result_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size);

RAC_API rac_result_t rac_tool_calling_session_destroy_proto(uint64_t session_handle);
RAC_API rac_result_t rac_tool_calling_session_cancel_proto(uint64_t session_handle);

/**
 * Synchronous host executor used by the single-call run loop. Input is a
 * serialized ToolCall; output must be an owned serialized ToolResult buffer.
 */
typedef rac_result_t (*rac_tool_execute_callback_fn)(const uint8_t* in_tool_call_bytes,
                                                     size_t in_size,
                                                     rac_proto_buffer_t* out_tool_result_bytes,
                                                     void* user_data);

RAC_API rac_result_t rac_tool_calling_run_loop_proto(
    const uint8_t* in_request_bytes, size_t in_size,
    rac_tool_execute_callback_fn on_execute, void* on_execute_user_data,
    rac_tool_calling_handle_published_callback_fn on_handle_published,
    void* on_handle_user_data, rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_tool_calling_run_loop_cancel_proto(uint64_t run_loop_handle);

#ifdef __cplusplus
}
#endif

#endif  // RAC_TOOL_CALLING_H
