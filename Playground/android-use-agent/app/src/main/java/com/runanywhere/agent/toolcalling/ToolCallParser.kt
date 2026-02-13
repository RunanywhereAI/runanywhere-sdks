package com.runanywhere.agent.toolcalling

import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID
import java.util.regex.Pattern

object ToolCallParser {
    private const val TAG = "ToolCallParser"

    private val TOOL_CALL_PATTERN = Pattern.compile(
        "<tool_call>(.*?)</tool_call>",
        Pattern.DOTALL
    )

    private val UNCLOSED_TOOL_CALL_PATTERN = Pattern.compile(
        "<tool_call>(\\{.*)",
        Pattern.DOTALL
    )

    private val INLINE_TOOL_CALL_PATTERN = Pattern.compile(
        "\\{\\s*\"tool_call\"\\s*:\\s*(\\{.*?\\})\\s*\\}",
        Pattern.DOTALL
    )

    fun parse(rawOutput: String): List<ToolCall> {
        val calls = mutableListOf<ToolCall>()

        // Try primary <tool_call>...</tool_call> tags
        val matcher = TOOL_CALL_PATTERN.matcher(rawOutput)
        while (matcher.find()) {
            val inner = matcher.group(1)?.trim() ?: continue
            parseToolCallJson(inner)?.let { calls.add(it) }
        }
        if (calls.isNotEmpty()) return calls

        // Try unclosed tag (model ran out of tokens)
        val unclosedMatcher = UNCLOSED_TOOL_CALL_PATTERN.matcher(rawOutput)
        if (unclosedMatcher.find()) {
            val inner = unclosedMatcher.group(1)?.trim() ?: ""
            val balanced = balanceBraces(inner)
            parseToolCallJson(balanced)?.let { calls.add(it) }
        }
        if (calls.isNotEmpty()) return calls

        // Try inline format {"tool_call": {...}}
        val inlineMatcher = INLINE_TOOL_CALL_PATTERN.matcher(rawOutput)
        if (inlineMatcher.find()) {
            val inner = inlineMatcher.group(1)?.trim() ?: ""
            parseToolCallJson(inner)?.let { calls.add(it) }
        }

        return calls
    }

    fun containsToolCall(rawOutput: String): Boolean {
        return rawOutput.contains("<tool_call>") ||
                rawOutput.contains("\"tool_call\"") ||
                TOOL_CALL_PATTERN.matcher(rawOutput).find()
    }

    fun extractCleanText(rawOutput: String): String {
        var text = rawOutput
        // Remove all <tool_call>...</tool_call> blocks
        text = TOOL_CALL_PATTERN.matcher(text).replaceAll("")
        // Remove unclosed <tool_call> to end
        text = text.replace(Regex("<tool_call>.*", RegexOption.DOT_MATCHES_ALL), "")
        return text.trim()
    }

    private fun parseToolCallJson(jsonStr: String): ToolCall? {
        val cleaned = fixMalformedJson(jsonStr)

        return try {
            val obj = JSONObject(cleaned)

            val toolName = obj.optString("tool", "").ifEmpty {
                obj.optString("name", "").ifEmpty {
                    obj.optString("function", "")
                }
            }
            if (toolName.isEmpty()) return null

            val argsObj = obj.optJSONObject("arguments")
                ?: obj.optJSONObject("args")
                ?: obj.optJSONObject("parameters")
                ?: JSONObject()

            val arguments = mutableMapOf<String, Any?>()
            val keys = argsObj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                arguments[key] = argsObj.opt(key)
            }

            ToolCall(
                id = UUID.randomUUID().toString(),
                toolName = toolName,
                arguments = arguments
            )
        } catch (e: JSONException) {
            Log.w(TAG, "Failed to parse tool call JSON: $cleaned", e)
            null
        }
    }

    private fun fixMalformedJson(input: String): String {
        var result = input.trim()

        // Remove markdown code fences
        result = result.replace("```json", "").replace("```", "").trim()

        // Fix unquoted keys: {tool: "name"} -> {"tool": "name"}
        // Only match keys that are not already quoted
        result = result.replace(Regex("([{,])\\s*([a-zA-Z_]\\w*)\\s*:")) { match ->
            "${match.groupValues[1]}\"${match.groupValues[2]}\":"
        }

        // Remove trailing commas before closing braces/brackets
        result = result.replace(Regex(",\\s*([}\\]])")) { match ->
            match.groupValues[1]
        }

        return result
    }

    private fun balanceBraces(input: String): String {
        var depth = 0
        var inString = false
        var escaped = false

        for (i in input.indices) {
            val c = input[i]
            if (escaped) {
                escaped = false
                continue
            }
            if (c == '\\') {
                escaped = true
                continue
            }
            if (c == '"') {
                inString = !inString
                continue
            }
            if (!inString) {
                if (c == '{') depth++
                if (c == '}') depth--
            }
        }

        // Append missing closing braces
        val sb = StringBuilder(input)
        while (depth > 0) {
            sb.append('}')
            depth--
        }
        return sb.toString()
    }
}
