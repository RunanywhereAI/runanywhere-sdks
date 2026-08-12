/**
 * @file openai_translation.h
 * @brief Translation layer between OpenAI API format and Commons format
 *
 * This provides conversion between OpenAI request JSON and the generated
 * tool-calling protobuf contract consumed by commons.
 *
 * The translation happens at the API boundary, keeping Commons
 * focused on model interaction and the server on API compliance.
 */

#ifndef RAC_OPENAI_TRANSLATION_H
#define RAC_OPENAI_TRANSLATION_H

#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace rac {
namespace server {
namespace translation {

using Json = nlohmann::json;

// =============================================================================
// OpenAI REQUEST -> Commons Format
// =============================================================================

/**
 * @brief Build a prompt from OpenAI messages and tools
 *
 * Uses rac_tool_call_format_prompt_proto for prompts with tools and simple
 * concatenation for prompts without tools.
 *
 * @param messages OpenAI messages array
 * @param tools OpenAI tools array (can be empty)
 * @return Formatted prompt string for LLM
 */
std::string buildPromptFromOpenAI(const Json& messages, const Json& tools);

/**
 * @brief Generate a unique tool call ID
 *
 * Format: "call_" + random hex string
 */
std::string generateToolCallId();

// =============================================================================
// Message Formatting
// =============================================================================

/**
 * @brief Extract the last user message from OpenAI messages
 *
 * @param messages OpenAI messages array
 * @return Last user message content, or empty string if none
 */
std::string extractLastUserMessage(const Json& messages);

/**
 * @brief Build a simple prompt from messages (no tools)
 *
 * Formats messages into a conversation format suitable for the LLM.
 *
 * @param messages OpenAI messages array
 * @return Formatted prompt string
 */
std::string buildSimplePrompt(const Json& messages);

}  // namespace translation
}  // namespace server
}  // namespace rac

#endif  // RAC_OPENAI_TRANSLATION_H
