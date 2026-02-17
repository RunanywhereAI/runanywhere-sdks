package com.runanywhere.agent.kernel

import android.content.Context
import android.util.Log
import com.runanywhere.agent.AgentApplication
import com.runanywhere.agent.BuildConfig
import com.runanywhere.agent.accessibility.AgentAccessibilityService
import com.runanywhere.agent.actions.AppActions
import com.runanywhere.agent.providers.ProviderMode
import com.runanywhere.agent.providers.VisionProvider
import com.runanywhere.agent.toolcalling.BuiltInTools
import com.runanywhere.agent.toolcalling.LLMResponse
import com.runanywhere.agent.toolcalling.ToolCall
import com.runanywhere.agent.toolcalling.ToolCallParser
import com.runanywhere.agent.toolcalling.ToolDefinition
import com.runanywhere.agent.toolcalling.ToolHandler
import com.runanywhere.agent.toolcalling.ToolPromptFormatter
import com.runanywhere.agent.toolcalling.ToolRegistry
import com.runanywhere.agent.toolcalling.ToolResult
import com.runanywhere.agent.toolcalling.UIActionContext
import com.runanywhere.agent.toolcalling.UIActionTools
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.StructuredOutputConfig
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.loadLLMModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject
import java.util.regex.Pattern

