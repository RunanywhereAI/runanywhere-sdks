package com.runanywhere.sdk.public.toolcalling

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.Tool
import kotlinx.serialization.json.*

/**
 * Parses LLM responses to extract tool calls.
 * Handles various edge cases and invalid formats gracefully.
 *
 * This parser tries multiple strategies to extract JSON from the response:
 * 1. Direct JSON parse
 * 2. Extract from markdown code blocks (```json ... ```)
 * 3. Find JSON object embedded in text
 */
class ResponseParser {
    private val logger = SDKLogger("ResponseParser")
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Parse response into either a tool call or regular text.
     *
     * @param response The LLM's response text
     * @param availableTools List of tools to validate against
     * @return ParseResult indicating what type of response was received
     */
    fun parseResponse(
        response: String,
        availableTools: List<Tool>
    ): ParseResult {
        logger.debug("Parsing response: ${response.take(200)}...")

        // Strategy 1: Try direct JSON parse
        val directJson = tryParseJson(response.trim())
        if (directJson != null) {
            return validateAndCreateToolCall(directJson, availableTools)
        }

        // Strategy 2: Extract from markdown code block
        val codeBlockJson = extractFromCodeBlock(response)
        if (codeBlockJson != null) {
            return validateAndCreateToolCall(codeBlockJson, availableTools)
        }

        // Strategy 3: Find JSON object in text
        val embeddedJson = extractJsonFromText(response)
        if (embeddedJson != null) {
            return validateAndCreateToolCall(embeddedJson, availableTools)
        }

        // No valid JSON found - treat as regular chat response
        logger.debug("No valid tool call JSON found, treating as regular text")
        return ParseResult.RegularResponse(response)
    }

    /**
     * Try parsing string as JSON.
     */
    private fun tryParseJson(text: String): JsonObject? {
        return try {
            json.parseToJsonElement(text).jsonObject
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Extract JSON from markdown code blocks: ```json {...} ``` or ``` {...} ```
     */
    private fun extractFromCodeBlock(response: String): JsonObject? {
        val patterns = listOf(
            "```json\\s*(.+?)\\s*```",  // ```json ... ```
            "```\\s*(.+?)\\s*```"        // ``` ... ```
        )

        for (pattern in patterns) {
            val regex = Regex(pattern, RegexOption.DOT_MATCHES_ALL)
            val match = regex.find(response)
            if (match != null) {
                val json = tryParseJson(match.groupValues[1].trim())
                if (json != null) return json
            }
        }

        return null
    }

    /**
     * Find JSON object anywhere in text by looking for { ... } pattern.
     */
    private fun extractJsonFromText(response: String): JsonObject? {
        val startIdx = response.indexOf('{')
        val endIdx = response.lastIndexOf('}')

        if (startIdx == -1 || endIdx <= startIdx) {
            return null
        }

        return tryParseJson(response.substring(startIdx, endIdx + 1))
    }

    /**
     * Validate JSON has correct structure and tool exists.
     */
    private fun validateAndCreateToolCall(
        jsonObject: JsonObject,
        availableTools: List<Tool>
    ): ParseResult {
        // Validate required keys
        val name = jsonObject["name"]?.jsonPrimitive?.contentOrNull
        val argumentsElement = jsonObject["arguments"]

        if (name == null || argumentsElement == null) {
            logger.warn("Invalid tool call format - missing 'name' or 'arguments'")
            return ParseResult.InvalidFormat(
                reason = "Missing required keys: name and/or arguments",
                rawResponse = jsonObject.toString()
            )
        }

        // Arguments can be either an object or null (for tools with no parameters)
        val arguments = when (argumentsElement) {
            is JsonObject -> argumentsElement
            is JsonNull -> JsonObject(emptyMap())
            else -> {
                logger.warn("Invalid arguments type: ${argumentsElement::class.simpleName}")
                return ParseResult.InvalidFormat(
                    reason = "Arguments must be an object",
                    rawResponse = jsonObject.toString()
                )
            }
        }

        // Find matching tool
        val tool = availableTools.find { it.name == name }
        if (tool == null) {
            logger.warn("Unknown tool: $name")
            return ParseResult.UnknownTool(
                attemptedName = name,
                availableTools = availableTools.map { it.name }
            )
        }

        // Validate arguments against schema
        val validation = validateArguments(tool, arguments)
        if (!validation.valid) {
            logger.warn("Invalid arguments: ${validation.reason}")
            return ParseResult.InvalidArguments(
                toolName = name,
                reason = validation.reason ?: "Unknown validation error",
                providedArgs = arguments
            )
        }

        logger.info("✅ Valid tool call parsed: $name")
        return ParseResult.ToolCall(
            name = name,
            arguments = convertJsonObjectToMap(arguments)
        )
    }

    /**
     * Validate arguments match tool parameter schema.
     */
    private fun validateArguments(
        tool: Tool,
        arguments: JsonObject
    ): ValidationResult {
        val providedParams = arguments.keys
        val requiredParams = tool.parameters.required
        val allParams = tool.parameters.properties.keys

        // Check all required parameters are provided
        for (requiredParam in requiredParams) {
            if (!providedParams.contains(requiredParam)) {
                return ValidationResult(
                    valid = false,
                    reason = "Missing required parameter: $requiredParam"
                )
            }
        }

        // Check no hallucinated parameters
        for (providedParam in providedParams) {
            if (!allParams.contains(providedParam)) {
                return ValidationResult(
                    valid = false,
                    reason = "Unknown parameter: $providedParam (not in tool schema)"
                )
            }
        }

        return ValidationResult(valid = true)
    }

    /**
     * Convert JsonObject to Map<String, String> for compatibility with ToolCall data class.
     */
    private fun convertJsonObjectToMap(jsonObject: JsonObject): Map<String, String> {
        return jsonObject.entries.associate { (key, value) ->
            key to when (value) {
                is JsonPrimitive -> value.contentOrNull ?: value.toString()
                else -> value.toString()
            }
        }
    }

    private data class ValidationResult(
        val valid: Boolean,
        val reason: String? = null
    )
}

/**
 * Result of parsing LLM response.
 */
sealed class ParseResult {
    /**
     * Successfully parsed a valid tool call.
     */
    data class ToolCall(
        val name: String,
        val arguments: Map<String, String>
    ) : ParseResult()

    /**
     * Response was regular text (no tool call).
     */
    data class RegularResponse(
        val text: String
    ) : ParseResult()

    /**
     * JSON found but format is invalid (missing keys, wrong structure).
     */
    data class InvalidFormat(
        val reason: String,
        val rawResponse: String
    ) : ParseResult()

    /**
     * Tool name not in available tools list.
     */
    data class UnknownTool(
        val attemptedName: String,
        val availableTools: List<String>
    ) : ParseResult()

    /**
     * Arguments don't match tool schema (missing required, unknown params, etc.).
     */
    data class InvalidArguments(
        val toolName: String,
        val reason: String,
        val providedArgs: JsonObject
    ) : ParseResult()
}
