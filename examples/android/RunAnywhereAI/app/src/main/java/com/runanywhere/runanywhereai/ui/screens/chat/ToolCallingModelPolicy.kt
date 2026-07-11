package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.ToolChoiceMode
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingOptions
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAToolDefinition

/** The generation path selected after tool/model compatibility preflight. */
internal enum class ToolCallingRoute {
    STANDARD_GENERATION,
    TOOL_GENERATION,
    BLOCKED,
}

internal data class ToolCallingAvailability(
    val isAvailable: Boolean,
    val message: String? = null,
)

internal data class ToolCallingPreflight(
    val route: ToolCallingRoute,
    val availability: ToolCallingAvailability,
)

internal data class ToolCallingExecutionPlan(
    val generationOptions: RALLMGenerationOptions,
    val toolOptions: RAToolCallingOptions,
    val toolChoice: ToolChoiceMode?,
    val forcedToolName: String?,
)

/**
 * App-level production gate for tool calling.
 *
 * Tool definitions, format instructions, the user prompt, and follow-up tool
 * results all share the model context window. The built-in catalog currently
 * produces an initial tools prompt just over 512 tokens, so 512-token models
 * fail before decoding. A published 1K window is the minimum supported tool
 * configuration; a separate execution budget below bounds output and loop
 * duration so that compatible small models remain responsive.
 */
internal object ToolCallingModelPolicy {
    const val MINIMUM_CONTEXT_TOKENS: Int = 1_024

    fun evaluate(model: RAModelInfo?): ToolCallingAvailability {
        if (model == null) {
            return unavailable("Choose a chat model before enabling Web & tools.")
        }
        val modelName = model.name.ifBlank { model.id.ifBlank { "The current model" } }
        val contextLength = model.context_length
        if (contextLength <= 0) {
            return unavailable(
                "$modelName does not publish a context-window capability. " +
                    "Choose a model with at least 1,024 tokens for Web & tools.",
            )
        }
        if (contextLength < MINIMUM_CONTEXT_TOKENS) {
            return unavailable(
                "$modelName has a $contextLength-token context window. " +
                    "Web & tools require at least 1,024 tokens. Choose a larger-context model.",
            )
        }
        return ToolCallingAvailability(isAvailable = true)
    }

    fun preflight(
        toolsRequested: Boolean,
        registeredToolCount: Int,
        model: RAModelInfo?,
    ): ToolCallingPreflight {
        if (!toolsRequested || registeredToolCount <= 0) {
            return ToolCallingPreflight(
                route = ToolCallingRoute.STANDARD_GENERATION,
                availability = evaluate(model),
            )
        }
        val availability = evaluate(model)
        return ToolCallingPreflight(
            route = if (availability.isAvailable) {
                ToolCallingRoute.TOOL_GENERATION
            } else {
                ToolCallingRoute.BLOCKED
            },
            availability = availability,
        )
    }

    private fun unavailable(message: String): ToolCallingAvailability =
        ToolCallingAvailability(isAvailable = false, message = message)
}

/** Tool-only limits applied after the normal chat response-budget policy. */
internal object ToolCallingExecutionPolicy {
    // The shared native loop stops the forced decision at the tool-call closing
    // marker with an independent 192-token safety ceiling. Final synthesis
    // remains concise while retaining enough room for an answer and source URL.
    const val MAX_FINAL_RESPONSE_TOKENS: Int = 96
    const val MAX_ITERATIONS: Int = 2
    const val TIMEOUT_MILLIS: Long = 45_000L
    const val PROGRESS_MESSAGE: String = "Using web & tools…"

    fun generationOptions(base: RALLMGenerationOptions): RALLMGenerationOptions =
        base.copy(
            max_tokens = base.max_tokens.takeIf { it in 1..MAX_FINAL_RESPONSE_TOKENS }
                ?: MAX_FINAL_RESPONSE_TOKENS,
            // Tool decisions must be reproducible. The native tool loop now
            // preserves temperature=0 as greedy instead of treating it as an
            // unset value and falling back to 0.8 sampling.
            temperature = 0f,
            top_p = 1f,
            disable_thinking = true,
        )

    fun plan(
        base: RALLMGenerationOptions,
        registeredTools: List<RAToolDefinition>,
    ): ToolCallingExecutionPlan {
        val generation = generationOptions(base)
        return ToolCallingExecutionPlan(
            generationOptions = generation,
            toolOptions = toolOptions(registeredTools, generation.max_tokens),
            // Commons recognizes an unambiguous explicit tool name in the
            // prompt and narrows the native decision there, so every SDK gets
            // the same behavior without app-side routing heuristics.
            toolChoice = null,
            forcedToolName = null,
        )
    }

    private fun toolOptions(
        tools: List<RAToolDefinition>,
        finalResponseMaxTokens: Int,
    ): RAToolCallingOptions = RAToolCallingOptions(
        tools = tools,
        max_iterations = MAX_ITERATIONS,
        max_tool_calls = MAX_ITERATIONS,
        max_tokens = finalResponseMaxTokens,
        temperature = 0f,
        auto_execute = true,
        keep_tools_available = false,
        disable_thinking = true,
    )
}
