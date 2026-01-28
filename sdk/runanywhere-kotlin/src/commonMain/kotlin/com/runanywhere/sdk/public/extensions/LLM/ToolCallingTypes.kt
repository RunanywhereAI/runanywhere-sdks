/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Type definitions for Tool Calling functionality.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * Mirrors Swift SDK's ToolCallingTypes.swift
 */

package com.runanywhere.sdk.public.extensions.LLM

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

// =============================================================================
// TOOL VALUE - Type-safe JSON representation
// =============================================================================

/**
 * A type-safe representation of JSON values for tool arguments and results.
 * Avoids using `Any` while supporting all JSON types.
 */
@Serializable
sealed class ToolValue {
    @Serializable
    data class StringValue(val value: String) : ToolValue()
    
    @Serializable
    data class NumberValue(val value: Double) : ToolValue()
    
    @Serializable
    data class BoolValue(val value: Boolean) : ToolValue()
    
    @Serializable
    data class ArrayValue(val value: List<ToolValue>) : ToolValue()
    
    @Serializable
    data class ObjectValue(val value: Map<String, ToolValue>) : ToolValue()
    
    @Serializable
    object NullValue : ToolValue()
    
    // Convenience value extraction
    val stringValue: String? get() = (this as? StringValue)?.value
    val numberValue: Double? get() = (this as? NumberValue)?.value
    val intValue: Int? get() = numberValue?.toInt()
    val boolValue: Boolean? get() = (this as? BoolValue)?.value
    val arrayValue: List<ToolValue>? get() = (this as? ArrayValue)?.value
    val objectValue: Map<String, ToolValue>? get() = (this as? ObjectValue)?.value
    val isNull: Boolean get() = this is NullValue
    
    companion object {
        fun string(value: String) = StringValue(value)
        fun number(value: Double) = NumberValue(value)
        fun number(value: Int) = NumberValue(value.toDouble())
        fun bool(value: Boolean) = BoolValue(value)
        fun array(value: List<ToolValue>) = ArrayValue(value)
        fun obj(value: Map<String, ToolValue>) = ObjectValue(value)
        fun nullValue() = NullValue
        
        /**
         * Convert Any to ToolValue
         */
        fun from(value: Any?): ToolValue = when (value) {
            null -> NullValue
            is String -> StringValue(value)
            is Number -> NumberValue(value.toDouble())
            is Boolean -> BoolValue(value)
            is List<*> -> ArrayValue(value.map { from(it) })
            is Map<*, *> -> ObjectValue(value.entries.associate { (k, v) -> 
                k.toString() to from(v)
            })
            else -> StringValue(value.toString())
        }
    }
}

// =============================================================================
// PARAMETER TYPES
// =============================================================================

/**
 * Supported parameter types for tool arguments
 */
enum class ToolParameterType(val value: String) {
    STRING("string"),
    NUMBER("number"),
    BOOLEAN("boolean"),
    OBJECT("object"),
    ARRAY("array");
    
    companion object {
        fun fromString(value: String): ToolParameterType = when (value.lowercase()) {
            "string" -> STRING
            "number" -> NUMBER
            "boolean" -> BOOLEAN
            "object" -> OBJECT
            "array" -> ARRAY
            else -> STRING
        }
    }
}

/**
 * A single parameter definition for a tool
 */
data class ToolParameter(
    /** Parameter name */
    val name: String,
    /** Data type of the parameter */
    val type: ToolParameterType,
    /** Human-readable description */
    val description: String,
    /** Whether this parameter is required */
    val required: Boolean = true,
    /** Allowed values (for enum-like parameters) */
    val enumValues: List<String>? = null
)

// =============================================================================
// TOOL DEFINITION TYPES
// =============================================================================

/**
 * Definition of a tool that the LLM can use
 */
data class ToolDefinition(
    /** Unique name of the tool (e.g., "get_weather") */
    val name: String,
    /** Human-readable description of what the tool does */
    val description: String,
    /** Parameters the tool accepts */
    val parameters: List<ToolParameter>,
    /** Category for organizing tools (optional) */
    val category: String? = null
)

// =============================================================================
// TOOL CALL TYPES (LLM requesting to use a tool)
// =============================================================================

