package com.runanywhere.agent.toolcalling

import org.json.JSONArray
import org.json.JSONObject

object ToolPromptFormatter {

    /**
     * Format tools for injection into local model system prompts (verbose version).
     */
    fun formatForLocalPrompt(tools: List<ToolDefinition>): String {
        if (tools.isEmpty()) return ""

        val sb = StringBuilder()
        sb.appendLine()
        sb.appendLine()
        sb.appendLine("AVAILABLE TOOLS:")
        sb.appendLine("You can call tools by wrapping a JSON object in <tool_call> tags.")
        sb.appendLine("Format: <tool_call>{\"tool\":\"tool_name\",\"arguments\":{\"param\":\"value\"}}</tool_call>")
        sb.appendLine()

        tools.forEach { tool ->
            sb.appendLine("- ${tool.name}: ${tool.description}")
            if (tool.parameters.isNotEmpty()) {
                sb.append("  Parameters: ")
                sb.appendLine(tool.parameters.joinToString(", ") { p ->
                    val req = if (p.required) "required" else "optional"
                    "${p.name} (${p.type.name.lowercase()}, $req): ${p.description}"
                })
            }
        }

        sb.appendLine()
        sb.appendLine("RULES:")
        sb.appendLine("- If you need factual information (time, weather, calculations), USE a tool call.")
        sb.appendLine("- Only call ONE tool at a time. Wait for the result before proceeding.")
        sb.appendLine("- After receiving tool results, decide your next action: another tool call, a UI action, or \"done\".")
        sb.appendLine("- For UI navigation tasks, use UI actions (tap, type, swipe) NOT tool calls.")
        return sb.toString()
    }

    /**
     * Ultra-compact tool format for on-device 1.2B models.
     * Minimizes token usage (~80 tokens total for 8 tools).
     */
    fun formatCompactForLocal(tools: List<ToolDefinition>): String {
        if (tools.isEmpty()) return ""

        val sb = StringBuilder()
        sb.appendLine("TOOLS (call ONE per turn):")
        sb.appendLine("Format: <tool_call>{\"tool\":\"name\",\"arguments\":{...}}</tool_call>")

        tools.forEach { tool ->
            val params = if (tool.parameters.isNotEmpty()) {
                tool.parameters.joinToString(",") { p ->
                    val typeStr = p.type.name.lowercase().take(3)
                    "${p.name}:$typeStr"
                }
                    .let { "($it)" }
            } else {
                "()"
            }
            // One-liner: tool_name(params) — short description
            val shortDesc = tool.description.take(50)
            sb.appendLine("- ${tool.name}$params — $shortDesc")
        }

        return sb.toString()
    }

    /**
     * Format tool results for re-injection into the prompt.
     */
    fun formatToolResults(results: List<ToolResult>): String {
        val sb = StringBuilder()
        sb.appendLine()
        sb.appendLine("TOOL RESULTS:")
        results.forEach { result ->
            val status = if (result.isError) "ERROR" else "OK"
            sb.appendLine("[${result.toolName}] ($status): ${result.result}")
        }
        sb.appendLine()
        sb.appendLine("Based on the tool results above, decide your next action.")
        return sb.toString()
    }

    /**
     * Convert tool definitions to OpenAI function calling format.
     * Returns a JSONArray for the "tools" parameter in the API request.
     */
    fun toOpenAIFormat(tools: List<ToolDefinition>): JSONArray {
        val array = JSONArray()
        tools.forEach { tool ->
            val properties = JSONObject()
            val required = JSONArray()

            tool.parameters.forEach { param ->
                val paramObj = JSONObject().apply {
                    put("type", when (param.type) {
                        ToolParameterType.STRING -> "string"
                        ToolParameterType.INTEGER -> "integer"
                        ToolParameterType.NUMBER -> "number"
                        ToolParameterType.BOOLEAN -> "boolean"
                    })
                    put("description", param.description)
                    param.enumValues?.let { vals ->
                        put("enum", JSONArray(vals))
                    }
                }
                properties.put(param.name, paramObj)
                if (param.required) {
                    required.put(param.name)
                }
            }

            val functionObj = JSONObject().apply {
                put("name", tool.name)
                put("description", tool.description)
                put("parameters", JSONObject().apply {
                    put("type", "object")
                    put("properties", properties)
                    put("required", required)
                })
            }

            array.put(JSONObject().apply {
                put("type", "function")
                put("function", functionObj)
            })
        }
        return array
    }
}
