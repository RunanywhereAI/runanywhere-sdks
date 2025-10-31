@file:JvmName("RunAnywhereToolCalling")

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.llm.llamacpp.LlamaCppService
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Tool Calling Extensions for RunAnywhere SDK
 *
 * ⚠️ DEPRECATED: Grammar-based tool calling (see issue #182)
 *
 * The grammar-based approach using llama.cpp's GBNF has been deprecated due to
 * persistent SIGABRT crashes in the grammar stack (llama.cpp bugs unfixed as of Oct 2025).
 *
 * Current status:
 * - Grammar implementation: Commented out (crashes after ~10 tokens)
 * - Production approach: Prompt-based tool calling with few-shot examples
 * - Success rate: 85-95% (vs 70-85% with crashes for grammar)
 *
 * See:
 * - Issue #182: Grammar implementation investigation and future plans
 * - GRAMMAR_IMPLEMENTATION_NOTES.md: Full 40+ hour debugging investigation
 * - prompt_based_tool_calling_implementation.md: Current production approach
 *
 * TODO: Re-enable grammar when upstream llama.cpp fixes are available
 */

private val logger = SDKLogger("RunAnywhereToolCalling")

/**
 * Generate text with tool calling support using grammar-based constrained generation
 *
 * ⚠️ DEPRECATED: This function is commented out due to SIGABRT crashes (see issue #182)
 *
 * The grammar-based approach crashes after ~10 tokens due to llama.cpp grammar stack bugs.
 * This will be re-enabled once upstream llama.cpp fixes are available.
 *
 * For production use, please use the prompt-based tool calling approach instead.
 * See: prompt_based_tool_calling_implementation.md
 *
 * @param prompt User prompt/question
 * @param tools List of available tools (optional if provided in options)
 * @param options Generation options (can include tools parameter)
 * @return Tool call result containing detected tool calls and response text
 * @throws UnsupportedOperationException Always throws - this function is deprecated
 */
@Deprecated(
    message = "Grammar-based tool calling crashes with SIGABRT. See issue #182. Use prompt-based approach instead.",
    level = DeprecationLevel.ERROR
)
suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    tools: List<Tool>? = null,
    options: RunAnywhereGenerationOptions? = null
): ToolCallResult {
    throw UnsupportedOperationException(
        "Grammar-based tool calling is deprecated due to crashes (issue #182). " +
        "Use prompt-based approach instead. See: prompt_based_tool_calling_implementation.md"
    )

    /* COMMENTED OUT - Grammar-based implementation (issue #182)
    val effectiveTools = tools ?: options?.tools ?: emptyList()
    logger.info("generateWithTools() called with ${effectiveTools.size} tools")

    // Get the currently loaded model from the generation service
    // This is the model that was loaded via RunAnywhere.loadModel()
    val serviceContainer = ServiceContainer.shared
    val currentModel = serviceContainer.generationService.getCurrentModel()
    logger.info("Current model: ${currentModel?.model?.id}")

    if (currentModel == null) {
        throw IllegalStateException(
            "No model currently loaded. Please call RunAnywhere.loadModel(modelId) before using generateWithTools()."
        )
    }

    // Get the LLM service from the loaded model
    val llmService = currentModel.service
    logger.info("Retrieved LLM service from loaded model: ${llmService?.javaClass?.name}")

    val llamaCppService = try {
        llmService as? LlamaCppService
    } catch (e: Exception) {
        logger.error("Failed to cast service to LlamaCppService: ${e.message}")
        null
    } ?: throw IllegalStateException(
        "LLM service is not a LlamaCppService. " +
        "Service type: ${llmService?.javaClass?.name}. " +
        "Tool calling is currently only supported with llama.cpp models."
    )

    // Validate tools
    if (effectiveTools.isEmpty()) {
        logger.warn("No tools provided for generateWithTools()")
    }

    logger.info("Using LlamaCppService for grammar-based tool calling")

    // Delegate to LlamaCppService
    return llamaCppService.generateWithTools(prompt, tools, options)
    */
}

/**
 * Create tool with DSL builder
 *
 * Example:
 * ```kotlin
 * val tool = createTool("search_web", "Search the internet") {
 *     stringParameter("query", "Search query", required = true)
 *     intParameter("max_results", "Max results to return", required = false)
 * }
 * ```
 */
fun createTool(
    name: String,
    description: String,
    builder: ToolBuilder.() -> Unit
): Tool {
    return tool(name, description, builder)
}
