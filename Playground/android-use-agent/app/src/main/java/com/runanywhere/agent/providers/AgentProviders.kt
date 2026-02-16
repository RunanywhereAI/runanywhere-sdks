package com.runanywhere.agent.providers

import com.runanywhere.agent.kernel.Decision

/**
 * Core abstraction for agent LLM reasoning.
 *
 * Decides the next action given screen state and history.
 * Handles utility tool calls (weather, time, math, etc.) internally
 * via the RunAnywhere SDK's tool calling system.
 *
 * Implementations:
 * - [OnDeviceLLMProvider] — runs on-device via RunAnywhere SDK (llama.cpp / ONNX)
 *
 * To add a cloud provider, implement this interface with your API client.
 */
interface AgentLLMProvider {

    /**
     * Decide the next UI action given the current reasoning context.
     * Utility tool calls (e.g., get_weather) are resolved internally
     * before returning the final UI action decision.
     */
    suspend fun decideNextAction(context: ReasoningContext): AgentDecision

    /**
     * Generate an optional step-by-step plan for the goal.
     * Returns null if planning is not supported or fails.
     */
    suspend fun generatePlan(goal: String): PlanResult?

    /**
     * Ensure the model is downloaded and loaded, ready for inference.
     */
    suspend fun ensureModelReady()

    /** Set the active model by ID. */
    fun setModel(modelId: String)

    /** Get the active model ID. */
    fun getModel(): String
}

/**
 * Context provided to the LLM for decision making.
 * Built by the kernel each step from screen state and action history.
 */
data class ReasoningContext(
    /** The user's stated goal. */
    val goal: String,
    /** Compact indexed list of interactive UI elements on screen. */
    val screenElements: String,
    /** Formatted recent action history for context. */
    val historyPrompt: String,
    /** Human-readable result of the last executed action. */
    val lastActionResult: String?,
    /** Optional VLM-generated screen description (null when no VLM available). */
    val visionContext: String?,
    /** True if the agent is repeating the same action. */
    val isLoopDetected: Boolean,
    /** True if a recent action failed. */
    val hasRecentFailure: Boolean
)

/**
 * The agent's decision — a sealed hierarchy for type-safe action handling.
 */
sealed class AgentDecision {
    /** Execute a UI action (tap, type, swipe, open app, etc.). */
    data class UIAction(val decision: Decision) : AgentDecision()
    /** The goal has been achieved. */
    data class Done(val reason: String) : AgentDecision()
    /** An error occurred during reasoning. */
    data class Error(val message: String) : AgentDecision()
}

/**
 * Result of a planning step.
 */
data class PlanResult(
    val steps: List<String>,
    val successCriteria: String?
)
