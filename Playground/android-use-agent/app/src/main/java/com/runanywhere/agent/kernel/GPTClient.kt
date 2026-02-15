package com.runanywhere.agent.kernel

import android.util.Log
import com.runanywhere.agent.toolcalling.LLMResponse
import com.runanywhere.agent.toolcalling.ToolCall
import com.runanywhere.agent.toolcalling.ToolDefinition
import com.runanywhere.agent.toolcalling.ToolPromptFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class GPTClient(
    private val apiKeyProvider: () -> String?,
    private val onLog: (String) -> Unit
) {
    companion object {
        private const val TAG = "GPTClient"
        private const val API_URL = "https://api.openai.com/v1/chat/completions"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    fun isConfigured(): Boolean = !apiKeyProvider().isNullOrBlank()

    suspend fun generatePlan(task: String): PlanResult? {
        val content = request(
            systemPrompt = "You are an expert Android planning assistant. Always respond with valid minified JSON following this schema: ${SystemPrompts.PLANNING_SCHEMA}",
            userPrompt = SystemPrompts.buildPlanningPrompt(task),
            maxTokens = 256
        ) ?: return null

        return try {
            parsePlan(content)
        } catch (e: JSONException) {
            Log.e(TAG, "Failed to parse plan: ${e.message}")
            null
        }
    }

    suspend fun generateAction(prompt: String): String? {
        return request(
            systemPrompt = SystemPrompts.SYSTEM_PROMPT,
            userPrompt = prompt,
            maxTokens = 256
        )
    }

    /**
     * Send a prompt with tool definitions using OpenAI's native function calling.
     * Does NOT use response_format: json_object (incompatible with tools).
     */
    suspend fun generateActionWithTools(
        prompt: String,
        tools: List<ToolDefinition>,
        conversationHistory: List<JSONObject>? = null
    ): LLMResponse? {
        val apiKey = apiKeyProvider()?.takeIf { it.isNotBlank() } ?: return null

        val messages = JSONArray()

        if (conversationHistory != null && conversationHistory.isNotEmpty()) {
            // Use provided conversation history (for multi-turn tool calling)
            conversationHistory.forEach { messages.put(it) }
        } else {
            // First turn: system + user messages
            messages.put(JSONObject().put("role", "system").put("content",
                SystemPrompts.TOOL_CALLING_SYSTEM_PROMPT
            ))
            messages.put(JSONObject().put("role", "user").put("content", prompt))
        }

        val payload = JSONObject().apply {
            put("model", "gpt-4o")
            put("temperature", 0)
            put("max_tokens", 512)
            put("messages", messages)
            if (tools.isNotEmpty()) {
                put("tools", ToolPromptFormatter.toOpenAIFormat(tools))
                put("parallel_tool_calls", false)
            }
        }

        val request = Request.Builder()
            .url(API_URL)
            .header("Authorization", "Bearer $apiKey")
            .header("Content-Type", JSON_MEDIA.toString())
            .post(payload.toString().toRequestBody(JSON_MEDIA))
            .build()

        return try {
            val response = withContext(Dispatchers.IO) { client.newCall(request).execute() }
            val body = response.body?.string()
            if (!response.isSuccessful) {
                val err = body ?: response.message
                Log.e(TAG, "GPT tool call failed: ${response.code} $err")
                onLog("GPT-4o error ${response.code}")
                null
            } else {
                body?.let { extractLLMResponse(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "GPT tool request error: ${e.message}", e)
            onLog("GPT-4o request failed: ${e.message}")
            null
        }
    }

    /**
     * Send a prompt with a screenshot image to GPT-4o vision.
     * Uses multi-part content format: [text, image_url].
     */
    suspend fun generateActionWithVision(
        prompt: String,
        screenshotBase64: String,
        tools: List<ToolDefinition>,
        conversationHistory: List<JSONObject>? = null
    ): LLMResponse? {
        val apiKey = apiKeyProvider()?.takeIf { it.isNotBlank() } ?: return null

        val messages = JSONArray()

        if (conversationHistory != null && conversationHistory.isNotEmpty()) {
            conversationHistory.forEach { messages.put(it) }
        } else {
            messages.put(JSONObject().put("role", "system").put("content",
                SystemPrompts.TOOL_CALLING_VISION_SYSTEM_PROMPT
            ))

            // User message with multi-part content: text + image
            val contentArray = JSONArray().apply {
                put(JSONObject().apply {
                    put("type", "text")
                    put("text", prompt)
                })
                put(JSONObject().apply {
                    put("type", "image_url")
                    put("image_url", JSONObject().apply {
                        put("url", "data:image/jpeg;base64,$screenshotBase64")
                        put("detail", "low")
                    })
                })
            }
            messages.put(JSONObject().apply {
                put("role", "user")
                put("content", contentArray)
            })
        }

        val payload = JSONObject().apply {
            put("model", "gpt-4o")
            put("temperature", 0)
            put("max_tokens", 512)
            put("messages", messages)
            if (tools.isNotEmpty()) {
                put("tools", ToolPromptFormatter.toOpenAIFormat(tools))
                put("parallel_tool_calls", false)
            }
        }

        val request = Request.Builder()
            .url(API_URL)
            .header("Authorization", "Bearer $apiKey")
            .header("Content-Type", JSON_MEDIA.toString())
            .post(payload.toString().toRequestBody(JSON_MEDIA))
            .build()

        return try {
            val response = withContext(Dispatchers.IO) { client.newCall(request).execute() }
            val body = response.body?.string()
            if (!response.isSuccessful) {
                val err = body ?: response.message
                Log.e(TAG, "GPT vision failed: ${response.code} $err")
                onLog("GPT-4o vision error ${response.code}")
                null
            } else {
                body?.let { extractLLMResponse(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "GPT vision error: ${e.message}", e)
            onLog("GPT-4o vision failed: ${e.message}")
            null
        }
    }

    /**
     * Build a user message with vision content for conversation history.
     */
    fun buildUserVisionMessage(prompt: String, screenshotBase64: String): JSONObject {
        val contentArray = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "text")
                put("text", prompt)
            })
            put(JSONObject().apply {
                put("type", "image_url")
                put("image_url", JSONObject().apply {
                    put("url", "data:image/jpeg;base64,$screenshotBase64")
                    put("detail", "low")
                })
            })
        }
        return JSONObject().apply {
            put("role", "user")
            put("content", contentArray)
        }
    }

    /**
     * Submit tool results back to GPT-4o for a follow-up response.
     * The conversationHistory should contain the full message chain including
     * the assistant message with tool_calls and tool role result messages.
     */
    suspend fun submitToolResults(
        conversationHistory: List<JSONObject>,
        tools: List<ToolDefinition>
    ): LLMResponse? {
        return generateActionWithTools(
            prompt = "", // not used when conversationHistory is provided
            tools = tools,
            conversationHistory = conversationHistory
        )
    }

    /**
     * Build the assistant message JSON for a tool_calls response.
     * Used to construct conversation history for multi-turn tool calling.
     */
    fun buildAssistantToolCallMessage(toolCalls: List<ToolCall>): JSONObject {
        val toolCallsArray = JSONArray()
        toolCalls.forEach { call ->
            val argsJson = JSONObject()
            call.arguments.forEach { (key, value) ->
                argsJson.put(key, value)
            }
            toolCallsArray.put(JSONObject().apply {
                put("id", call.id)
                put("type", "function")
                put("function", JSONObject().apply {
                    put("name", call.toolName)
                    put("arguments", argsJson.toString())
                })
            })
        }
        return JSONObject().apply {
            put("role", "assistant")
            put("tool_calls", toolCallsArray)
        }
    }

    /**
     * Build a tool result message for the conversation history.
     */
    fun buildToolResultMessage(toolCallId: String, result: String): JSONObject {
        return JSONObject().apply {
            put("role", "tool")
            put("tool_call_id", toolCallId)
            put("content", result)
        }
    }

    // ---- Existing private methods ----

    private suspend fun request(systemPrompt: String, userPrompt: String, maxTokens: Int): String? {
        val apiKey = apiKeyProvider()?.takeIf { it.isNotBlank() } ?: return null

        val payload = JSONObject().apply {
            put("model", "gpt-4o")
            put("temperature", 0)
            put("max_tokens", maxTokens)
            put("response_format", JSONObject().put("type", "json_object"))
            put("messages", JSONArray().apply {
                put(JSONObject().put("role", "system").put("content", systemPrompt))
                put(JSONObject().put("role", "user").put("content", userPrompt))
            })
        }

        val request = Request.Builder()
            .url(API_URL)
            .header("Authorization", "Bearer $apiKey")
            .header("Content-Type", JSON_MEDIA.toString())
            .post(payload.toString().toRequestBody(JSON_MEDIA))
            .build()

        return try {
            val response = withContext(Dispatchers.IO) { client.newCall(request).execute() }
            val body = response.body?.string()
            if (!response.isSuccessful) {
                val err = body ?: response.message
                Log.e(TAG, "GPT call failed: ${response.code} $err")
                onLog("GPT-4o error ${response.code}")
                null
            } else {
                body?.let { extractContent(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "GPT request error: ${e.message}", e)
            onLog("GPT-4o request failed: ${e.message}")
            null
        }
    }

    private fun extractContent(body: String): String? {
        val json = JSONObject(body)
        val choices = json.optJSONArray("choices") ?: return null
        val message = choices.optJSONObject(0)?.optJSONObject("message") ?: return null
        val arrayContent = message.optJSONArray("content")
        return when {
            arrayContent != null -> buildString {
                for (i in 0 until arrayContent.length()) {
                    val part = arrayContent.optJSONObject(i)
                    if (part != null) {
                        append(part.optString("text"))
                    } else {
                        append(arrayContent.optString(i))
                    }
                }
            }.trim()
            else -> message.optString("content").trim()
        }
    }

    /**
     * Parse GPT-4o response into an LLMResponse, handling both tool_calls and content.
     */
    private fun extractLLMResponse(body: String): LLMResponse {
        val json = JSONObject(body)
        val choices = json.optJSONArray("choices")
        if (choices == null || choices.length() == 0) {
            return LLMResponse.Error("No choices in GPT response")
        }
        val message = choices.optJSONObject(0)?.optJSONObject("message")
            ?: return LLMResponse.Error("No message in GPT response")

        // Check for tool calls first
        val toolCallsArray = message.optJSONArray("tool_calls")
        if (toolCallsArray != null && toolCallsArray.length() > 0) {
            val calls = mutableListOf<ToolCall>()
            for (i in 0 until toolCallsArray.length()) {
                val tc = toolCallsArray.getJSONObject(i)
                val id = tc.getString("id")
                val function = tc.getJSONObject("function")
                val name = function.getString("name")
                val argsStr = function.getString("arguments")
                val argsObj = try { JSONObject(argsStr) } catch (_: Exception) { JSONObject() }
                val args = mutableMapOf<String, Any?>()
                val keys = argsObj.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    args[key] = argsObj.opt(key)
                }
                calls.add(ToolCall(id = id, toolName = name, arguments = args))
            }
            return LLMResponse.ToolCalls(calls)
        }

        // No tool calls -- extract content
        val content = message.optString("content", "").trim()
        if (content.isEmpty()) {
            return LLMResponse.Error("Empty response from GPT")
        }

        // Determine if it's a UI action JSON or a text answer
        return try {
            val cleaned = content
                .replace("```json", "")
                .replace("```", "")
                .trim()
            val obj = JSONObject(cleaned)
            if (obj.has("action") || obj.has("a")) {
                LLMResponse.UIAction(cleaned)
            } else {
                LLMResponse.TextAnswer(content)
            }
        } catch (_: JSONException) {
            LLMResponse.TextAnswer(content)
        }
    }

    private fun parsePlan(text: String): PlanResult {
        val cleaned = text
            .replace("```json", "")
            .replace("```", "")
            .trim()
        val obj = JSONObject(cleaned)
        val stepsArray = obj.optJSONArray("steps") ?: JSONArray()
        val steps = mutableListOf<String>()
        for (i in 0 until stepsArray.length()) {
            steps.add(stepsArray.optString(i))
        }
        val successCriteria = obj.optString("success_criteria").takeIf { it.isNotEmpty() }
        return PlanResult(steps, successCriteria)
    }
}

data class PlanResult(
    val steps: List<String>,
    val successCriteria: String?
)