/**
 * A request from the LLM to execute a tool
 */
data class ToolCall(
    /** Name of the tool to execute */
    val toolName: String,
    /** Arguments to pass to the tool */
    val arguments: Map<String, ToolValue>,
    /** Unique ID for this tool call (for tracking) */
    val callId: String? = null
) {
    /** Get a string argument by name */
    fun getString(key: String): String? = arguments[key]?.stringValue
    
    /** Get a number argument by name */
    fun getNumber(key: String): Double? = arguments[key]?.numberValue
    
    /** Get a bool argument by name */
    fun getBool(key: String): Boolean? = arguments[key]?.boolValue
}

// =============================================================================
// TOOL RESULT TYPES (Result after execution)
// =============================================================================

/**
 * Result of executing a tool
 */
data class ToolResult(
    /** Name of the tool that was executed */
    val toolName: String,
    /** Whether execution was successful */
    val success: Boolean,
    /** Result data (if successful) */
    val result: Map<String, ToolValue>? = null,
    /** Error message (if failed) */
    val error: String? = null,
    /** The original call ID (for tracking) */
    val callId: String? = null
)

// =============================================================================
// TOOL EXECUTOR TYPES
// =============================================================================

/**
 * Function type for tool executors.
 * Takes arguments as strongly-typed ToolValue map, returns result map.
 */
typealias ToolExecutor = suspend (Map<String, ToolValue>) -> Map<String, ToolValue>

/**
 * A registered tool with its definition and executor
 */
internal data class RegisteredTool(
    val definition: ToolDefinition,
    val executor: ToolExecutor
)

// =============================================================================
// TOOL CALL FORMAT NAMES
// =============================================================================

/**
 * Format names for tool calling output.
 * Different LLM models expect different formats for tool calls.
 *
 * The format logic is handled in C++ commons (single source of truth).
 */
object ToolCallFormatName {
    /** JSON format: `<tool_call>{"tool":"name","arguments":{...}}</tool_call>`
     * Use for most general-purpose models (Llama, Qwen, Mistral, etc.) */
    const val DEFAULT = "default"
    
    /** Liquid AI format: `<|tool_call_start|>[func(args)]<|tool_call_end|>`
     * Use for LFM2-Tool models */
    const val LFM2 = "lfm2"
}

// =============================================================================
// TOOL CALLING OPTIONS
// =============================================================================

/**
 * Options for tool-enabled generation
 */
data class ToolCallingOptions(
    /** Available tools for this generation (if not provided, uses registered tools) */
    val tools: List<ToolDefinition>? = null,
    /** Maximum number of tool calls allowed in one conversation turn (default: 5) */
    val maxToolCalls: Int = 5,
    /** Whether to automatically execute tools or return them for manual execution (default: true) */
    val autoExecute: Boolean = true,
    /** Temperature for generation */
    val temperature: Float? = null,
    /** Maximum tokens to generate */
    val maxTokens: Int? = null,
    /** System prompt to use (will be merged with tool instructions by default) */
    val systemPrompt: String? = null,
    /** If true, replaces the system prompt entirely instead of appending tool instructions */
    val replaceSystemPrompt: Boolean = false,
    /** If true, keeps tool definitions available after the first tool call */
    val keepToolsAvailable: Boolean = false,
    /**
     * Format for tool calls. Use "lfm2" for LFM2-Tool models (Liquid AI).
     * Default: "default" which uses JSON-based format suitable for most models.
     * Valid values: "auto", "default", "lfm2", "openai"
     * See [ToolCallFormatName] for constants.
     */
    val format: String = ToolCallFormatName.DEFAULT
)

// =============================================================================
// TOOL CALLING RESULT TYPES
// =============================================================================

/**
 * Result of a generation that may include tool calls
 */
data class ToolCallingResult(
    /** The final text response */
    val text: String,
    /** Any tool calls the LLM made */
    val toolCalls: List<ToolCall>,
    /** Results of executed tools (if autoExecute was true) */
    val toolResults: List<ToolResult>,
    /** Whether the response is complete or waiting for tool results */
    val isComplete: Boolean,
    /** Conversation ID for continuing with tool results */
    val conversationId: String? = null
)
