/**
 * @file json_utils.h
 * @brief JSON utilities for OpenAI API serialization
 */

#ifndef RAC_JSON_UTILS_H
#define RAC_JSON_UTILS_H

#include "rac/server/rac_openai_types.h"
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace rac {
namespace server {
namespace json {

using Json = nlohmann::json;

// =============================================================================
// PARSING (JSON -> C types)
// =============================================================================

/**
 * @brief Parse a chat completion request from JSON
 *
 * @param json Input JSON
 * @param request Output request structure
 * @return true on success, false on parse error
 */
bool parseChatRequest(const Json& json, rac_openai_chat_request_t& request);

/**
 * @brief Parse messages array from JSON
 *
 * @param json Messages JSON array
 * @param messages Output vector of messages (caller manages memory)
 * @return true on success
 */
bool parseMessages(const Json& json, std::vector<rac_openai_message_t>& messages);

/**
 * @brief Parse tools array from JSON
 *
 * @param json Tools JSON array
 * @param tools Output vector of tools (caller manages memory)
 * @return true on success
 */
bool parseTools(const Json& json, std::vector<rac_openai_tool_t>& tools);

// =============================================================================
// SERIALIZATION (C types -> JSON)
// =============================================================================

/**
 * @brief Serialize a chat completion response to JSON
 */
Json serializeChatResponse(const rac_openai_chat_response_t& response);

/**
 * @brief Serialize a streaming chunk to JSON
 */
Json serializeStreamChunk(const rac_openai_stream_chunk_t& chunk);

/**
 * @brief Serialize models list to JSON
 */
Json serializeModelsResponse(const rac_openai_models_response_t& response);

/**
 * @brief Serialize a single model to JSON
 */
Json serializeModel(const rac_openai_model_t& model);

/**
 * @brief Serialize usage statistics to JSON
 */
Json serializeUsage(const rac_openai_usage_t& usage);

/**
 * @brief Serialize a tool call to JSON
 */
Json serializeToolCall(const rac_openai_tool_call_t& toolCall);

/**
 * @brief Create an error response JSON
 */
Json createErrorResponse(const std::string& message, const std::string& type, int code);

// =============================================================================
// STREAMING HELPERS
// =============================================================================

/**
 * @brief Format a chunk for SSE (Server-Sent Events)
 *
 * @param chunk JSON chunk
 * @return "data: {json}\n\n" formatted string
 */
std::string formatSSE(const Json& chunk);

/**
 * @brief Format the final SSE done message
 *
 * @return "data: [DONE]\n\n"
 */
std::string formatSSEDone();

// =============================================================================
// PROMPT BUILDING
// =============================================================================

/**
 * @brief Build a prompt string from messages
 *
 * Converts OpenAI-style messages into a format suitable for the LLM.
 * This uses a simple chat format; models with special templates
 * should use their own formatting.
 *
 * @param messages Array of messages
 * @param numMessages Number of messages
 * @param includeSystemPrompt Whether to include system messages
 * @return Formatted prompt string
 */
std::string buildPrompt(const rac_openai_message_t* messages,
                        size_t numMessages,
                        bool includeSystemPrompt = true);

/**
 * @brief Build a prompt with tools
 *
 * Formats the prompt to include tool definitions for models
 * that support function calling.
 *
 * @param messages Array of messages
 * @param numMessages Number of messages
 * @param tools Array of tools
 * @param numTools Number of tools
 * @return Formatted prompt string with tool instructions
 */
std::string buildPromptWithTools(const rac_openai_message_t* messages,
                                  size_t numMessages,
                                  const rac_openai_tool_t* tools,
                                  size_t numTools);

} // namespace json
} // namespace server
} // namespace rac

#endif // RAC_JSON_UTILS_H
