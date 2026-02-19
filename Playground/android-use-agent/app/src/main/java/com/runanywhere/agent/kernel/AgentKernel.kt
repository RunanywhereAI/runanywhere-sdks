package com.runanywhere.agent.kernel

import android.content.Context
import android.util.Log
import com.runanywhere.agent.AgentApplication
import com.runanywhere.agent.BuildConfig
import com.runanywhere.agent.accessibility.AgentAccessibilityService
import com.runanywhere.agent.actions.AppActions
import com.runanywhere.agent.providers.ProviderMode
import com.runanywhere.agent.providers.VisionProvider
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
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.StructuredOutputConfig
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import com.runanywhere.sdk.public.extensions.loadLLMModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject
import java.util.Locale
import java.util.regex.Pattern

class AgentKernel(
    private val context: Context,
    private val visionProvider: VisionProvider,
    private val onLog: (String) -> Unit
) {
    companion object {
        private const val TAG = "AgentKernel"
        private const val MAX_STEPS = 30
        private const val MAX_DURATION_MS = 1_800_000L // 30 min — Qwen3-4B at 0.2 tok/s takes ~100s/step
        private const val STEP_DELAY_MS = 1000L
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
        // Only register UI action tools — utility tools (time, weather, etc.)
        // confuse small on-device LLMs and cause tool-calling loops.
        UIActionTools.registerAll(registry, uiActionContext, actionExecutor)
    }

    private var activeModelId: String = AgentApplication.DEFAULT_MODEL
    @Volatile
    private var isRunning = false
    private var planResult: PlanResult? = null

    /** Tweet text if compose was pre-launched via deep link. Non-null means compose should stay open. */
    private var xComposeMessage: String? = null

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
        /** Live token emitted during on-device LLM inference — for streaming overlay UI. */
        data class ThinkingToken(val token: String) : AgentEvent()
        /** Per-step performance metrics emitted after LLM inference completes. */
        data class PerfMetrics(
            val step: Int,
            val tokensPerSecond: Double,
            val outputTokens: Int,
            val inputTokens: Int,
            val latencyMs: Double,
            val thinkingContent: String?,
        ) : AgentEvent()
    }

    /** Structured record of one agent step — used for log export. */
    data class StepRecord(
        val step: Int,
        val timestampMs: Long,
        val promptSnippet: String,
        val rawOutput: String,
        val thinkingContent: String?,
        val action: String,
        val durationMs: Long,
        val tokensPerSecond: Double,
        val outputTokens: Int,
        val inputTokens: Int,
    )

    private val _stepRecords = mutableListOf<StepRecord>()
    fun getStepRecords(): List<StepRecord> = _stepRecords.toList()

    fun run(goal: String): Flow<AgentEvent> = flow {
        if (isRunning) {
            emit(AgentEvent.Error("Agent already running"))
            return@flow
        }

        isRunning = true
        history.clear()
        _stepRecords.clear()
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
            var hasNavigatedAway = false
            var lastTargetPackage: String? = null
            val preLaunch = preLaunchApp(goal)
            if (preLaunch != null) {
                emit(AgentEvent.Log(preLaunch.message))
                hasNavigatedAway = true
                lastTargetPackage = preLaunch.packageName
                delay(2000) // Wait for app to fully launch

                // If preLaunch already completed the goal (e.g., timer set, search done)
                if (preLaunch.goalComplete) {
                    emit(AgentEvent.Log("Pre-launch completed goal directly"))
                    emit(AgentEvent.Speak("Task complete."))
                    emit(AgentEvent.Done("Goal achieved via pre-launch"))
                    return@flow
                }

                // If preLaunch performed a search, verify we navigated away
                if (preLaunch.didSearch) {
                    val screen = screenParser.parse()
                    if (screen.foregroundPackage != null && screen.foregroundPackage != "com.runanywhere.agent") {
                        emit(AgentEvent.Log("Pre-launch completed goal (search already performed)"))
                        emit(AgentEvent.Speak("Task complete."))
                        emit(AgentEvent.Done("Goal achieved via pre-launch"))
                        return@flow
                    }
                }
            }

            // Load LLM model — graceful if VLM is available as fallback
            val llmReady = try {
                emit(AgentEvent.Log("Loading LLM model: $activeModelId"))
                ensureModelReady()
                emit(AgentEvent.Log("LLM model ready"))
                true
            } catch (e: Exception) {
                if (visionProvider.isAvailable) {
                    emit(AgentEvent.Log("LLM load failed, using VLM-only mode"))
                    false
                } else {
                    throw e // No fallback available
                }
            }

            val vlmOnly = !llmReady && visionProvider.isAvailable
            if (vlmOnly) {
                emit(AgentEvent.Log("Running in VLM-only mode (no LLM)"))
                emit(AgentEvent.ProviderChanged(ProviderMode.LOCAL))
            }

            val startTime = System.currentTimeMillis()
            var step = 0

            while (step < MAX_STEPS && isRunning) {
                step++
                val stepStart = System.currentTimeMillis()
                emit(AgentEvent.Log("Step $step/$MAX_STEPS"))

                // Self-detection: never analyze/interact with our own UI
                val currentFgCheck = screenParser.parse().foregroundPackage
                if (currentFgCheck == "com.runanywhere.agent") {
                    if (hasNavigatedAway && lastTargetPackage != null) {
                        Log.i(TAG, "Returning to target app: $lastTargetPackage")
                        bringAppToForeground(lastTargetPackage!!)
                        delay(800)
                    } else {
                        // preLaunch didn't fire — try to open the target app from goal
                        Log.w(TAG, "Agent sees own UI but no target app set. Attempting preLaunch.")
                        val latePre = preLaunchApp(goal)
                        if (latePre != null) {
                            emit(AgentEvent.Log(latePre.message))
                            hasNavigatedAway = true
                            lastTargetPackage = latePre.packageName
                            delay(2000)
                            if (latePre.goalComplete) {
                                emit(AgentEvent.Done("Goal achieved via late pre-launch"))
                                return@flow
                            }
                        } else {
                            // Last resort: press Home and wait — avoids interacting with own UI
                            Log.w(TAG, "No preLaunch match — pressing Home to escape own UI")
                            actionExecutor.execute(Decision("home"), emptyMap())
                            delay(1000)
                        }
                    }
                    continue // Re-parse after navigating away
                }

                // Parse screen
                val screen = screenParser.parse()
                if (screen.elementCount == 0) {
                    emit(AgentEvent.Log("No elements found, waiting..."))
                    delay(STEP_DELAY_MS)
                    continue
                }

                // Track the target app package
                if (screen.foregroundPackage != null && screen.foregroundPackage != "com.runanywhere.agent") {
                    lastTargetPackage = screen.foregroundPackage
                }

                Log.i(TAG, "Screen: pkg=${screen.foregroundPackage}, ${screen.elementCount} elements")
                Log.i(TAG, "Elements: ${screen.compactText.take(1500)}")

                // Update UI action context with fresh coordinates
                uiActionContext.indexToCoords = screen.indexToCoords

                // Capture screenshot
                val screenshotBase64 = try {
                    AgentAccessibilityService.instance?.captureScreenshotBase64()
                } catch (e: Exception) {
                    Log.w(TAG, "Screenshot capture failed: ${e.message}")
                    null
                }

                // Common context for both paths — use compact history for local models
                val historyPrompt = history.formatCompact()
                val lastActionResult = history.getLastActionResult()
                val lastAction = history.getLastAction()
                val loopDetected = lastAction != null && history.isRepetitive(lastAction.action, lastAction.target)
                val hadFailure = history.hadRecentFailure()

                // Smart recovery on loop: try to find a matching element or use search.
                if (loopDetected) {
                    val recoveryResult = trySmartRecovery(goal, screen, step) { event -> emit(event) }
                    when (recoveryResult) {
                        RecoveryResult.GOAL_ACHIEVED -> return@flow
                        RecoveryResult.ACTION_TAKEN -> { delay(STEP_DELAY_MS); continue }
                        RecoveryResult.NO_ACTION -> { /* fall through to LLM */ }
                    }
                }

                // Quick completion check for X compose: if POST button is visible, tap it directly.
                // MUST run before bringToForeground() so compose screen is never disrupted by inference.
                if (xComposeMessage != null && screen.foregroundPackage == AppActions.Packages.TWITTER) {
                    val postIndex = findPostButtonIndex(screen.compactText)
                    if (postIndex != null && screen.indexToCoords.containsKey(postIndex)) {
                        emit(AgentEvent.Log("[X] POST button at index $postIndex — tapping directly"))
                        val tapResult = actionExecutor.execute(Decision("tap", elementIndex = postIndex), screen.indexToCoords)
                        emit(AgentEvent.Step(step, "tap", tapResult.message))
                        history.record("tap", "POST", tapResult.message, tapResult.success)
                        if (tapResult.success) {
                            xComposeMessage = null
                            delay(1500)
                            emit(AgentEvent.Speak("Posted successfully."))
                            emit(AgentEvent.Done("Successfully posted on X"))
                            return@flow
                        }
                    }
                }

                // ========== VLM-ONLY PATH ==========
                if (vlmOnly && screenshotBase64 != null) {
                    // Foreground boost for VLM inference too
                    if (screen.foregroundPackage != "com.runanywhere.agent") {
                        bringToForeground()
                        delay(300)
                    }
                    emit(AgentEvent.Log("[VLM-ONLY] Deciding next action..."))
                    val vlmRawOutput = try {
                        visionProvider.decideNextAction(
                            screenshotBase64, screen.compactText, goal,
                            historyPrompt, lastActionResult
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "VLM decision failed: ${e.message}")
                        null
                    }

                    if (vlmRawOutput != null) {
                        emit(AgentEvent.Log("[VLM-ONLY] Output: ${vlmRawOutput.take(100)}"))

                        // Go back to target app after VLM inference
                        if (screen.foregroundPackage != null && screen.foregroundPackage != "com.runanywhere.agent") {
                            val currentFgVlm = screenParser.parse().foregroundPackage
                            if (currentFgVlm == "com.runanywhere.agent") {
                                bringAppToForeground(screen.foregroundPackage!!)
                                delay(500)
                            }
                        }

                        // Try parsing as tool call first
                        if (ToolCallParser.containsToolCall(vlmRawOutput)) {
                            val calls = ToolCallParser.parse(vlmRawOutput)
                            val uiCall = calls.firstOrNull { it.toolName.startsWith("ui_") }
                            if (uiCall != null) {
                                val actionName = mapToolNameToAction(uiCall.toolName)
                                val target = extractTargetFromToolCall(uiCall)
                                emit(AgentEvent.Log("Action (vlm): $actionName"))
                                val result = toolRegistry.execute(uiCall)
                                emit(AgentEvent.Step(step, actionName, result.result))
                                history.record(actionName, target, result.result, !result.isError)

                                if (uiCall.toolName == "ui_done") {
                                    emit(AgentEvent.Speak("Task complete."))
                                    emit(AgentEvent.Done("Goal achieved"))
                                    return@flow
                                }

                                val stepElapsed = System.currentTimeMillis() - stepStart
                                emit(AgentEvent.Log("Step $step took ${stepElapsed / 1000}s"))
                                if (System.currentTimeMillis() - startTime > MAX_DURATION_MS) {
                                    emit(AgentEvent.Done("Max duration reached"))
                                    return@flow
                                }
                                delay(STEP_DELAY_MS)
                                continue
                            }
                        }

                        // Fallback: try parsing as JSON decision
                        val decision = parseDecision(vlmRawOutput)
                        emit(AgentEvent.Log("Action (vlm-json): ${decision.action}"))
                        val result = actionExecutor.execute(decision, screen.indexToCoords)
                        emit(AgentEvent.Step(step, decision.action, result.message))
                        val target = when {
                            decision.elementIndex != null -> screenParser.getElementLabel(decision.elementIndex)
                            decision.text != null -> decision.text
                            else -> null
                        }
                        history.record(decision.action, target, result.message, result.success)

                        if (decision.action == "done") {
                            emit(AgentEvent.Speak("Task complete."))
                            emit(AgentEvent.Done("Goal achieved"))
                            return@flow
                        }

                        val stepElapsed = System.currentTimeMillis() - stepStart
                        emit(AgentEvent.Log("Step $step took ${stepElapsed / 1000}s"))
                        if (System.currentTimeMillis() - startTime > MAX_DURATION_MS) {
                            emit(AgentEvent.Done("Max duration reached"))
                            return@flow
                        }
                        delay(STEP_DELAY_MS)
                        continue
                    } else {
                        emit(AgentEvent.Log("[VLM-ONLY] No output, waiting..."))
                        delay(STEP_DELAY_MS)
                        continue
                    }
                }

                // ========== LLM PATH (with optional VLM context) ==========

                // On-device VLM: analyze screenshot locally for context enrichment
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

                val hasVisionContext = visionContext != null
                val useVision = hasVisionContext || (screenshotBase64 != null && gptClient.isConfigured())

                // Build prompt — use tool calling format always
                val useToolCalling = true
                val prompt = if (useVision) {
                    when {
                        loopDetected -> {
                            emit(AgentEvent.Log("Loop detected, adding recovery prompt"))
                            SystemPrompts.buildVisionLoopRecoveryPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling, visionContext)
                        }
                        hadFailure -> {
                            emit(AgentEvent.Log("Recent failure, adding recovery hints"))
                            SystemPrompts.buildVisionFailureRecoveryPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling, visionContext)
                        }
                        else -> {
                            SystemPrompts.buildVisionPrompt(goal, screen.compactText, historyPrompt, lastActionResult, useToolCalling, visionContext)
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

                lastPrompt = prompt

                // ========== FOREGROUND BOOST ==========
                // Bring our activity to foreground during LLM inference.
                // Samsung's OneUI scheduler pins background processes to efficiency cores,
                // causing ~20x slowdown. Being foreground during inference restores full speed.
                if (screen.foregroundPackage != "com.runanywhere.agent") {
                    bringToForeground()
                    delay(300)
                }

                // ========== LOCAL-FIRST LLM ROUTING ==========
                val response = getDecision(prompt, screenshotBase64, hasVisionContext) { event ->
                    emit(event)
                }

                // After inference, return to the target app if we came to foreground
                val targetPkg = screen.foregroundPackage
                if (targetPkg != null && targetPkg != "com.runanywhere.agent") {
                    val currentFg = screenParser.parse().foregroundPackage
                    if (currentFg == "com.runanywhere.agent") {
                        bringAppToForeground(targetPkg)
                        delay(500)
                    }
                }

                // Resolve any tool calls (sub-loop)
                Log.i(TAG, "Initial response type: ${response::class.simpleName}")
                val finalResponse = resolveToolCalls(response, prompt) { event -> emit(event) }
                Log.i(TAG, "After resolveToolCalls: ${finalResponse::class.simpleName}")

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
                    hasNavigatedAway = true

                    if (call.toolName == "ui_done") {
                        emit(AgentEvent.Speak("Task complete."))
                        emit(AgentEvent.Done("Goal achieved"))
                        return@flow
                    }

                    val stepElapsed = System.currentTimeMillis() - stepStart
                    emit(AgentEvent.Log("Step $step took ${stepElapsed / 1000}s"))
                    // Record step for export
                    _stepRecords.add(StepRecord(
                        step = step,
                        timestampMs = stepStart,
                        promptSnippet = lastPrompt.take(200),
                        rawOutput = call.toolName + "(${call.arguments})",
                        thinkingContent = null,
                        action = actionName,
                        durationMs = stepElapsed,
                        tokensPerSecond = 0.0,
                        outputTokens = 0,
                        inputTokens = 0,
                    ))

                    // Check timeout
                    if (System.currentTimeMillis() - startTime > MAX_DURATION_MS) {
                        emit(AgentEvent.Done("Max duration reached"))
                        return@flow
                    }

                    delay(STEP_DELAY_MS)
                    continue
                }

                // Legacy path: handle JSON-based UI actions (local model)
                Log.i(TAG, "Final response type: ${finalResponse::class.simpleName}")
                val decision = when (finalResponse) {
                    is LLMResponse.UIAction -> {
                        Log.i(TAG, "Parsing UIAction: ${finalResponse.json.take(100)}")
                        parseDecision(finalResponse.json)
                    }
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
                Log.i(TAG, "Decision: action=${decision.action}, index=${decision.elementIndex}, text=${decision.text}")

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
                hasNavigatedAway = true

                // Check for completion
                if (decision.action == "done") {
                    emit(AgentEvent.Speak("Task complete."))
                    emit(AgentEvent.Done("Goal achieved"))
                    return@flow
                }

                val stepElapsedLegacy = System.currentTimeMillis() - stepStart
                emit(AgentEvent.Log("Step $step took ${stepElapsedLegacy / 1000}s"))

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

    /**
     * Bring our activity to the foreground before LLM inference.
     * Samsung's OneUI scheduler pins background processes to efficiency cores,
     * causing ~20x slowdown for on-device LLM inference. Being foreground restores full speed.
     */
    private fun bringToForeground() {
        try {
            val intent = android.content.Intent(context, Class.forName("com.runanywhere.agent.MainActivity"))
            intent.flags = android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            Log.i(TAG, "Brought agent to foreground for inference")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to bring to foreground: ${e.message}")
        }
    }

    /**
     * Bring a target app back to the foreground after inference completes.
     * Multiple strategies because Samsung's PackageManager sometimes returns null
     * from getLaunchIntentForPackage() for apps like YouTube.
     */
    private fun bringAppToForeground(packageName: String) {
        try {
            // Strategy 0 (X-specific): preserve compose screen by targeting ComposerActivity directly.
            // X's main activity (singleTask) clears compose from the back stack when started.
            // ComposerActivity with SINGLE_TOP brings the existing compose instance to front instead.
            if (packageName == AppActions.Packages.TWITTER && xComposeMessage != null) {
                try {
                    val composeIntent = android.content.Intent().apply {
                        component = android.content.ComponentName(
                            "com.twitter.android",
                            "com.twitter.composer.ComposerActivity"
                        )
                        flags = android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(composeIntent)
                    Log.i(TAG, "Returned to X compose: ComposerActivity (SINGLE_TOP)")
                    return
                } catch (e: Exception) {
                    Log.w(TAG, "ComposerActivity bring-to-front failed: ${e.message}")
                    // Fall through to standard strategies
                }
            }

            // Strategy 1: Standard launch intent (works for most apps)
            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.flags = android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                context.startActivity(launchIntent)
                Log.i(TAG, "Returned to target app: $packageName (launch intent)")
                return
            }

            // Strategy 2: Resolve MAIN/LAUNCHER intent manually
            val mainIntent = android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                addCategory(android.content.Intent.CATEGORY_LAUNCHER)
                setPackage(packageName)
            }
            val resolveInfo = context.packageManager.resolveActivity(mainIntent, 0)
            if (resolveInfo != null) {
                mainIntent.component = android.content.ComponentName(
                    resolveInfo.activityInfo.packageName,
                    resolveInfo.activityInfo.name
                )
                mainIntent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                        android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                context.startActivity(mainIntent)
                Log.i(TAG, "Returned to target app: $packageName (resolved main/launcher)")
                return
            }

            // Strategy 3: Shell command fallback (works even when PM returns null)
            Log.i(TAG, "Trying shell am start for $packageName")
            val process = Runtime.getRuntime().exec(
                arrayOf("am", "start", "-a", "android.intent.action.MAIN",
                    "-c", "android.intent.category.LAUNCHER", "-p", packageName)
            )
            process.waitFor()
            if (process.exitValue() == 0) {
                Log.i(TAG, "Returned to target app: $packageName (shell am start)")
            } else {
                Log.w(TAG, "Shell am start failed for $packageName (exit=${process.exitValue()})")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to bring app to foreground: ${e.message}")
        }
    }

    // ========== Smart Recovery ==========

    private enum class RecoveryResult { GOAL_ACHIEVED, ACTION_TAKEN, NO_ACTION }

    /**
     * Minimal recovery when the model gets stuck in a loop.
     * We intentionally keep this simple — the model should do the reasoning, not heuristics.
     * Only handles: (1) dismiss blocking dialogs, (2) scroll to reveal more elements.
     */
    private suspend fun trySmartRecovery(
        goal: String,
        screen: ScreenParser.ParsedScreen,
        step: Int,
        emitEvent: suspend (AgentEvent) -> Unit
    ): RecoveryResult {
        Log.i(TAG, "[RECOVERY] Loop detected at step $step")

        // Strategy 1: Dismiss common app dialogs/sign-in screens that block progress
        val dismissIndex = findDismissableDialog(screen.compactText)
        if (dismissIndex != null && screen.indexToCoords.containsKey(dismissIndex)) {
            emitEvent(AgentEvent.Log("[RECOVERY] Dismissing dialog at index $dismissIndex"))
            val tapResult = actionExecutor.execute(
                Decision("tap", elementIndex = dismissIndex),
                screen.indexToCoords
            )
            history.record("tap", "dismiss dialog", "Recovery: dismissed blocking dialog", tapResult.success)
            emitEvent(AgentEvent.Step(step, "tap (recovery)", "Dismissed dialog"))
            return RecoveryResult.ACTION_TAKEN
        }

        // Strategy 2: Scroll to reveal more elements
        emitEvent(AgentEvent.Log("[RECOVERY] Scrolling to find more elements"))
        val swipeResult = actionExecutor.execute(
            Decision("swipe", direction = "u"),
            screen.indexToCoords
        )
        history.record("swipe", "up", "Recovery: scroll to find elements", swipeResult.success)
        return RecoveryResult.ACTION_TAKEN
    }

    /**
     * Find a dismissable dialog/sign-in/welcome screen button.
     * Returns the index of a clickable element that can bypass the dialog.
     */
    private fun findDismissableDialog(compactText: String): Int? {
        val dismissLabels = listOf(
            "stay signed out", "no thanks", "skip", "not now", "maybe later",
            "dismiss", "close", "got it", "accept & continue", "accept", "i agree"
        )
        val lines = compactText.split("\n")
        for (label in dismissLabels) {
            for (line in lines) {
                if (!line.contains("[tap]")) continue
                if (line.lowercase().contains(label)) {
                    val indexMatch = Regex("^(\\d+):").find(line.trim())
                    if (indexMatch != null) {
                        return indexMatch.groupValues[1].toIntOrNull()
                    }
                }
            }
        }
        return null
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
            callLocalLLMWithTools(prompt, emitEvent)
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

    /** Only these tools are sent to local models to avoid context bloat and confusion. */
    private val essentialToolNames = setOf(
        "ui_tap", "ui_type", "ui_enter", "ui_swipe",
        "ui_back", "ui_home", "ui_open_app", "ui_done"
    )

    /**
     * Call local LLM with essential UI tools.
     * Uses streaming generation so tokens appear live in the UI.
     * Emits ThinkingToken events per token and PerfMetrics after completion.
     */
    private suspend fun callLocalLLMWithTools(
        prompt: String,
        emitEvent: (suspend (AgentEvent) -> Unit)? = null,
    ): LLMResponse {
        val allTools = toolRegistry.getDefinitions()
        val essentialTools = allTools.filter { it.name in essentialToolNames }
        val hasTools = essentialTools.isNotEmpty()

        // Larger models get richer prompts and more reasoning tokens
        val isLargeModel = activeModelId.contains("8b", ignoreCase = true) ||
                activeModelId.contains("4b", ignoreCase = true)
        val systemPrompt = if (isLargeModel) {
            SystemPrompts.TOOL_CALLING_SYSTEM_PROMPT
        } else {
            SystemPrompts.COMPACT_SYSTEM_PROMPT
        }
        val maxTokens = when {
            activeModelId.contains("8b", ignoreCase = true) -> 512
            activeModelId.contains("4b", ignoreCase = true) -> 512
            else -> 256
        }

        val options = if (hasTools) {
            LLMGenerationOptions(
                maxTokens = maxTokens,
                temperature = 0.0f,
                topP = 0.95f,
                streamingEnabled = true,
                systemPrompt = systemPrompt,
                structuredOutput = null
            )
        } else {
            LLMGenerationOptions(
                maxTokens = 32,
                temperature = 0.0f,
                topP = 0.95f,
                streamingEnabled = true,
                systemPrompt = systemPrompt,
                structuredOutput = StructuredOutputConfig(
                    typeName = "Act",
                    includeSchemaInPrompt = true,
                    jsonSchema = SystemPrompts.DECISION_SCHEMA
                )
            )
        }

        // Qwen3 models use <think> chain-of-thought by default which consumes the entire
        // token budget. Appending /no_think disables this and produces direct tool calls.
        val noThinkSuffix = if (activeModelId.contains("qwen", ignoreCase = true)) "\n/no_think" else ""

        val fullPrompt = if (hasTools) {
            prompt + "\n" + ToolPromptFormatter.formatCompactForLocal(essentialTools) + noThinkSuffix
        } else {
            prompt + noThinkSuffix
        }

        return try {
            // Boost thread priority for inference (mitigates Samsung background CPU throttling)
            val prevPriority = android.os.Process.getThreadPriority(android.os.Process.myTid())
            try {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
            } catch (_: Exception) {}

            val metrics: LLMGenerationResult
            val text: String
            try {
                val streamResult = withContext(Dispatchers.Default) {
                    RunAnywhere.generateStreamWithMetrics(fullPrompt, options)
                }
                // Collect tokens and emit them live for the streaming overlay
                val sb = StringBuilder()
                streamResult.stream.collect { token ->
                    sb.append(token)
                    emitEvent?.invoke(AgentEvent.ThinkingToken(token))
                }
                metrics = streamResult.result.await()
                text = metrics.text.ifBlank { sb.toString() }
            } finally {
                try { android.os.Process.setThreadPriority(prevPriority) } catch (_: Exception) {}
            }

            Log.i(TAG, "LLM raw output (${text.length} chars): $text")

            // Emit perf metrics so the UI and export log can capture them
            val currentStep = _stepRecords.size + 1
            emitEvent?.invoke(AgentEvent.PerfMetrics(
                step = currentStep,
                tokensPerSecond = metrics.tokensPerSecond,
                outputTokens = metrics.tokensUsed,
                inputTokens = metrics.inputTokens,
                latencyMs = metrics.latencyMs,
                thinkingContent = metrics.thinkingContent,
            ))
            val perfLine = buildString {
                append("[PERF] ")
                append("%.1f tok/s".format(metrics.tokensPerSecond))
                append(" | out:${metrics.tokensUsed}")
                append(" | in:${metrics.inputTokens}")
                append(" | %.1fs".format(metrics.latencyMs / 1000.0))
                metrics.thinkingContent?.let { append(" | think:${it.length}ch") }
            }
            Log.i(TAG, perfLine)
            emitEvent?.invoke(AgentEvent.Log(perfLine))

            // Check for tool calls first (only when tools are registered)
            if (hasTools && ToolCallParser.containsToolCall(text)) {
                val calls = ToolCallParser.parse(text)
                Log.i(TAG, "Parsed ${calls.size} tool calls: ${calls.map { it.toolName }}")
                if (calls.isNotEmpty()) {
                    return LLMResponse.ToolCalls(calls)
                }
            }

            // Otherwise treat as UI action
            Log.i(TAG, "No tool call found, treating as UI action")
            LLMResponse.UIAction(text)
        } catch (e: Exception) {
            Log.e(TAG, "LLM call failed: ${e.message}", e)
            LLMResponse.Error(e.message ?: "LLM call failed")
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
                callLocalLLMWithTools(originalPrompt + toolResultText, emitEvent)
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
        Log.i(TAG, "parseDecision input: $cleaned")

        // Try parsing as JSON
        try {
            val obj = JSONObject(cleaned)
            val d = extractDecision(obj)
            Log.i(TAG, "Parsed JSON decision: ${d.action}")
            return d
        } catch (_: JSONException) {
            Log.i(TAG, "Not valid JSON, trying regex extraction")
        }

        // Try extracting JSON from text
        val matcher = Pattern.compile("\\{.*?\\}", Pattern.DOTALL).matcher(cleaned)
        if (matcher.find()) {
            try {
                val d = extractDecision(JSONObject(matcher.group()))
                Log.i(TAG, "Extracted JSON decision: ${d.action}")
                return d
            } catch (_: JSONException) {}
        }

        // Fallback: heuristic parsing
        Log.i(TAG, "Falling back to heuristic parsing")
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

    private data class PreLaunchResult(
        val message: String,
        val packageName: String,
        val didSearch: Boolean = false,
        /** When true, goal is complete without verifying foreground app (e.g., timer set with skipUi). */
        val goalComplete: Boolean = false
    )

    /**
     * Pre-launch: analyze the goal and open the target app directly via intent.
     */
    private fun preLaunchApp(goal: String): PreLaunchResult? {
        val goalLower = goal.lowercase()

        return when {
            goalLower.contains("youtube") -> {
                val searchQuery = extractSearchQuery(goalLower, "youtube")
                if (searchQuery != null) {
                    AppActions.openYouTubeSearch(context, searchQuery)
                    PreLaunchResult("Pre-launched YouTube with search: $searchQuery", AppActions.Packages.YOUTUBE, didSearch = true)
                } else {
                    AppActions.openApp(context, AppActions.Packages.YOUTUBE)
                    PreLaunchResult("Pre-launched YouTube", AppActions.Packages.YOUTUBE)
                }
            }
            goalLower.contains("chrome") || goalLower.contains("browser") -> {
                // Check if the goal is just "open Chrome" or "go to google.com" (Chrome's default homepage)
                val isGoToGoogle = goalLower.contains("google.com") || goalLower.contains("google .com")
                if (isGoToGoogle) {
                    // Chrome's homepage is google.com — opening Chrome achieves the goal
                    AppActions.openApp(context, AppActions.Packages.CHROME)
                    PreLaunchResult("Pre-launched Chrome (google.com is homepage)", AppActions.Packages.CHROME, didSearch = true)
                } else {
                    AppActions.openApp(context, AppActions.Packages.CHROME)
                    PreLaunchResult("Pre-launched Chrome", AppActions.Packages.CHROME)
                }
            }
            // X (Twitter) — match "open x", "x app", "twitter" but not random "x" in words
            goalLower.contains("twitter") || Regex("\\bopen\\s+x\\b|\\bx\\s+app\\b|\\bopen\\s+x\\s|\\btap.*\\bx\\b|\\bpost.*\\bon\\s+x\\b|\\bx.*\\bpost\\b|\\btweet\\b").containsMatchIn(goalLower) -> {
                val tweetText = extractTweetText(goal)
                if (tweetText != null && (goalLower.contains("post") || goalLower.contains("tweet"))) {
                    AppActions.openXCompose(context, tweetText)
                    xComposeMessage = tweetText
                    PreLaunchResult("Pre-launched X compose: ${tweetText.take(40)}", AppActions.Packages.TWITTER)
                } else {
                    AppActions.openX(context)
                    PreLaunchResult("Pre-launched X (Twitter)", AppActions.Packages.TWITTER)
                }
            }
            goalLower.contains("whatsapp") -> {
                AppActions.openApp(context, AppActions.Packages.WHATSAPP)
                PreLaunchResult("Pre-launched WhatsApp", AppActions.Packages.WHATSAPP)
            }
            goalLower.contains("gmail") -> {
                AppActions.openApp(context, AppActions.Packages.GMAIL)
                PreLaunchResult("Pre-launched Gmail", AppActions.Packages.GMAIL)
            }
            goalLower.contains("spotify") -> {
                val searchQuery = extractSearchQuery(goalLower, "spotify")
                if (searchQuery != null) {
                    AppActions.openSpotifySearch(context, searchQuery)
                    PreLaunchResult("Pre-launched Spotify with search: $searchQuery", AppActions.Packages.SPOTIFY, didSearch = true)
                } else {
                    AppActions.openApp(context, AppActions.Packages.SPOTIFY)
                    PreLaunchResult("Pre-launched Spotify", AppActions.Packages.SPOTIFY)
                }
            }
            goalLower.contains("maps") || goalLower.contains("navigate to") || goalLower.contains("directions to") -> {
                AppActions.openApp(context, AppActions.Packages.MAPS)
                PreLaunchResult("Pre-launched Maps", AppActions.Packages.MAPS)
            }
            goalLower.contains("timer") -> {
                val seconds = parseTimerDuration(goalLower)
                if (seconds != null) {
                    val label = Regex("(?:called|named|labeled)\\s+[\"']?(.+?)[\"']?$").find(goalLower)?.groupValues?.get(1)
                    AppActions.setTimer(context, seconds, label, skipUi = true)
                    val display = formatDuration(seconds)
                    PreLaunchResult("Set timer for $display", AppActions.Packages.CLOCK, goalComplete = true)
                } else {
                    AppActions.openClock(context)
                    PreLaunchResult("Pre-launched Clock (timer)", AppActions.Packages.CLOCK)
                }
            }
            goalLower.contains("alarm") -> {
                val time = parseAlarmTime(goalLower)
                if (time != null) {
                    AppActions.setAlarm(context, time.first, time.second, skipUi = true)
                    val display = String.format(Locale.ROOT, "%d:%02d", time.first, time.second)
                    PreLaunchResult("Set alarm for $display", AppActions.Packages.CLOCK, goalComplete = true)
                } else {
                    AppActions.openClock(context)
                    PreLaunchResult("Pre-launched Clock (alarm)", AppActions.Packages.CLOCK)
                }
            }
            goalLower.contains("clock") -> {
                AppActions.openClock(context)
                PreLaunchResult("Pre-launched Clock", AppActions.Packages.CLOCK)
            }
            goalLower.contains("note") || goalLower.contains("write a note") || goalLower.contains("take a note") -> {
                AppActions.openNotes(context)
                PreLaunchResult("Pre-launched Notes", AppActions.Packages.NOTES_SAMSUNG)
            }
            goalLower.contains("calculator") || goalLower.contains("calculate") -> {
                val success = AppActions.openApp(context, AppActions.Packages.CALCULATOR)
                    || AppActions.openApp(context, AppActions.Packages.CALCULATOR_SAMSUNG)
                if (success) {
                    PreLaunchResult("Pre-launched Calculator", AppActions.Packages.CALCULATOR)
                } else null
            }
            goalLower.contains("camera") || goalLower.contains("photo") || goalLower.contains("picture") -> {
                AppActions.openCamera(context)
                PreLaunchResult("Pre-launched Camera", "com.android.camera")
            }
            goalLower.contains("settings") -> {
                // Try to open a specific settings sub-page directly
                val settingType = when {
                    goalLower.contains("wifi") || goalLower.contains("wi-fi") -> "wifi"
                    goalLower.contains("bluetooth") -> "bluetooth"
                    goalLower.contains("display") || goalLower.contains("brightness") -> "display"
                    goalLower.contains("sound") || goalLower.contains("volume") || goalLower.contains("ringtone") -> "sound"
                    goalLower.contains("battery") -> "battery"
                    goalLower.contains("location") || goalLower.contains("gps") -> "location"
                    goalLower.contains("notification") -> "notification"
                    goalLower.contains("storage") -> "storage"
                    goalLower.contains("security") || goalLower.contains("privacy") -> "security"
                    goalLower.contains("accessibility") -> "accessibility"
                    goalLower.contains("about") || goalLower.contains("phone info") -> "about"
                    goalLower.contains("developer") || goalLower.contains("dev options") -> "developer"
                    goalLower.contains("date") || goalLower.contains("time") -> "date"
                    goalLower.contains("language") -> "language"
                    else -> null
                }
                if (settingType != null) {
                    actionExecutor.openSettings(settingType)
                    // Only mark goal complete if the user just wants to open/navigate to the settings page.
                    // If they want to perform an action (enable, disable, toggle, etc.), keep the agent loop running.
                    val isNavigationOnly = Regex(
                        "\\b(open|go\\s+to|show|navigate\\s+to|launch|view|pull\\s+up|bring\\s+up)\\b"
                    ).containsMatchIn(goalLower) && !Regex(
                        "\\b(enable|disable|turn\\s+on|turn\\s+off|toggle|change|set|configure|switch|activate|deactivate|connect|disconnect|pair|adjust|increase|decrease|lower|raise)\\b"
                    ).containsMatchIn(goalLower)
                    PreLaunchResult("Pre-launched $settingType Settings", "com.android.settings", goalComplete = isNavigationOnly)
                } else {
                    actionExecutor.openSettings()
                    PreLaunchResult("Pre-launched Settings", "com.android.settings")
                }
            }
            else -> null
        }
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

    /**
     * Extract tweet/post text from the goal string.
     * Handles: "post Hi from RunAnywhere on X", "tweet 'Hello' on Twitter", etc.
     */
    private fun extractTweetText(goal: String): String? {
        // Pattern 1: post/tweet <text> on x/twitter (with optional quotes)
        Regex("""(?:post|tweet)\s+['"]?(.+?)['"]?\s+on\s+(?:x|twitter)""", RegexOption.IGNORE_CASE).find(goal)?.let {
            val text = it.groupValues[1].trim()
            if (text.isNotEmpty()) return text
        }
        // Pattern 2: quoted text when goal contains post/tweet keyword
        val goalLower = goal.lowercase()
        if (goalLower.contains("post") || goalLower.contains("tweet")) {
            Regex("""['"]([^'"]+)['"]""").find(goal)?.let {
                val text = it.groupValues[1].trim()
                if (text.isNotEmpty()) return text
            }
        }
        return null
    }

    /**
     * Find the index of X's POST submit button in the compact element list.
     * Returns the element index of "POST (Button) [tap]" or null if not found.
     */
    private fun findPostButtonIndex(compactText: String): Int? {
        for (line in compactText.split("\n")) {
            if (!line.contains("[tap]")) continue
            val lineLower = line.lowercase()
            if (lineLower.contains("post") && lineLower.contains("button")) {
                val indexMatch = Regex("^(\\d+):").find(line.trim())
                if (indexMatch != null) return indexMatch.groupValues[1].toIntOrNull()
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

    /**
     * Parse a timer duration from natural language.
     * Supports: "5 minutes", "30 seconds", "1 hour and 30 minutes", "1h30m", etc.
     * Returns total seconds or null if unparseable.
     */
    private fun parseTimerDuration(goalLower: String): Int? {
        var totalSeconds = 0

        // Match "X hour(s)"
        Regex("(\\d+)\\s*(?:hour|hr|h)").find(goalLower)?.let {
            totalSeconds += it.groupValues[1].toInt() * 3600
        }
        // Match "X minute(s)"
        Regex("(\\d+)\\s*(?:minute|min|m(?!s|onth))").find(goalLower)?.let {
            totalSeconds += it.groupValues[1].toInt() * 60
        }
        // Match "X second(s)"
        Regex("(\\d+)\\s*(?:second|sec|s(?!et|ound))").find(goalLower)?.let {
            totalSeconds += it.groupValues[1].toInt()
        }

        return if (totalSeconds > 0) totalSeconds else null
    }

    /** Format seconds as human-readable duration (e.g., "5 minutes", "1 hour 30 minutes"). */
    private fun formatDuration(totalSeconds: Int): String {
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        val parts = mutableListOf<String>()
        if (hours > 0) parts.add("$hours hour${if (hours > 1) "s" else ""}")
        if (minutes > 0) parts.add("$minutes minute${if (minutes > 1) "s" else ""}")
        if (seconds > 0 && hours == 0) parts.add("$seconds second${if (seconds > 1) "s" else ""}")
        return parts.joinToString(" ")
    }

    /**
     * Parse an alarm time from natural language.
     * Supports: "7:30 am", "7:30", "7 am", "at 7", "for 7:30 pm", etc.
     * Returns (hour, minute) in 24h format or null.
     */
    private fun parseAlarmTime(goalLower: String): Pair<Int, Int>? {
        // Match "H:MM am/pm" or "H:MM"
        Regex("(\\d{1,2}):(\\d{2})\\s*(am|pm)?").find(goalLower)?.let { match ->
            var hour = match.groupValues[1].toInt()
            val minute = match.groupValues[2].toInt()
            val ampm = match.groupValues[3]
            if (ampm == "pm" && hour < 12) hour += 12
            if (ampm == "am" && hour == 12) hour = 0
            if (hour in 0..23 && minute in 0..59) return Pair(hour, minute)
        }
        // Match "H am/pm"
        Regex("(\\d{1,2})\\s*(am|pm)").find(goalLower)?.let { match ->
            var hour = match.groupValues[1].toInt()
            val ampm = match.groupValues[2]
            if (ampm == "pm" && hour < 12) hour += 12
            if (ampm == "am" && hour == 12) hour = 0
            if (hour in 0..23) return Pair(hour, 0)
        }
        return null
    }

    private fun heuristicDecision(text: String): Decision {
        val lower = text.lowercase()
        Log.i(TAG, "Heuristic parsing text: $lower")

        // Strip <think> tags before heuristic matching — reasoning text often
        // mentions actions like "home screen" or "go back" which causes false matches.
        val stripped = lower.replace(Regex("<think>.*?</think>", RegexOption.DOT_MATCHES_ALL), "").trim()
        val match = stripped.ifEmpty { lower }

        return when {
            match.contains("done") || match.contains("complete") || match.contains("achieved") -> Decision("done")
            match.contains("back") -> Decision("back")
            match.contains("go home") || match.contains("press home") || match.contains("\"home\"") -> Decision("home")
            match.contains("enter") -> Decision("enter")
            match.contains("swipe") || match.contains("scroll") -> {
                val dir = when {
                    match.contains("up") -> "u"
                    match.contains("down") -> "d"
                    match.contains("left") -> "l"
                    match.contains("right") -> "r"
                    else -> "u"
                }
                Decision("swipe", direction = dir)
            }
            match.contains("tap") || match.contains("click") -> {
                val idx = Regex("\\d+").find(match)?.value?.toIntOrNull() ?: 0
                Decision("tap", elementIndex = idx)
            }
            match.contains("type") -> {
                val textMatch = Regex("\"([^\"]+)\"").find(match)
                Decision("type", text = textMatch?.groupValues?.getOrNull(1) ?: "")
            }
            else -> {
                Log.w(TAG, "Unrecognized LLM output, defaulting to wait")
                Decision("wait")
            }
        }
    }
}
