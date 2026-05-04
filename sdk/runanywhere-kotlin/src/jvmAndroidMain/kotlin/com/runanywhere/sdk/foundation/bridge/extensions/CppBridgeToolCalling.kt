/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * C++ bridge for tool calling functionality.
 *
 * *** SINGLE SOURCE OF TRUTH FOR TOOL CALLING LOGIC ***
 * All parsing and prompt formatting is done in C++ (rac_tool_calling.h).
 * This bridge is a THIN WRAPPER - no parsing logic in Kotlin.
 *
 * Platform SDKs handle ONLY:
 * - Tool registry (Kotlin closures)
 * - Tool execution (Kotlin async calls)
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ToolParameterType
import ai.runanywhere.proto.v1.ToolValueArray
import ai.runanywhere.proto.v1.ToolValueObject
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOptions
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolValue
import kotlinx.serialization.json.*

/**
 * Tool calling bridge to C++ implementation.
 *
 * *** ALL PARSING LOGIC IS IN C++ - NO KOTLIN FALLBACKS ***
 */
object CppBridgeToolCalling {
    private const val TAG = "CppBridgeToolCalling"
    private val logger = SDKLogger(TAG)

    /**
     * Parsed tool call result from C++
     */
    data class ParseResult(
        val hasToolCall: Boolean,
        val cleanText: String,
        val toolName: String?,
        val argumentsJson: String?,
        val callId: Long,
    )

    // ========================================================================
    // PARSE TOOL CALL (NO FALLBACK)
    // ========================================================================

    /**
     * Parse LLM output for tool calls using C++ implementation.
     *
     * *** THIS IS THE ONLY PARSING IMPLEMENTATION - NO KOTLIN FALLBACK ***
     *
     * @param llmOutput Raw LLM output text
     * @return Parsed result with tool call info
     */
    fun parseToolCall(llmOutput: String): ParseResult {
        val resultJson =
            RunAnywhereBridge.racToolCallParse(llmOutput)
                ?: return ParseResult(
                    hasToolCall = false,
                    cleanText = llmOutput,
                    toolName = null,
                    argumentsJson = null,
                    callId = 0,
                )

        return try {
            val json = Json.parseToJsonElement(resultJson).jsonObject
            ParseResult(
                hasToolCall = json["hasToolCall"]?.jsonPrimitive?.boolean ?: false,
                cleanText = json["cleanText"]?.jsonPrimitive?.content ?: llmOutput,
                toolName = json["toolName"]?.jsonPrimitive?.contentOrNull,
                argumentsJson =
                    json["argumentsJson"]?.let { args ->
                        if (args is JsonPrimitive && args.isString) args.content else args.toString()
                    },
                callId = json["callId"]?.jsonPrimitive?.longOrNull ?: 0,
            )
        } catch (e: Exception) {
            logger.error("Failed to parse tool call result: ${e.message}")
            ParseResult(
                hasToolCall = false,
                cleanText = llmOutput,
                toolName = null,
                argumentsJson = null,
                callId = 0,
            )
        }
    }

    /**
     * Parse LLM output and return a ToolCall object if found.
     *
     * @param llmOutput Raw LLM output text
     * @return Pair of (cleanText, toolCall) where toolCall is null if none found
     */
    fun parseToolCallToObject(llmOutput: String): Pair<String, ToolCall?> {
        val result = parseToolCall(llmOutput)

        if (!result.hasToolCall || result.toolName == null) {
            return Pair(result.cleanText, null)
        }

        val arguments = parseArgumentsJson(result.argumentsJson ?: "{}")

        return Pair(
            result.cleanText,
            ToolCall(
                id = "call_${result.callId}",
                name = result.toolName,
                arguments_json = toolValueToJsonString(arguments),
            ),
        )
    }

    // ========================================================================
    // FORMAT TOOLS FOR PROMPT (NO FALLBACK)
    // ========================================================================

    /**
     * Format tool definitions into a system prompt using C++ implementation.
     *
     * @param tools List of tool definitions
     * @param formatHint Tool calling format hint, e.g. "default" or "lfm2".
     * @return Formatted system prompt string
     */
    fun formatToolsForPrompt(
        tools: List<ToolDefinition>,
        formatHint: String = "",
    ): String {
        if (tools.isEmpty()) return ""

        val toolsJson = serializeToolsToJson(tools)
        val formatString = formatHint.ifBlank { "default" }
        return RunAnywhereBridge.racToolCallFormatPromptJsonWithFormatName(toolsJson, formatString) ?: ""
    }

    // ========================================================================
    // BUILD INITIAL PROMPT (NO FALLBACK)
    // ========================================================================

    /**
     * Build the initial prompt with tools and user query using C++ implementation.
     *
     * @param userPrompt The user's question/request
     * @param tools List of tool definitions
     * @param options Tool calling options
     * @return Complete formatted prompt
     */
    fun buildInitialPrompt(
        userPrompt: String,
        tools: List<ToolDefinition>,
        options: ToolCallingOptions,
    ): String {
        val toolsJson = serializeToolsToJson(tools)
        val optionsJson = serializeOptionsToJson(options)

        return RunAnywhereBridge.racToolCallBuildInitialPrompt(
            userPrompt,
            toolsJson,
            optionsJson,
        ) ?: userPrompt
    }

    // ========================================================================
    // BUILD FOLLOW-UP PROMPT (NO FALLBACK)
    // ========================================================================