class AgentKernel(
    private val context: Context,
    private val visionProvider: VisionProvider,
    private val onLog: (String) -> Unit
) {
    companion object {
        private const val TAG = "AgentKernel"
        private const val MAX_STEPS = 30
        private const val MAX_DURATION_MS = 180_000L
        private const val STEP_DELAY_MS = 1500L
        private const val MAX_TOOL_ITERATIONS = 5
    }

    private val history = ActionHistory()
    private val screenParser = ScreenParser { AgentAccessibilityService.instance }
    private val actionExecutor = ActionExecutor(
        context = context,
        accessibilityService = { AgentAccessibilityService.instance },
        onLog = onLog
    )

    private val gptClient = GPTClient(
        apiKeyProvider = { BuildConfig.GPT52_API_KEY },
        onLog = onLog
    )

    private val uiActionContext = UIActionContext()

    private val toolRegistry = ToolRegistry().also { registry ->
        BuiltInTools.registerAll(registry, context)
        UIActionTools.registerAll(registry, uiActionContext, actionExecutor)
    }

    private var activeModelId: String = AgentApplication.DEFAULT_MODEL
    private var isRunning = false
    private var planResult: PlanResult? = null

    // Tracks the last prompt for local model tool result re-injection
    private var lastPrompt: String = ""

    fun setModel(modelId: String) {
        activeModelId = modelId
    }

    fun getModel(): String = activeModelId

    fun registerTool(definition: ToolDefinition, handler: ToolHandler) {
        toolRegistry.register(definition, handler)
    }

    sealed class AgentEvent {
        data class Log(val message: String) : AgentEvent()
        data class Step(val step: Int, val action: String, val result: String) : AgentEvent()
        data class Done(val message: String) : AgentEvent()
        data class Error(val message: String) : AgentEvent()
        data class Speak(val text: String) : AgentEvent()
        data class ProviderChanged(val mode: ProviderMode) : AgentEvent()
    }

    fun run(goal: String): Flow<AgentEvent> = flow {
        if (isRunning) {
            emit(AgentEvent.Error("Agent already running"))
            return@flow
        }

        isRunning = true
        history.clear()
        planResult = null

        try {
            emit(AgentEvent.Log("Starting agent..."))
            emit(AgentEvent.Speak("Working on it."))

            // Planning: prefer cloud if available, skip otherwise
            if (gptClient.isConfigured()) {
                emit(AgentEvent.Log("Requesting GPT-4o plan..."))
                planResult = gptClient.generatePlan(goal)
                planResult?.let { plan ->
                    if (plan.steps.isNotEmpty()) {
                        emit(AgentEvent.Log("Plan:"))
                        plan.steps.forEachIndexed { index, step ->
                            emit(AgentEvent.Log("${index + 1}. $step"))
                        }
                    }
                    plan.successCriteria?.let { criteria ->
                        emit(AgentEvent.Log("Success criteria: $criteria"))
                    }
                }
            } else {
                emit(AgentEvent.Log("No cloud API key. Running fully local."))
            }

            val toolCount = toolRegistry.getDefinitions().size
            if (toolCount > 0) {
                emit(AgentEvent.Log("$toolCount tools registered"))
            }

            // Smart pre-launch: open the target app before the agent loop
            val preLaunchResult = preLaunchApp(goal)
            if (preLaunchResult != null) {
                emit(AgentEvent.Log(preLaunchResult))
                delay(1500) // Wait for app to fully launch
            }

            // Ensure LLM model is ready
            emit(AgentEvent.Log("Loading model: $activeModelId"))
            ensureModelReady()
            emit(AgentEvent.Log("Model ready"))

            val startTime = System.currentTimeMillis()
            var step = 0

            while (step < MAX_STEPS && isRunning) {
                step++
                emit(AgentEvent.Log("Step $step/$MAX_STEPS"))

                // Parse screen
                val screen = screenParser.parse()
                if (screen.elementCount == 0) {
                    emit(AgentEvent.Log("No elements found, waiting..."))
                    delay(STEP_DELAY_MS)
                    continue
                }

                // Update UI action context with fresh coordinates
                uiActionContext.indexToCoords = screen.indexToCoords

                // Capture screenshot
                val screenshotBase64 = try {
                    AgentAccessibilityService.instance?.captureScreenshotBase64()
                } catch (e: Exception) {
                    Log.w(TAG, "Screenshot capture failed: ${e.message}")
                    null
                }

                // On-device VLM: analyze screenshot locally
                val visionContext = if (screenshotBase64 != null && visionProvider.isAvailable) {
                    emit(AgentEvent.Log("[LOCAL] Analyzing screen with VLM..."))
                    try {
                        visionProvider.analyzeScreen(screenshotBase64, screen.compactText, goal)
                    } catch (e: Exception) {
                        Log.w(TAG, "VLM analysis failed: ${e.message}")
                        null
                    }
                } else null

                if (visionContext != null) {
                    emit(AgentEvent.Log("[LOCAL] VLM: ${visionContext.take(80)}..."))
                }

                // Determine vision availability (either local VLM or cloud GPT-4o)
                val hasVisionContext = visionContext != null
                val useVision = hasVisionContext || (screenshotBase64 != null && gptClient.isConfigured())

                // Get LLM decision with context
                val historyPrompt = history.formatForPrompt()
                val lastActionResult = history.getLastActionResult()
                val lastAction = history.getLastAction()

                val loopDetected = lastAction != null && history.isRepetitive(lastAction.action, lastAction.target)
                val hadFailure = history.hadRecentFailure()

                // Build prompt — use tool calling format always
                val useToolCalling = true
                val prompt = if (useVision) {
                    when {
                        loopDetected -> {
                            emit(AgentEvent.Log("Loop detected, adding recovery prompt"))
                            SystemPrompts.buildVisionLoopRecoveryPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling)
                        }
                        hadFailure -> {
                            emit(AgentEvent.Log("Recent failure, adding recovery hints"))
                            SystemPrompts.buildVisionFailureRecoveryPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling)
                        }
                        else -> {
                            SystemPrompts.buildVisionPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling)
                        }
                    }
                } else {
                    when {
                        loopDetected -> {
                            emit(AgentEvent.Log("Loop detected, adding recovery prompt"))
                            SystemPrompts.buildLoopRecoveryPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling)
                        }
                        hadFailure -> {
                            emit(AgentEvent.Log("Recent failure, adding recovery hints"))
                            SystemPrompts.buildFailureRecoveryPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling)
                        }
                        else -> {
                            SystemPrompts.buildPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling)
                        }
                    }
                }

                // Inject VLM context into prompt if available
                val enrichedPrompt = if (visionContext != null) {
                    "$prompt\n\nVISION_CONTEXT (from on-device VLM):\n$visionContext"
                } else {
                    prompt
                }

                lastPrompt = enrichedPrompt

                // ========== LOCAL-FIRST LLM ROUTING ==========
                val response = getDecision(enrichedPrompt, screenshotBase64, hasVisionContext) { event ->
                    emit(event)
                }

                // Resolve any tool calls (sub-loop)
                val finalResponse = resolveToolCalls(response, enrichedPrompt) { event -> emit(event) }

                // Handle UI action tool calls from GPT-4o function calling
                if (finalResponse is LLMResponse.UIActionToolCall) {
                    val call = finalResponse.call
                    val actionName = mapToolNameToAction(call.toolName)
                    val target = extractTargetFromToolCall(call)

                    emit(AgentEvent.Log("Action (tool): $actionName"))

                    // Speak key actions
                    when (actionName) {
                        "open" -> (call.arguments["app_name"] as? String)?.let {
                            emit(AgentEvent.Speak("Opening $it"))
                        }
                        "type" -> (call.arguments["text"] as? String)?.let {
                            val preview = if (it.length > 30) it.take(30) + "..." else it
                            emit(AgentEvent.Speak("Typing $preview"))
                        }
                    }

                    // Execute via tool registry (which delegates to ActionExecutor)
                    val result = toolRegistry.execute(call)
                    emit(AgentEvent.Step(step, actionName, result.result))
                    history.record(actionName, target, result.result, !result.isError)

                    if (call.toolName == "ui_done") {
                        emit(AgentEvent.Speak("Task complete."))
                        emit(AgentEvent.Done("Goal achieved"))
                        return@flow
                    }

                    // Check timeout
                    if (System.currentTimeMillis() - startTime > MAX_DURATION_MS) {
                        emit(AgentEvent.Done("Max duration reached"))
                        return@flow
                    }

                    delay(STEP_DELAY_MS)
                    continue
                }

                // Legacy path: handle JSON-based UI actions (local model)
                val decision = when (finalResponse) {
                    is LLMResponse.UIAction -> parseDecision(finalResponse.json)
                    is LLMResponse.TextAnswer -> {
                        emit(AgentEvent.Log("LLM answer: ${finalResponse.text}"))
                        tryExtractDecisionFromText(finalResponse.text) ?: Decision("wait")
                    }
                    is LLMResponse.Error -> {
                        emit(AgentEvent.Log("LLM error: ${finalResponse.message}"))
                        Decision("wait")
                    }
                    is LLMResponse.ToolCalls -> {
                        emit(AgentEvent.Log("Unresolved tool calls after max iterations"))
                        Decision("wait")
                    }
                    is LLMResponse.UIActionToolCall -> {
                        // Should not reach here, handled above
                        Decision("wait")
                    }
                }

                emit(AgentEvent.Log("Action: ${decision.action}"))

                // Speak key actions
                when (decision.action) {
                    "open" -> decision.text?.let { emit(AgentEvent.Speak("Opening $it")) }
                    "type" -> decision.text?.let {
                        val preview = if (it.length > 30) it.take(30) + "..." else it
                        emit(AgentEvent.Speak("Typing $preview"))
                    }
                }

                // Execute action
                val result = actionExecutor.execute(decision, screen.indexToCoords)
                emit(AgentEvent.Step(step, decision.action, result.message))

                // Record in history with success/failure
                val target = when {
                    decision.elementIndex != null -> screenParser.getElementLabel(decision.elementIndex)
                    decision.text != null -> decision.text
                    decision.url != null -> decision.url
                    decision.query != null -> decision.query
                    else -> null
                }
                history.record(decision.action, target, result.message, result.success)

                // Check for completion
                if (decision.action == "done") {
                    emit(AgentEvent.Speak("Task complete."))
                    emit(AgentEvent.Done("Goal achieved"))
                    return@flow
                }

                // Check timeout
                if (System.currentTimeMillis() - startTime > MAX_DURATION_MS) {
                    emit(AgentEvent.Done("Max duration reached"))
                    return@flow
                }

                delay(STEP_DELAY_MS)
            }

            emit(AgentEvent.Speak("I've reached the maximum steps."))
            emit(AgentEvent.Done("Max steps reached"))

        } catch (e: CancellationException) {
            emit(AgentEvent.Log("Agent cancelled"))
        } catch (e: Exception) {
            Log.e(TAG, "Agent error: ${e.message}", e)
            emit(AgentEvent.Error(e.message ?: "Unknown error"))
        } finally {
            isRunning = false
        }
    }

    fun stop() {
        isRunning = false
    }

    // ========== Local-First Decision Routing ==========

    /**
     * LOCAL FIRST: Try on-device LLM, fall back to cloud on failure.
     */
    private suspend fun getDecision(
        prompt: String,
        screenshotBase64: String?,
        hasVisionContext: Boolean,
        emitEvent: suspend (AgentEvent) -> Unit
    ): LLMResponse {
        // Try local first
        val localResponse = try {
            val mode = if (hasVisionContext) ProviderMode.LOCAL else ProviderMode.LOCAL_NO_VISION
            emitEvent(AgentEvent.ProviderChanged(mode))
            emitEvent(AgentEvent.Log("[LOCAL] Reasoning with $activeModelId..."))
            callLocalLLMWithTools(prompt)
        } catch (e: Exception) {
            Log.w(TAG, "Local LLM failed: ${e.message}")
            null
        }

        // If local succeeded, return it
        if (localResponse != null && localResponse !is LLMResponse.Error) {
            return localResponse
        }

        // Fall back to cloud if configured
        if (gptClient.isConfigured()) {
            emitEvent(AgentEvent.ProviderChanged(ProviderMode.CLOUD_FALLBACK))
            emitEvent(AgentEvent.Log("[CLOUD] Falling back to GPT-4o..."))

            val cloudResponse = if (screenshotBase64 != null) {
                callRemoteLLMWithVision(prompt, screenshotBase64)
                    ?: callRemoteLLMWithTools(prompt)
            } else {
                callRemoteLLMWithTools(prompt)
            }

            if (cloudResponse != null) return cloudResponse
        }

        // Both failed
        return localResponse ?: LLMResponse.Error("No LLM available")
    }

    // ========== Tool Calling Integration ==========

    private suspend fun callRemoteLLMWithVision(prompt: String, screenshotBase64: String): LLMResponse? {
        val tools = toolRegistry.getDefinitions()
        return gptClient.generateActionWithVision(prompt, screenshotBase64, tools)
    }

    private suspend fun callRemoteLLMWithTools(prompt: String): LLMResponse? {
        val tools = toolRegistry.getDefinitions()
        return if (tools.isNotEmpty()) {
            gptClient.generateActionWithTools(prompt, tools)
        } else {
            val json = gptClient.generateAction(prompt) ?: return null
            LLMResponse.UIAction(json)
        }
    }

    /**
     * Call local LLM with ALL tools (including ui_* tools).
     * The local model gets the full tool set for autonomous UI control.
     */
    private suspend fun callLocalLLMWithTools(prompt: String): LLMResponse {
        val tools = toolRegistry.getDefinitions()
        val hasTools = tools.isNotEmpty()

        val options = if (hasTools) {
            // When tools are registered: more tokens, no structured output
            // (grammar enforcement would block <tool_call> tags)
            LLMGenerationOptions(
                maxTokens = 128,
                temperature = 0.0f,
                topP = 0.95f,
                streamingEnabled = false,
                systemPrompt = null,
                structuredOutput = null
            )
        } else {
            // No tools: existing behavior with structured output
            LLMGenerationOptions(
                maxTokens = 32,
                temperature = 0.0f,
                topP = 0.95f,
                streamingEnabled = false,
                systemPrompt = null,
                structuredOutput = StructuredOutputConfig(
                    typeName = "Act",
                    includeSchemaInPrompt = true,
                    jsonSchema = SystemPrompts.DECISION_SCHEMA
                )
            )
        }

        val fullPrompt = if (hasTools) {
            prompt + SystemPrompts.TOOL_AWARE_ADDENDUM +
                    ToolPromptFormatter.formatForLocalPrompt(tools)
        } else {
            prompt
        }

        return try {
            val result = withContext(Dispatchers.Default) {
                RunAnywhere.generate(fullPrompt, options)
            }
            val text = result.text

            // Check for tool calls first (only when tools are registered)
            if (hasTools && ToolCallParser.containsToolCall(text)) {
                val calls = ToolCallParser.parse(text)
                if (calls.isNotEmpty()) {
                    return LLMResponse.ToolCalls(calls)
                }
            }

            // Otherwise treat as UI action
            LLMResponse.UIAction(text)
        } catch (e: Exception) {
            Log.e(TAG, "LLM call failed: ${e.message}", e)
            LLMResponse.UIAction("{\"a\":\"done\"}")
        }
    }

    /**
     * Resolve tool calls in a sub-loop: execute tools, feed results back, repeat.
     * Returns the final non-tool-call response.
     */
    private suspend fun resolveToolCalls(
        initialResponse: LLMResponse,
        originalPrompt: String,
        emitEvent: suspend (AgentEvent) -> Unit
    ): LLMResponse {
        var current = initialResponse
        var iterations = 0

        // For GPT-4o multi-turn: maintain conversation history
        val conversationHistory = mutableListOf<JSONObject>()
        var historyInitialized = false

        while (current is LLMResponse.ToolCalls && iterations < MAX_TOOL_ITERATIONS) {
            iterations++
            val toolCalls = current.calls

            // Check if any call is a UI action tool — if so, return it immediately
            // so the main loop handles it as a single-step action
            val uiCall = toolCalls.firstOrNull { it.toolName.startsWith("ui_") }
            if (uiCall != null) {
                return LLMResponse.UIActionToolCall(uiCall)
            }

            val results = mutableListOf<ToolResult>()

            for (call in toolCalls) {
                emitEvent(AgentEvent.Log("Tool call: ${call.toolName}(${call.arguments})"))
                val result = toolRegistry.execute(call)
                emitEvent(AgentEvent.Log("Tool result [${call.toolName}]: ${result.result}"))
                results.add(result)

                // Record in action history
                history.recordToolCall(
                    call.toolName,
                    call.arguments.toString(),
                    result.result,
                    !result.isError
                )
            }

            // Feed results back to LLM
            current = if (gptClient.isConfigured()) {
                // GPT-4o path: build multi-turn conversation history
                if (!historyInitialized) {
                    conversationHistory.add(JSONObject().apply {
                        put("role", "system")
                        put("content", SystemPrompts.TOOL_CALLING_SYSTEM_PROMPT)
                    })
                    conversationHistory.add(JSONObject().apply {
                        put("role", "user")
                        put("content", originalPrompt)
                    })
                    historyInitialized = true
                }

                // Add assistant message with tool calls
                conversationHistory.add(gptClient.buildAssistantToolCallMessage(toolCalls))

                // Add tool result messages
                results.forEach { result ->
                    conversationHistory.add(
                        gptClient.buildToolResultMessage(result.toolCallId, result.result)
                    )
                }

                gptClient.submitToolResults(conversationHistory, toolRegistry.getDefinitions())
                    ?: LLMResponse.Error("GPT-4o tool result submission failed")
            } else {
                // Local model path: append tool results to prompt and re-generate
                val toolResultText = ToolPromptFormatter.formatToolResults(results)
                callLocalLLMWithTools(originalPrompt + toolResultText)
            }
        }

        if (iterations >= MAX_TOOL_ITERATIONS && current is LLMResponse.ToolCalls) {
            return LLMResponse.Error("Max tool calling iterations ($MAX_TOOL_ITERATIONS) reached")
        }

        return current
    }

    /**
     * Try to extract a UI action decision from a text answer.
     */
    private fun tryExtractDecisionFromText(text: String): Decision? {
        val matcher = Pattern.compile("\\{.*?\\}", Pattern.DOTALL).matcher(text)
        if (matcher.find()) {
            try {
                val obj = JSONObject(matcher.group())
                if (obj.has("action") || obj.has("a")) {
                    return extractDecision(obj)
                }
            } catch (_: JSONException) {}
        }
        return null
    }

    // ========== Existing Methods ==========

    private suspend fun ensureModelReady() {
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

    private fun parseDecision(text: String): Decision {
        val cleaned = text
            .replace("```json", "")
            .replace("```", "")
            .trim()

        // Try parsing as JSON
        try {
            val obj = JSONObject(cleaned)
            return extractDecision(obj)
        } catch (_: JSONException) {}

        // Try extracting JSON from text
        val matcher = Pattern.compile("\\{.*?\\}", Pattern.DOTALL).matcher(cleaned)
        if (matcher.find()) {
            try {
                return extractDecision(JSONObject(matcher.group()))
            } catch (_: JSONException) {}
        }

        // Fallback: heuristic parsing
        return heuristicDecision(cleaned)
    }

    private fun extractDecision(obj: JSONObject): Decision {
        val action = obj.optString("action", "").ifEmpty { obj.optString("a", "") }

        // Support both "index" (new) and "i" (old) keys
        val index = obj.optInt("index", -1).let { if (it >= 0) it else obj.optInt("i", -1) }.takeIf { it >= 0 }

        // Map direction values: support both full words and abbreviations
        val rawDirection = obj.optString("direction", "").ifEmpty { obj.optString("d", "") }.takeIf { it.isNotEmpty() }
        val direction = when (rawDirection) {
            "up" -> "u"
            "down" -> "d"
            "left" -> "l"
            "right" -> "r"
            else -> rawDirection
        }

        return Decision(
            action = action.ifEmpty { "done" },
            elementIndex = index,
            text = obj.optString("text", "").ifEmpty { obj.optString("t") }?.takeIf { it.isNotEmpty() },
            direction = direction,
            url = obj.optString("url", "").ifEmpty { obj.optString("u") }?.takeIf { it.isNotEmpty() },
            query = obj.optString("query", "").ifEmpty { obj.optString("q") }?.takeIf { it.isNotEmpty() }
        )
    }

    /**
     * Pre-launch: analyze the goal and open the target app directly via intent.
     */
    private fun preLaunchApp(goal: String): String? {
        val goalLower = goal.lowercase()

        val appMatch = when {
            goalLower.contains("youtube") -> {
                val searchQuery = extractSearchQuery(goalLower, "youtube")
                if (searchQuery != null) {
                    AppActions.openYouTubeSearch(context, searchQuery)
                    return "Pre-launched YouTube with search: $searchQuery"
                }
                AppActions.openApp(context, AppActions.Packages.YOUTUBE)
                "Pre-launched YouTube"
            }
            goalLower.contains("chrome") || goalLower.contains("browser") -> {
                AppActions.openApp(context, AppActions.Packages.CHROME)
                "Pre-launched Chrome"
            }
            goalLower.contains("whatsapp") -> {
                AppActions.openApp(context, AppActions.Packages.WHATSAPP)
                "Pre-launched WhatsApp"
            }
            goalLower.contains("gmail") -> {
                AppActions.openApp(context, AppActions.Packages.GMAIL)
                "Pre-launched Gmail"
            }
            goalLower.contains("spotify") -> {
                val searchQuery = extractSearchQuery(goalLower, "spotify")
                if (searchQuery != null) {
                    AppActions.openSpotifySearch(context, searchQuery)
                    return "Pre-launched Spotify with search: $searchQuery"
                }
                AppActions.openApp(context, AppActions.Packages.SPOTIFY)
                "Pre-launched Spotify"
            }
            goalLower.contains("maps") || goalLower.contains("navigate to") || goalLower.contains("directions to") -> {
                AppActions.openApp(context, AppActions.Packages.MAPS)
                "Pre-launched Maps"
            }
            goalLower.contains("timer") || goalLower.contains("alarm") || goalLower.contains("clock") -> {
                AppActions.openClock(context)
                "Pre-launched Clock"
            }
            goalLower.contains("camera") || goalLower.contains("photo") || goalLower.contains("picture") -> {
                AppActions.openCamera(context)
                "Pre-launched Camera"
            }
            goalLower.contains("settings") -> {
                actionExecutor.openSettings()
                "Pre-launched Settings"
            }
            else -> null
        }

        return appMatch
    }

    private fun extractSearchQuery(goalLower: String, appName: String): String? {
        val patterns = listOf(
            Regex("search\\s+(?:for\\s+)?[\"']?(.+?)[\"']?\\s+on\\s+$appName"),
            Regex("$appName.*?search\\s+(?:for\\s+)?[\"']?(.+?)(?:[\"']|$)"),
            Regex("(?:play|find|look\\s+(?:up|for))\\s+[\"']?(.+?)[\"']?\\s+on\\s+$appName"),
            Regex("$appName.*?(?:play|find|look\\s+(?:up|for))\\s+[\"']?(.+?)(?:[\"']|$)")
        )

        for (pattern in patterns) {
            val match = pattern.find(goalLower)
            if (match != null) {
                val query = match.groupValues[1]
                    .replace(Regex("\\s+and\\s+(play|click|tap|open|select).*"), "")
                    .trim()
                if (query.isNotEmpty() && query.length > 2) return query
            }
        }
        return null
    }

    private fun mapToolNameToAction(toolName: String): String {
        return when (toolName) {
            "ui_tap" -> "tap"
            "ui_type" -> "type"
            "ui_enter" -> "enter"
            "ui_swipe" -> "swipe"
            "ui_back" -> "back"
            "ui_home" -> "home"
            "ui_open_app" -> "open"
            "ui_long_press" -> "long"
            "ui_open_url" -> "url"
            "ui_web_search" -> "search"
            "ui_open_notifications" -> "notif"
            "ui_open_quick_settings" -> "quick"
            "ui_wait" -> "wait"
            "ui_done" -> "done"
            else -> toolName.removePrefix("ui_")
        }
    }

    private fun extractTargetFromToolCall(call: ToolCall): String? {
        return when (call.toolName) {
            "ui_tap", "ui_long_press" -> {
                val index = (call.arguments["index"] as? Number)?.toInt()
                index?.let { screenParser.getElementLabel(it) }
            }
            "ui_type" -> call.arguments["text"]?.toString()
            "ui_open_app" -> call.arguments["app_name"]?.toString()
            "ui_open_url" -> call.arguments["url"]?.toString()
            "ui_web_search" -> call.arguments["query"]?.toString()
            "ui_swipe" -> call.arguments["direction"]?.toString()
            "ui_done" -> call.arguments["reason"]?.toString()
            else -> null
        }
    }

    private fun heuristicDecision(text: String): Decision {
        val lower = text.lowercase()

        return when {
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
    }
}
