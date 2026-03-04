package com.runanywhere.agent.toolcalling

import android.util.Log

typealias ToolHandler = suspend (arguments: Map<String, Any?>) -> String

class ToolRegistry {
    companion object {
        private const val TAG = "ToolRegistry"
    }

    private val definitions = mutableMapOf<String, ToolDefinition>()
    private val handlers = mutableMapOf<String, ToolHandler>()

    fun register(definition: ToolDefinition, handler: ToolHandler) {
        definitions[definition.name] = definition
        handlers[definition.name] = handler
        Log.d(TAG, "Registered tool: ${definition.name}")
    }

    fun unregister(name: String) {
        definitions.remove(name)
        handlers.remove(name)
    }

    fun getDefinitions(): List<ToolDefinition> = definitions.values.toList()

    fun getDefinition(name: String): ToolDefinition? = definitions[name]

    fun hasHandler(name: String): Boolean = handlers.containsKey(name)

    fun isEmpty(): Boolean = definitions.isEmpty()

    suspend fun execute(call: ToolCall): ToolResult {
        val handler = handlers[call.toolName]
            ?: return ToolResult(
                toolCallId = call.id,
                toolName = call.toolName,
                result = "Error: Unknown tool '${call.toolName}'",
                isError = true
            )

        return try {
            val result = handler(call.arguments)
            ToolResult(
                toolCallId = call.id,
                toolName = call.toolName,
                result = result
            )
        } catch (e: Exception) {
            Log.e(TAG, "Tool execution failed: ${call.toolName}", e)
            ToolResult(
                toolCallId = call.id,
                toolName = call.toolName,
                result = "Error executing ${call.toolName}: ${e.message}",
                isError = true
            )
        }
    }
}
