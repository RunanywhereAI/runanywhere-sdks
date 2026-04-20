// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

import org.json.JSONArray
import org.json.JSONObject

/**
 * Tool / function-calling helpers. Runs in Kotlin on top of ChatSession:
 * formats tool definitions into the system prompt, parses
 * <tool_call>{...}</tool_call> blocks out of generated text.
 */

data class ToolParameter(
    val name: String,
    val type: String,
    val description: String,
    val required: Boolean = true,
)

data class ToolDefinition(
    val name: String,
    val description: String,
    val parameters: List<ToolParameter>,
)

data class ToolCall(val name: String, val arguments: Map<String, Any?>)

object ToolFormatter {

    fun systemPrompt(tools: List<ToolDefinition>): String {
        if (tools.isEmpty()) return ""
        val sb = StringBuilder("You have access to the following tools:\n\n")
        for (t in tools) {
            sb.append("${t.name}: ${t.description}\nArguments:\n{\n")
            for (p in t.parameters) {
                val req = if (p.required) "" else " (optional)"
                sb.append("    \"${p.name}\": <${p.type}>  // ${p.description}$req\n")
            }
            sb.append("}\n\n")
        }
        sb.append("""

            To invoke a tool, reply with EXACTLY:
            <tool_call>{"name":"<tool_name>","arguments":{<args_json>}}</tool_call>

            Only output the tool call and nothing else when you use a tool.
        """.trimIndent())
        return sb.toString()
    }

    fun parseToolCalls(text: String): List<ToolCall> {
        val calls = mutableListOf<ToolCall>()
        val pattern = Regex("<tool_call>(.*?)</tool_call>", RegexOption.DOT_MATCHES_ALL)
        for (match in pattern.findAll(text)) {
            val json = match.groupValues[1].trim()
            try {
                val obj = JSONObject(json)
                val name = obj.optString("name")
                val args = obj.optJSONObject("arguments") ?: continue
                calls.add(ToolCall(name, jsonToMap(args)))
            } catch (_: Exception) { /* skip malformed */ }
        }
        return calls
    }

    private fun jsonToMap(obj: JSONObject): Map<String, Any?> =
        obj.keys().asSequence().associateWith { key ->
            when (val v = obj.get(key)) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(v)
                is JSONArray -> (0 until v.length()).map { v.get(it) }
                else -> v
            }
        }
}

/**
 * High-level agent: send user messages, get either an assistant response
 * or a list of pending tool calls. Caller executes tools and passes
 * results back via `continueAfter(toolResults)`.
 */
class ToolCallingAgent(
    modelId: String,
    modelPath: String,
    private val tools: List<ToolDefinition>,
    systemPrompt: String = "",
) {
    private val chat: ChatSession
    private val history = mutableListOf<ChatMessage>()

    init {
        val toolPrompt = ToolFormatter.systemPrompt(tools)
        val combined = listOf(systemPrompt, toolPrompt)
            .filter { it.isNotEmpty() }
            .joinToString("\n\n")
        chat = ChatSession(modelId, modelPath, combined)
    }

    sealed interface Reply {
        data class Assistant(val text: String) : Reply
        data class ToolCalls(val calls: List<ToolCall>) : Reply
    }

    suspend fun send(userMessage: String): Reply {
        history.add(ChatMessage.user(userMessage))
        val response = chat.generateText(history)
        history.add(ChatMessage.assistant(response))
        val calls = ToolFormatter.parseToolCalls(response)
        return if (calls.isNotEmpty()) Reply.ToolCalls(calls)
               else Reply.Assistant(response)
    }

    suspend fun continueAfter(toolResults: List<Pair<String, String>>): Reply {
        val blob = toolResults.joinToString("\n\n") { (name, result) ->
            "Tool `$name` returned:\n$result"
        }
        history.add(ChatMessage.tool(blob))
        val response = chat.generateText(history)
        history.add(ChatMessage.assistant(response))
        val calls = ToolFormatter.parseToolCalls(response)
        return if (calls.isNotEmpty()) Reply.ToolCalls(calls)
               else Reply.Assistant(response)
    }

    fun resetHistory() {
        history.clear()
        chat.resetHistory()
    }

    fun close() = chat.close()
}
