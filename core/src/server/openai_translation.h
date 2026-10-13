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

namespace runanywhere::v1 {
class LLMGenerateRequest;
}

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
std::string buildPromptFromOpenAI(const Json& messages, const Json& tools,
                                  const Json& toolChoice = "auto");

/** Convert one validated OpenAI request to the canonical generation envelope. */
runanywhere::v1::LLMGenerateRequest buildGenerateRequest(const Json& request,
                                                         const std::string& modelId);

/**
 * @brief Generate a unique tool call ID
 *
 * Format: "call_" + random hex string
 */
std::string generateToolCallId();

// =============================================================================
// Message Formatting
// =============================================================================

/** Extract string or text-part content after request validation. */
std::string messageText(const Json& message);

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
