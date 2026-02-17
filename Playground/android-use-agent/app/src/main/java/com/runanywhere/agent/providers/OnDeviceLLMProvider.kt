package com.runanywhere.agent.providers

import android.content.Context
import android.util.Log
import com.runanywhere.agent.AgentApplication
import com.runanywhere.agent.kernel.Decision
import com.runanywhere.agent.kernel.SystemPrompts
import com.runanywhere.agent.tools.UtilityTools
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import com.runanywhere.sdk.public.extensions.LLM.StructuredOutputConfig
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOptions
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.loadLLMModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.regex.Pattern

/**
 * On-device LLM provider using the RunAnywhere SDK.
 *
 * Uses [RunAnywhere.generate] for text generation with structured output,
 * and [RunAnywhereToolCalling.generateWithTools] for generations that may
 * require utility tool calls (weather, time, math, etc.).
 *
 * The SDK's C++ layer handles:
 * - Tool prompt formatting and injection
 * - <tool_call> tag parsing (single source of truth)
 * - Auto-execution of utility tools
 * - Re-generation with tool results
 */
class OnDeviceLLMProvider(
    private val appContext: Context,
    private val onLog: (String) -> Unit
) : AgentLLMProvider {

    companion object {
        private const val TAG = "OnDeviceLLMProvider"
    }

    private var activeModelId: String = AgentApplication.DEFAULT_MODEL
    private var utilityToolsRegistered = false

    override fun setModel(modelId: String) {
        activeModelId = modelId
    }

    override fun getModel(): String = activeModelId

    /**
     * Register utility tools (weather, time, calculator, etc.) with the SDK.
     * Call once before the agent loop starts.
     */
    suspend fun registerUtilityTools() {
        if (utilityToolsRegistered) return
        UtilityTools.registerAll(appContext)
        utilityToolsRegistered = true
        onLog("Utility tools registered")
    }

    override suspend fun ensureModelReady() {
        try {
            RunAnywhere.loadLLMModel(activeModelId)
        } catch (e: Exception) {
            onLog("Downloading model...")
            var lastPercent = -1
            RunAnywhere.downloadModel(activeModelId).collect { progress ->
                val percent = (progress.progress * 100).toInt()
                if (percent != lastPercent && percent % 10 == 0) {
                    lastPercent = percent
                    onLog("Downloading... $percent%")
                }
            }
            RunAnywhere.loadLLMModel(activeModelId)
        }
    }

    override suspend fun decideNextAction(context: ReasoningContext): AgentDecision {
        val systemPrompt = SystemPrompts.SYSTEM_PROMPT
        val userPrompt = SystemPrompts.buildPrompt(
            goal = context.goal,
            screenState = context.screenElements,
            history = context.historyPrompt,
            lastActionResult = context.lastActionResult,
            useToolCalling = utilityToolsRegistered
        )

        val responseText = try {
            if (utilityToolsRegistered) {
                generateWithToolCalling(userPrompt, systemPrompt)
            } else {
                generateWithStructuredOutput(userPrompt, systemPrompt)
            }
        } catch (e: Exception) {
            Log.e(TAG, "LLM generation failed: ${e.message}", e)
            return AgentDecision.Error("LLM generation failed: ${e.message}")
        }

        return parseResponseToDecision(responseText)
    }

    override suspend fun generatePlan(goal: String): PlanResult? {
        return try {
            val prompt = "You are an expert Android planning assistant. " +
                    "Always respond with valid minified JSON.\n\n" +
                    SystemPrompts.buildPlanningPrompt(goal)
            val result = withContext(Dispatchers.Default) {
                RunAnywhere.generate(
                    prompt,
                    LLMGenerationOptions(
                        maxTokens = 256,
                        temperature = 0.0f,
                        topP = 0.95f,
                        streamingEnabled = false,
                        structuredOutput = StructuredOutputConfig(
                            typeName = "Plan",
                            includeSchemaInPrompt = true,
                            jsonSchema = SystemPrompts.PLANNING_SCHEMA
                        )
                    )
                )
            }
            parsePlan(result.text)
        } catch (e: Exception) {
            Log.w(TAG, "Plan generation failed: ${e.message}")
            null
        }
    }

    // ========== Generation Strategies ==========

    /**
     * Generate with SDK tool calling. The SDK handles:
     * 1. Building tool descriptions in the system prompt (C++)
     * 2. Generating LLM response
     * 3. Parsing <tool_call> tags (C++)
     * 4. Auto-executing registered utility tools
     * 5. Re-generating with tool results
     *
     * Returns the final text after all tool calls are resolved.
     */
    private suspend fun generateWithToolCalling(
        userPrompt: String,
        systemPrompt: String
    ): String {
        val result = RunAnywhereToolCalling.generateWithTools(
            prompt = userPrompt,
            options = ToolCallingOptions(
                systemPrompt = systemPrompt,
                maxToolCalls = 3,
                autoExecute = true,
                temperature = 0.0f,
                maxTokens = 128
            )
        )

        result.toolCalls.forEachIndexed { i, call ->
            val toolResult = result.toolResults.getOrNull(i)
            val status = if (toolResult?.success == true) "OK" else "FAILED"
            onLog("Tool: ${call.toolName} → $status")
        }

        return result.text
    }

    /**
     * Generate with structured output (grammar enforcement) for clean JSON.
     * Used when no utility tools are registered.
     */
    private suspend fun generateWithStructuredOutput(
        userPrompt: String,
        systemPrompt: String
    ): String {
        val fullPrompt = "$systemPrompt\n\n$userPrompt"
        val result = withContext(Dispatchers.Default) {
            RunAnywhere.generate(
                fullPrompt,
                LLMGenerationOptions(
                    maxTokens = 32,
                    temperature = 0.0f,
                    topP = 0.95f,
                    streamingEnabled = false,
                    structuredOutput = StructuredOutputConfig(
                        typeName = "Act",
                        includeSchemaInPrompt = true,
                        jsonSchema = SystemPrompts.DECISION_SCHEMA
                    )
                )
            )
        }
        return result.text
    }

    // ========== Response Parsing ==========

    /**
     * Parse LLM output into an AgentDecision.
     * Handles clean JSON, JSON embedded in text, and heuristic fallback.
     */
    private fun parseResponseToDecision(text: String): AgentDecision {
        val cleaned = text
            .replace("```json", "")
            .replace("```", "")
            .trim()

        // Try direct JSON parse
        extractDecisionFromJson(cleaned)?.let { return it }

        // Try extracting JSON from surrounding text
        val matcher = Pattern.compile("\\{.*?\\}", Pattern.DOTALL).matcher(cleaned)
        if (matcher.find()) {
            extractDecisionFromJson(matcher.group())?.let { return it }
        }

        // Heuristic fallback
        return heuristicDecision(cleaned)
    }

    private fun extractDecisionFromJson(jsonStr: String): AgentDecision? {
        return try {
            val obj = JSONObject(jsonStr)
            val action = obj.optString("action", "").ifEmpty { obj.optString("a", "") }
            if (action.isEmpty()) return null

            if (action == "done") {
                return AgentDecision.Done(obj.optString("reason", "Goal complete"))
            }

            val index = obj.optInt("index", -1)
                .let { if (it >= 0) it else obj.optInt("i", -1) }
                .takeIf { it >= 0 }

            val rawDirection = obj.optString("direction", "")
                .ifEmpty { obj.optString("d", "") }
                .takeIf { it.isNotEmpty() }
            val direction = when (rawDirection) {
                "up" -> "u"; "down" -> "d"; "left" -> "l"; "right" -> "r"
                else -> rawDirection
            }

            AgentDecision.UIAction(
                Decision(
                    action = action,
                    elementIndex = index,
                    text = obj.optString("text", "").ifEmpty { obj.optString("t") }
                        ?.takeIf { it.isNotEmpty() },
                    direction = direction,
                    url = obj.optString("url", "").ifEmpty { obj.optString("u") }
                        ?.takeIf { it.isNotEmpty() },
                    query = obj.optString("query", "").ifEmpty { obj.optString("q") }
                        ?.takeIf { it.isNotEmpty() }
                )
            )
        } catch (_: JSONException) {
            null
        }
    }

    private fun heuristicDecision(text: String): AgentDecision {
        val lower = text.lowercase()
        val decision = when {
            lower.contains("done") -> Decision("done")
            lower.contains("back") -> Decision("back")
            lower.contains("home") -> Decision("home")
            lower.contains("enter") -> Decision("enter")
            lower.contains("wait") -> Decision("wait")
            lower.contains("swipe") || lower.contains("scroll") -> {
                val dir = when {
                    lower.contains("up") -> "u"
                    lower.contains("down") -> "d"
                    lower.contains("left") -> "l"
                    lower.contains("right") -> "r"
                    else -> "u"
                }
                Decision("swipe", direction = dir)
            }
            lower.contains("tap") || lower.contains("click") -> {
                val idx = Regex("\\d+").find(text)?.value?.toIntOrNull() ?: 0
                Decision("tap", elementIndex = idx)
            }
            lower.contains("type") -> {
                val textMatch = Regex("\"([^\"]+)\"").find(text)
                Decision("type", text = textMatch?.groupValues?.getOrNull(1) ?: "")
            }
            else -> Decision("done")
        }

        return if (decision.action == "done") {
            AgentDecision.Done("Inferred completion from LLM output")
        } else {
            AgentDecision.UIAction(decision)
        }
    }

    private fun parsePlan(text: String): PlanResult? {
        return try {
            val cleaned = text
                .replace("```json", "")
                .replace("```", "")
                .trim()
            val obj = JSONObject(cleaned)
            val stepsArray = obj.optJSONArray("steps") ?: JSONArray()
            val steps = (0 until stepsArray.length()).map { stepsArray.optString(it) }
            val successCriteria = obj.optString("success_criteria").takeIf { it.isNotEmpty() }
            PlanResult(steps, successCriteria)
        } catch (_: Exception) {
            null
        }
    }
}
