/**
 * @file rac_openai_types.h
 * @brief RunAnywhere Commons - OpenAI-Compatible API Types
 *
 * This header defines C types that mirror the OpenAI API format for
 * interoperability with tools like Clawdbot, LM Studio, and other
 * OpenAI-compatible clients.
 *
 * These types are used internally by the server to parse requests and
 * format responses. They are exposed here for clients that want to
 * construct requests programmatically in C.
 *
 * @see https://platform.openai.com/docs/api-reference/chat
 */

#ifndef RAC_OPENAI_TYPES_H
#define RAC_OPENAI_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MESSAGE ROLES
// =============================================================================

/**
 * @brief Message role in a conversation
 */
typedef enum rac_openai_role {
    RAC_OPENAI_ROLE_SYSTEM = 0,    /**< System message (instructions) */
    RAC_OPENAI_ROLE_USER = 1,      /**< User message (input) */
    RAC_OPENAI_ROLE_ASSISTANT = 2, /**< Assistant message (output) */
    RAC_OPENAI_ROLE_TOOL = 3,      /**< Tool result message */
} rac_openai_role_t;

/**
 * @brief Convert role enum to string
 */
static inline const char* rac_openai_role_to_string(rac_openai_role_t role) {
    switch (role) {
        case RAC_OPENAI_ROLE_SYSTEM: return "system";
        case RAC_OPENAI_ROLE_USER: return "user";
        case RAC_OPENAI_ROLE_ASSISTANT: return "assistant";
        case RAC_OPENAI_ROLE_TOOL: return "tool";
        default: return "unknown";
    }
}

// =============================================================================
// CHAT MESSAGE
// =============================================================================

/**
 * @brief A single message in a chat conversation
 *
 * Mirrors OpenAI's ChatCompletionRequestMessage.
 */
typedef struct rac_openai_message {
    /** Message role */
    rac_openai_role_t role;

    /** Message content (can be NULL for assistant messages with tool_calls) */
    const char* content;

    /** Tool call ID (only for role=tool, references the tool_call that this responds to) */
    const char* tool_call_id;

    /** Name of the function (only for role=tool) */
    const char* name;
} rac_openai_message_t;

// =============================================================================
// TOOL / FUNCTION CALLING
// =============================================================================

/**
 * @brief JSON Schema parameter definition
 *
 * Simplified representation of JSON Schema for function parameters.
 */
typedef struct rac_openai_function_param {
    /** Parameter name */
    const char* name;

    /** Parameter type (e.g., "string", "number", "boolean", "object", "array") */
    const char* type;

    /** Parameter description */
    const char* description;

    /** Whether this parameter is required */
    rac_bool_t required;

    /** Enum values (JSON array string, can be NULL) */
    const char* enum_values;
} rac_openai_function_param_t;

/**
 * @brief Function definition for tool calling
 *
 * Mirrors OpenAI's FunctionDefinition.
 */
typedef struct rac_openai_function {
    /** Function name (required) */
    const char* name;

    /** Function description */
    const char* description;

    /** Parameters as JSON Schema string (can be NULL for no parameters) */
    const char* parameters_json;

    /** Strict mode - enforce schema validation (default: false) */
    rac_bool_t strict;
} rac_openai_function_t;

/**
 * @brief Tool definition
 *
 * Mirrors OpenAI's ChatCompletionTool.
 */
typedef struct rac_openai_tool {
    /** Tool type (always "function" for now) */
    const char* type;

    /** Function definition */
    rac_openai_function_t function;
} rac_openai_tool_t;

/**
 * @brief Tool call in assistant response
 *
 * Mirrors OpenAI's ChatCompletionMessageToolCall.
 */
typedef struct rac_openai_tool_call {
    /** Unique ID for this tool call */
    const char* id;

    /** Tool type (always "function") */
    const char* type;

    /** Function name */
    const char* function_name;

    /** Function arguments as JSON string */
    const char* function_arguments;
} rac_openai_tool_call_t;

// =============================================================================
// CHAT COMPLETION REQUEST
// =============================================================================

/**
 * @brief Chat completion request
 *
 * Mirrors OpenAI's CreateChatCompletionRequest.
 */
typedef struct rac_openai_chat_request {
    /** Model ID to use */
    const char* model;

    /** Array of messages */
    const rac_openai_message_t* messages;
    size_t num_messages;

    /** Temperature (0.0 - 2.0, default: 1.0) */
    float temperature;

    /** Top-p sampling (0.0 - 1.0, default: 1.0) */
    float top_p;

    /** Maximum tokens to generate (default: model-specific) */
    int32_t max_tokens;

    /** Whether to stream responses */
    rac_bool_t stream;

    /** Stop sequences (can be NULL) */
    const char* const* stop;
    size_t num_stop;

    /** Presence penalty (-2.0 - 2.0, default: 0.0) */
    float presence_penalty;

    /** Frequency penalty (-2.0 - 2.0, default: 0.0) */
    float frequency_penalty;

    /** Tool definitions (can be NULL) */
    const rac_openai_tool_t* tools;
    size_t num_tools;

    /** Tool choice: "none", "auto", "required", or specific function name */
    const char* tool_choice;

    /** User identifier for abuse detection (optional) */
    const char* user;
} rac_openai_chat_request_t;

/**
 * @brief Default chat request values
 */
