package com.runanywhere.sdk.public.toolcalling

import com.runanywhere.sdk.models.Tool
import com.runanywhere.sdk.models.ToolParameter
import kotlinx.serialization.json.Json

/**
 * Builds prompts for tool calling using few-shot learning.
 *
 * This approach uses carefully crafted system prompts with examples to guide
 * the LLM to generate valid JSON for tool calls, rather than using grammar constraints.
 */
class PromptBuilder {

    /**
     * Build a system prompt that instructs the model how to use tools.
     *
     * @param tools List of available tools
     * @return System prompt string with tool definitions and examples
     */
    fun buildSystemPrompt(tools: List<Tool>): String {
        return """
        |You are a program which picks the most optimal function and parameters to call.
        |
        |IMPORTANT RULES:
        |1. You DO NOT HAVE TO pick a function if it will not help answer the user's query.
        |2. When a function is selected, respond with ONLY JSON - no additional text.
        |3. When there is no relevant function, respond with a regular chat message.
        |4. Pick a **single** function that best helps with the user query.
        |
        |JSON RESPONSE FORMAT:
        |All JSON responses must have exactly these two keys:
        |{
        |  "name": "function_name",
        |  "arguments": {
        |    "param1": "value1",
        |    "param2": "value2"
        |  }
        |}
        |
        |DO NOT INCLUDE ANY OTHER KEYS OR TEXT IN JSON RESPONSES.
        |
        |AVAILABLE TOOLS:
        |${showcaseTools(tools)}
        |
        |Now analyze the user's message and pick the most appropriate function if needed.
        """.trimMargin()
    }

    /**
     * Format tools with their parameters and examples.
     * Examples are critical for small models to understand the expected format.
     */
    private fun showcaseTools(tools: List<Tool>): String {
        return tools.joinToString("\n\n") { tool ->
            val examplesSection = if (tool.examples.isNotEmpty()) {
                "\nEXAMPLES:\n" + tool.examples.joinToString("\n") { example ->
                    """
                    |User Query: "${example.userQuery}"
                    |JSON Response: ${formatExampleCall(tool.name, example.arguments)}
                    """.trimMargin()
                }
            } else ""

            """
            |-----------
            |Function: ${tool.name}
            |Description: ${tool.description}
            |Parameters:
            |${formatParameters(tool.parameters.properties.entries.toList())}
            |$examplesSection
            |-----------
            """.trimMargin()
        }
    }

    /**
     * Format parameter definitions in a readable way.
     */
    private fun formatParameters(parameters: List<Map.Entry<String, ToolParameter>>): String {
        return parameters.joinToString("\n") { (name, param) ->
            val requiredLabel = if (param.required) "(required)" else "(optional)"
            "  - $name: ${param.type.toJsonSchemaType()} $requiredLabel - ${param.description}"
        }
    }

    /**
     * Format an example tool call as JSON string.
     */
    private fun formatExampleCall(toolName: String, arguments: Map<String, String>): String {
        // Manual JSON formatting for simple cases
        val argsJson = arguments.entries.joinToString(", ") { (key, value) ->
            """"$key": "$value""""
        }
        return """{"name": "$toolName", "arguments": {$argsJson}}"""
    }
}
