package com.runanywhere.agent.toolcalling

enum class ToolParameterType {
    STRING, INTEGER, NUMBER, BOOLEAN
}

data class ToolParameter(
    val name: String,
    val type: ToolParameterType,
    val description: String,
    val required: Boolean = true,
    val enumValues: List<String>? = null
)

data class ToolDefinition(
    val name: String,
    val description: String,
    val parameters: List<ToolParameter>
)

data class ToolCall(
    val id: String,
    val toolName: String,
    val arguments: Map<String, Any?>
)

data class ToolResult(
    val toolCallId: String,
    val toolName: String,
    val result: String,
    val isError: Boolean = false
)

sealed class LLMResponse {
    data class UIAction(val json: String) : LLMResponse()
    data class UIActionToolCall(val call: ToolCall) : LLMResponse()
    data class ToolCalls(val calls: List<ToolCall>) : LLMResponse()
    data class TextAnswer(val text: String) : LLMResponse()
    data class Error(val message: String) : LLMResponse()
}