    /**
     * Build follow-up prompt after tool execution using C++ implementation.
     *
     * @param originalPrompt The original user prompt
     * @param toolsPrompt The formatted tools prompt (null if not keeping tools)
     * @param toolName Name of the tool that was executed
     * @param toolResultJson JSON string of the tool result
     * @param keepToolsAvailable Whether to include tool definitions
     * @return Follow-up prompt string
     */
    fun buildFollowupPrompt(
        originalPrompt: String,
        toolsPrompt: String?,
        toolName: String,
        toolResultJson: String,
        keepToolsAvailable: Boolean,
    ): String {
        return RunAnywhereBridge.racToolCallBuildFollowupPrompt(
            originalPrompt,
            toolsPrompt,
            toolName,
            toolResultJson,
            keepToolsAvailable,
        ) ?: ""
    }

    // ========================================================================
    // JSON NORMALIZATION (NO FALLBACK)
    // ========================================================================

    /**
     * Normalize JSON by adding quotes around unquoted keys using C++ implementation.
     *
     * @param jsonStr Raw JSON string possibly with unquoted keys
     * @return Normalized JSON string with all keys quoted
     */
    fun normalizeJson(jsonStr: String): String {
        return RunAnywhereBridge.racToolCallNormalizeJson(jsonStr) ?: jsonStr
    }

    // ========================================================================
    // PRIVATE HELPERS
    // ========================================================================

    /**
     * Parse arguments JSON string to Map<String, ToolValue>
     */
    internal fun parseArgumentsJson(json: String): Map<String, ToolValue> {
        return try {
            val element = Json.parseToJsonElement(json)
            if (element is JsonObject) {
                element.mapValues { (_, v) -> jsonElementToToolValue(v) }
            } else {
                emptyMap()
            }
        } catch (e: Exception) {
            logger.error("Failed to parse arguments JSON: ${e.message}")
            emptyMap()
        }
    }

    /**
     * Convert JsonElement to ToolValue
     */
    private fun jsonElementToToolValue(element: JsonElement): ToolValue =
        when (element) {
            is JsonPrimitive ->
                when {
                    element.isString -> ToolValue(string_value = element.content)
                    element.booleanOrNull != null -> ToolValue(bool_value = element.boolean)
                    element.doubleOrNull != null -> ToolValue(number_value = element.double)
                    else -> ToolValue(string_value = element.content)
                }
            is JsonArray -> ToolValue(array_value = ToolValueArray(element.map { jsonElementToToolValue(it) }))
            is JsonObject -> ToolValue(object_value = ToolValueObject(element.mapValues { (_, v) -> jsonElementToToolValue(v) }))
            JsonNull -> ToolValue()
        }

    /**
     * Serialize tool definitions to JSON array string
     */
    private fun serializeToolsToJson(tools: List<ToolDefinition>): String {
        val jsonArray =
            buildJsonArray {
                tools.forEach { tool ->
                    addJsonObject {
                        put("name", tool.name)
                        put("description", tool.description)
                        putJsonArray("parameters") {
                            tool.parameters.forEach { param ->
                                addJsonObject {
                                    put("name", param.name)
                                    put("type", param.type.toJsonSchemaType())
                                    put("description", param.description)
                                    put("required", param.required)
                                    if (param.enum_values.isNotEmpty()) {
                                        putJsonArray("enumValues") {
                                            param.enum_values.forEach { add(it) }
                                        }
                                    }
                                }
                            }
                        }
                        tool.category?.let { put("category", it) }
                    }
                }
            }
        return jsonArray.toString()
    }

    /**
     * Serialize options to JSON string
     */
    private fun serializeOptionsToJson(options: ToolCallingOptions): String {
        val jsonObj =
            buildJsonObject {
                put("maxToolCalls", options.max_iterations)
                put("autoExecute", options.auto_execute)
                options.temperature?.let { put("temperature", it) }
                options.max_tokens?.let { put("maxTokens", it) }
                options.system_prompt?.let { put("systemPrompt", it) }
                put("replaceSystemPrompt", options.replace_system_prompt)
                put("keepToolsAvailable", options.keep_tools_available)
                put("format", options.format_hint.ifBlank { "default" })
            }
        return jsonObj.toString()
    }

    /**
     * Convert ToolValue to JSON string
     */
    fun toolValueToJsonString(value: Map<String, ToolValue>): String {
        val jsonObj =
            buildJsonObject {
                value.forEach { (k, v) ->
                    put(k, toolValueToJsonElement(v))
                }
            }
        return jsonObj.toString()
    }

    private fun toolValueToJsonElement(value: ToolValue): JsonElement =
        when {
            value.string_value != null -> JsonPrimitive(value.string_value)
            value.number_value != null -> JsonPrimitive(value.number_value)
            value.bool_value != null -> JsonPrimitive(value.bool_value)
            value.array_value != null ->
                buildJsonArray {
                    value.array_value.values.forEach { add(toolValueToJsonElement(it)) }
                }
            value.object_value != null ->
                buildJsonObject {
                    value.object_value.fields.forEach { (k, v) -> put(k, toolValueToJsonElement(v)) }
                }
            else -> JsonNull
        }

    private fun ToolParameterType.toJsonSchemaType(): String =
        when (this) {
            ToolParameterType.TOOL_PARAMETER_TYPE_STRING -> "string"
            ToolParameterType.TOOL_PARAMETER_TYPE_NUMBER -> "number"
            ToolParameterType.TOOL_PARAMETER_TYPE_BOOLEAN -> "boolean"
            ToolParameterType.TOOL_PARAMETER_TYPE_OBJECT -> "object"
            ToolParameterType.TOOL_PARAMETER_TYPE_ARRAY -> "array"
            else -> "string"
        }
}
