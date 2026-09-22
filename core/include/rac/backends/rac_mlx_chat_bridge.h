/**
 * @file rac_mlx_chat_bridge.h
 * @brief MLX-private typed view of a structured LLM request.
 *
 * The MLX engine parses the canonical LLMGenerateRequest protobuf and exposes
 * this borrowed view to Swift for the duration of one synchronous callback.
 * Swift must copy any values it retains.
 */

#ifndef RAC_BACKENDS_RAC_MLX_CHAT_BRIDGE_H
#define RAC_BACKENDS_RAC_MLX_CHAT_BRIDGE_H

#include "rac/backends/rac_mlx.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ra_mlx_chat_tool_call_view {
    const char* id;
    const char* name;
    const char* arguments_json;
} ra_mlx_chat_tool_call_view_t;

typedef struct ra_mlx_chat_tool_result_view {
    const char* tool_call_id;
    const char* name;
    const char* result_json;
    const char* error;
    rac_bool_t is_error;
} ra_mlx_chat_tool_result_view_t;

typedef struct ra_mlx_chat_message_view {
    const char* role;
    const char* content;
    const char* name;
    const char* tool_call_id;
    const ra_mlx_chat_tool_call_view_t* tool_calls;
    size_t tool_call_count;
    const ra_mlx_chat_tool_result_view_t* tool_result;
    rac_bool_t has_attachments;
} ra_mlx_chat_message_view_t;

typedef struct ra_mlx_chat_tool_definition_view {
    const char* name;
    const char* description;
    const char* parameters_json;
} ra_mlx_chat_tool_definition_view_t;

typedef struct ra_mlx_chat_options_view {
    rac_bool_t has_max_output_tokens;
    int32_t max_output_tokens;
    rac_bool_t has_temperature;
    float temperature;
    rac_bool_t has_top_p;
    float top_p;
    rac_bool_t has_top_k;
    int32_t top_k;
    rac_bool_t has_repeat_penalty;
    float repeat_penalty;
    rac_bool_t has_seed;
    int64_t seed;
    rac_bool_t has_frequency_penalty;
    float frequency_penalty;
    rac_bool_t has_presence_penalty;
    float presence_penalty;
    rac_bool_t has_min_p;
    float min_p;
    const char* system_prompt;
    rac_bool_t disable_thinking;
} ra_mlx_chat_options_view_t;

typedef struct ra_mlx_chat_request_view {
    const char* model_id;
    ra_mlx_chat_options_view_t options;
    const ra_mlx_chat_message_view_t* messages;
    size_t message_count;
    const ra_mlx_chat_tool_definition_view_t* tools;
    size_t tool_count;
} ra_mlx_chat_request_view_t;

typedef rac_result_t (*ra_mlx_llm_generate_chat_typed_fn)(
    rac_handle_t handle, const ra_mlx_chat_request_view_t* request,
    rac_llm_stream_callback_fn callback, void* callback_user_data, void* user_data);

RAC_API rac_result_t ra_mlx_set_chat_callback(ra_mlx_llm_generate_chat_typed_fn callback,
                                               void* user_data);

#ifdef __cplusplus
}
#endif

#endif  // RAC_BACKENDS_RAC_MLX_CHAT_BRIDGE_H
