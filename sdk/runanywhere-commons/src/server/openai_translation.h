/**
 * @file openai_translation.h
 * @brief Translation layer between OpenAI API format and Commons format
 *
 * This provides conversion between:
 * - OpenAI API request format (tools, messages)
 * - Commons internal format (rac_tool_definition_t, rac_tool_call_t)
 *
 * The translation happens at the API boundary, keeping Commons
 * focused on model interaction and the server on API compliance.
 */

#ifndef RAC_OPENAI_TRANSLATION_H
#define RAC_OPENAI_TRANSLATION_H

#include "rac/features/llm/rac_tool_calling.h"
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
 * @brief Convert OpenAI tools array to Commons JSON format
 *
 * OpenAI format:
 * [{"type": "function", "function": {"name": "...", "parameters": {...}}}]
 *
 * Commons format (for rac_tool_call_format_prompt_json):
 * [{"name": "...", "description": "...", "parameters": [...]}]
 *
 * @param openaiTools OpenAI tools array
 * @return Commons-compatible tools JSON string
 */
std::string openaiToolsToCommonsJson(const Json& openaiTools);

/**
 * @brief Build a prompt from OpenAI messages and tools
 *
 * Uses Commons APIs to build the prompt:
 * - rac_tool_call_build_initial_prompt() for prompts with tools
 * - Simple concatenation for prompts without tools
 *
 * @param messages OpenAI messages array
 * @param tools OpenAI tools array (can be empty)
 * @param options Tool calling options (can be nullptr)
 * @return Formatted prompt string for LLM
 */
std::string buildPromptFromOpenAI(const Json& messages,
                                   const Json& tools,
                                   const rac_tool_calling_options_t* options = nullptr);

// =============================================================================
// Commons Format -> OpenAI RESPONSE
// =============================================================================

/**
 * @brief Convert Commons tool call to OpenAI response format
 *
 * Commons format (from rac_tool_call_parse):
 * { tool_name, arguments_json, clean_text }
 *
 * OpenAI format:
 * {"tool_calls": [{"id": "call_...", "type": "function", "function": {...}}]}
 *
 * @param toolCall Parsed tool call from Commons
 * @return OpenAI-formatted tool_calls array (empty if no tool call)
 */
Json commonsToolCallToOpenAI(const rac_tool_call_t& toolCall);

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

} // namespace translation
} // namespace server
} // namespace rac

#endif // RAC_OPENAI_TRANSLATION_H
