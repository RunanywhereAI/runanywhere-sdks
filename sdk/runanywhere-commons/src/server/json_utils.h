/**
 * @file json_utils.h
 * @brief JSON utilities for OpenAI API serialization
 *
 * This file handles OpenAI-specific JSON format serialization.
 * For prompt building, use openai_translation.h which delegates to Commons.
 */

#ifndef RAC_JSON_UTILS_H
#define RAC_JSON_UTILS_H

#include "rac/server/rac_openai_types.h"
#include <nlohmann/json.hpp>
#include <string>

namespace rac {
namespace server {
namespace json {

using Json = nlohmann::json;

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

} // namespace json
} // namespace server
} // namespace rac

#endif // RAC_JSON_UTILS_H
