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
 * Provides grammar-based constrained generation for reliable tool calling.
 * Uses llama.cpp's GBNF grammar to guarantee valid JSON output.
 *
 * Example usage:
 * ```kotlin
 * // Define tools
 * val weatherTool = createTool("get_weather", "Get weather for a location") {
 *     stringParameter("location", "City name", required = true)
 *     stringParameter("units", "celsius or fahrenheit", required = false)
 * }
 *
 * // Generate with tools
 * val result = RunAnywhere.generateWithTools(
 *     prompt = "What's the weather in Tokyo?",
 *     tools = listOf(weatherTool)
 * )
 *
 * // Execute tools
 * result.toolCalls.forEach { call ->
 *     when (call.name) {
 *         "get_weather" -> {
 *             val location = call.arguments["location"]
 *             val weather = fetchWeather(location)
 *             println("Weather: $weather")
 *         }
 *     }
 * }
 * ```
 */

private val logger = SDKLogger("RunAnywhereToolCalling")

/**
 * Generate text with tool calling support
 *
 * Uses grammar-based constrained generation to ensure 100% valid JSON output.
 * The grammar is automatically generated from the tool definitions.
 *
 * Tools can be provided either:
 * 1. Via the `tools` parameter (recommended for explicit tool lists)
 * 2. Via `options.tools` (recommended when tools are part of generation config)
 *
 * @param prompt User prompt/question
 * @param tools List of available tools (optional if provided in options)
 * @param options Generation options (can include tools parameter)
 * @return Tool call result containing detected tool calls and response text
 * @throws IllegalStateException if SDK not initialized or LLM service not available
 */
suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    tools: List<Tool>? = null,
    options: RunAnywhereGenerationOptions? = null
): ToolCallResult {
    val effectiveTools = tools ?: options?.tools ?: emptyList()
    logger.info("generateWithTools() called with ${effectiveTools.size} tools")

    // Ensure SDK is initialized
    if (!this.isInitialized) {
        throw IllegalStateException("RunAnywhere SDK not initialized. Call initialize() first.")
    }

    // Get LLM service from service container
    val serviceContainer = ServiceContainer.shared
    val llmComponent = serviceContainer.llmComponent
        ?: throw IllegalStateException("LLM component not available")

    // Access service through public getter
    val llmService = try {
        llmComponent.getService() as? LlamaCppService
    } catch (e: Exception) {
        null
    } ?: throw IllegalStateException("LLM service not initialized or not available")

    // Validate tools
    if (effectiveTools.isEmpty()) {
        logger.warn("No tools provided for generateWithTools()")
    }

    logger.info("Using LlamaCppService for grammar-based tool calling")

    // Delegate to LlamaCppService
    return llmService.generateWithTools(prompt, tools, options)
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