static const rac_openai_chat_request_t RAC_OPENAI_CHAT_REQUEST_DEFAULT = {
    .model = RAC_NULL,
    .messages = RAC_NULL,
    .num_messages = 0,
    .temperature = 1.0f,
    .top_p = 1.0f,
    .max_tokens = -1,  // Model-specific default
    .stream = RAC_FALSE,
    .stop = RAC_NULL,
    .num_stop = 0,
    .presence_penalty = 0.0f,
    .frequency_penalty = 0.0f,
    .tools = RAC_NULL,
    .num_tools = 0,
    .tool_choice = RAC_NULL,
    .user = RAC_NULL
};

// =============================================================================
// CHAT COMPLETION RESPONSE
// =============================================================================

/**
 * @brief Finish reason for generation
 */
typedef enum rac_openai_finish_reason {
    RAC_OPENAI_FINISH_NONE = 0,       /**< Still generating */
    RAC_OPENAI_FINISH_STOP = 1,       /**< Natural stop or stop sequence */
    RAC_OPENAI_FINISH_LENGTH = 2,     /**< Max tokens reached */
    RAC_OPENAI_FINISH_TOOL_CALLS = 3, /**< Model wants to call tools */
    RAC_OPENAI_FINISH_ERROR = 4,      /**< Error occurred */
} rac_openai_finish_reason_t;

/**
 * @brief Convert finish reason to string
 */
static inline const char* rac_openai_finish_reason_to_string(rac_openai_finish_reason_t reason) {
    switch (reason) {
        case RAC_OPENAI_FINISH_STOP: return "stop";
        case RAC_OPENAI_FINISH_LENGTH: return "length";
        case RAC_OPENAI_FINISH_TOOL_CALLS: return "tool_calls";
        case RAC_OPENAI_FINISH_ERROR: return "error";
        default: return RAC_NULL;
    }
}

/**
 * @brief Assistant message in response
 */
typedef struct rac_openai_assistant_message {
    /** Role (always "assistant") */
    rac_openai_role_t role;

    /** Generated content (can be NULL if tool_calls present) */
    char* content;

    /** Tool calls (can be NULL) */
    rac_openai_tool_call_t* tool_calls;
    size_t num_tool_calls;
} rac_openai_assistant_message_t;

/**
 * @brief A single choice in the response
 */
typedef struct rac_openai_choice {
    /** Choice index */
    int32_t index;

    /** Generated message */
    rac_openai_assistant_message_t message;

    /** Finish reason */
    rac_openai_finish_reason_t finish_reason;
} rac_openai_choice_t;

/**
 * @brief Token usage statistics
 */
typedef struct rac_openai_usage {
    /** Tokens in the prompt */
    int32_t prompt_tokens;

    /** Tokens in the completion */
    int32_t completion_tokens;

    /** Total tokens */
    int32_t total_tokens;
} rac_openai_usage_t;

/**
 * @brief Chat completion response
 *
 * Mirrors OpenAI's CreateChatCompletionResponse.
 */
typedef struct rac_openai_chat_response {
    /** Unique response ID */
    char* id;

    /** Object type (always "chat.completion") */
    const char* object;

    /** Unix timestamp of creation */
    int64_t created;

    /** Model used */
    const char* model;

    /** Choices (usually 1) */
    rac_openai_choice_t* choices;
    size_t num_choices;

    /** Token usage */
    rac_openai_usage_t usage;

    /** System fingerprint (optional) */
    const char* system_fingerprint;
} rac_openai_chat_response_t;

// =============================================================================
// STREAMING CHUNK
// =============================================================================

/**
 * @brief Delta content in streaming chunk
 */
typedef struct rac_openai_delta {
    /** Role (only in first chunk) */
    const char* role;

    /** Content delta (partial token) */
    const char* content;

    /** Tool calls delta (can be NULL) */
    rac_openai_tool_call_t* tool_calls;
    size_t num_tool_calls;
} rac_openai_delta_t;

/**
 * @brief Streaming choice chunk
 */
typedef struct rac_openai_stream_choice {
    /** Choice index */
    int32_t index;

    /** Delta content */
    rac_openai_delta_t delta;

    /** Finish reason (NULL until done) */
    rac_openai_finish_reason_t finish_reason;
} rac_openai_stream_choice_t;

/**
 * @brief Streaming response chunk
 *
 * Mirrors OpenAI's CreateChatCompletionStreamResponse.
 */
typedef struct rac_openai_stream_chunk {
    /** Unique response ID */
    const char* id;

    /** Object type (always "chat.completion.chunk") */
    const char* object;

    /** Unix timestamp of creation */
    int64_t created;

    /** Model used */
    const char* model;

    /** Choices (usually 1) */
    rac_openai_stream_choice_t* choices;
    size_t num_choices;
} rac_openai_stream_chunk_t;

// =============================================================================
// MODELS ENDPOINT
// =============================================================================

/**
 * @brief Model information
 *
 * Mirrors OpenAI's Model object.
 */
typedef struct rac_openai_model {
    /** Model ID */
    const char* id;

    /** Object type (always "model") */
    const char* object;

    /** Unix timestamp of creation */
    int64_t created;

    /** Owner (always "runanywhere") */
    const char* owned_by;
} rac_openai_model_t;

/**
 * @brief Models list response
 */
typedef struct rac_openai_models_response {
    /** Object type (always "list") */
    const char* object;

    /** Array of models */
    rac_openai_model_t* data;
    size_t num_data;
} rac_openai_models_response_t;

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free a chat response
 *
 * @param response Response to free (can be NULL)
 */
RAC_API void rac_openai_chat_response_free(rac_openai_chat_response_t* response);

/**
 * @brief Free a models response
 *
 * @param response Response to free (can be NULL)
 */
RAC_API void rac_openai_models_response_free(rac_openai_models_response_t* response);

#ifdef __cplusplus
}
#endif

#endif /* RAC_OPENAI_TYPES_H */
