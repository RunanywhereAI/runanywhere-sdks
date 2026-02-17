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

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.LLM.*
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
                argumentsJson = json["argumentsJson"]?.toString(),
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
                toolName = result.toolName,
                arguments = arguments,
                callId = "call_${result.callId}",
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
     * @param format Tool calling format type. See [ToolCallFormat].
     * @return Formatted system prompt string
     */
    fun formatToolsForPrompt(
        tools: List<ToolDefinition>,
        format: ToolCallFormat = ToolCallFormat.Default,
    ): String {
        if (tools.isEmpty()) return ""

        val toolsJson = serializeToolsToJson(tools)
        // Convert to string at JNI boundary - C++ handles the format logic
        val formatString = format.toFormatName()
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
    private fun parseArgumentsJson(json: String): Map<String, ToolValue> {
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
                    element.isString -> ToolValue.string(element.content)
                    element.booleanOrNull != null -> ToolValue.bool(element.boolean)
                    element.doubleOrNull != null -> ToolValue.number(element.double)
                    else -> ToolValue.string(element.content)
                }
            is JsonArray -> ToolValue.array(element.map { jsonElementToToolValue(it) })
            is JsonObject -> ToolValue.obj(element.mapValues { (_, v) -> jsonElementToToolValue(v) })
            JsonNull -> ToolValue.nullValue()
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
                                    put("type", param.type.value)
                                    put("description", param.description)
                                    put("required", param.required)
                                    param.enumValues?.let { values ->
                                        putJsonArray("enumValues") {
                                            values.forEach { add(it) }
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
                put("maxToolCalls", options.maxToolCalls)
                put("autoExecute", options.autoExecute)
                options.temperature?.let { put("temperature", it) }
                options.maxTokens?.let { put("maxTokens", it) }
                options.systemPrompt?.let { put("systemPrompt", it) }
                put("replaceSystemPrompt", options.replaceSystemPrompt)
                put("keepToolsAvailable", options.keepToolsAvailable)
                put("format", options.format.toFormatName()) // Convert to string at serialization boundary
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
        when (value) {
            is ToolValue.StringValue -> JsonPrimitive(value.value)
            is ToolValue.NumberValue -> JsonPrimitive(value.value)
            is ToolValue.BoolValue -> JsonPrimitive(value.value)
            is ToolValue.ArrayValue ->
                buildJsonArray {
                    value.value.forEach { add(toolValueToJsonElement(it)) }
                }
            is ToolValue.ObjectValue ->
                buildJsonObject {
                    value.value.forEach { (k, v) -> put(k, toolValueToJsonElement(v)) }
                }
            ToolValue.NullValue -> JsonNull
        }
}
