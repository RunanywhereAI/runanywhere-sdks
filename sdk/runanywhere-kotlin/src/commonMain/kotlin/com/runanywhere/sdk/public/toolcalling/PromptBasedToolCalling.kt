package com.runanywhere.sdk.public.toolcalling

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Prompt-based tool calling orchestrator.
 *
 * This service coordinates the entire flow of prompt-based tool calling:
 * 1. Build system prompt with tool definitions and examples
 * 2. Send prompt to LLM
 * 3. Parse response to extract tool call or regular text
 * 4. Validate and deduplicate tool calls
 * 5. Return result
 *
 * This approach is more reliable than grammar-based constrained generation
 * for small models (0.5B-1.5B parameters) and doesn't suffer from crashes.
 */
class PromptBasedToolCalling(
    private val runAnywhere: RunAnywhere,
    private val maxRetries: Int = 2
) {
    private val logger = SDKLogger("PromptBasedToolCalling")
    private val promptBuilder = PromptBuilder()
    private val responseParser = ResponseParser()
    private val deduplicator = Deduplicator()

    /**
     * Generate a response with tool calling support using prompt-based approach.
     *
     * @param userMessage The user's message/query
     * @param tools List of available tools
     * @param options Generation options (temperature, maxTokens, etc.)
     * @return ToolCallResult containing tool calls or regular response
     */
    suspend fun generateWithTools(
        userMessage: String,
        tools: List<Tool>,
        options: RunAnywhereGenerationOptions? = null
    ): ToolCallResult {
        logger.info("Starting prompt-based tool calling with ${tools.size} tools")

        if (tools.isEmpty()) {
            logger.warn("No tools provided, falling back to regular generation")
            return generateRegularResponse(userMessage, options)
        }

        // Build system prompt with tool definitions
        val systemPrompt = promptBuilder.buildSystemPrompt(tools)
        logger.debug("System prompt built (${systemPrompt.length} chars)")

        // Prepare the full prompt: system + user message
        val fullPrompt = buildFullPrompt(systemPrompt, userMessage)

        // Try generation with retries for invalid responses
        var retryCount = 0
        var lastError: String? = null

        while (retryCount <= maxRetries) {
            try {
                // Generate response from LLM
                val response = generateResponse(fullPrompt, options)
                logger.debug("LLM response: ${response.take(200)}...")

                // Parse the response
                when (val parseResult = responseParser.parseResponse(response, tools)) {
                    is ParseResult.ToolCall -> {
                        // Check for duplicates
                        if (deduplicator.isDuplicate(parseResult.name, parseResult.arguments)) {
                            logger.warn("Duplicate tool call detected, treating as regular response")
                            return ToolCallResult(
                                success = true,
                                text = "I've already attempted that action. Let me try a different approach: $response",
                                toolCalls = emptyList(),
                                mode = ToolCallingMode.PROMPT_BASED
                            )
                        }

                        // Valid, non-duplicate tool call
                        logger.info("✅ Tool call successful: ${parseResult.name}")
                        return ToolCallResult(
                            success = true,
                            text = null,
                            toolCalls = listOf(
                                ToolCall(
                                    id = generateToolCallId(),
                                    name = parseResult.name,
                                    arguments = parseResult.arguments
                                )
                            ),
                            mode = ToolCallingMode.PROMPT_BASED
                        )
                    }

                    is ParseResult.RegularResponse -> {
                        // Model decided not to use a tool, return as regular response
                        logger.info("✅ Regular response (no tool call needed)")
                        return ToolCallResult(
                            success = true,
                            text = parseResult.text,
                            toolCalls = emptyList(),
                            mode = ToolCallingMode.PROMPT_BASED
                        )
                    }

                    is ParseResult.InvalidFormat -> {
                        lastError = parseResult.reason
                        logger.warn("Invalid format (attempt ${retryCount + 1}/$maxRetries): ${parseResult.reason}")

                        if (retryCount < maxRetries) {
                            retryCount++
                            // Add error feedback to help model self-correct
                            val errorFeedback = buildErrorFeedback(parseResult.reason, parseResult.rawResponse)
                            // We could append this to the conversation and retry, but for now just retry
                            continue
                        }
                    }

                    is ParseResult.UnknownTool -> {
                        lastError = "Unknown tool: ${parseResult.attemptedName}"
                        logger.warn("Unknown tool (attempt ${retryCount + 1}/$maxRetries): ${parseResult.attemptedName}")

                        if (retryCount < maxRetries) {
                            retryCount++
                            continue
                        }
                    }

                    is ParseResult.InvalidArguments -> {
                        lastError = parseResult.reason
                        logger.warn("Invalid arguments (attempt ${retryCount + 1}/$maxRetries): ${parseResult.reason}")

                        if (retryCount < maxRetries) {
                            retryCount++
                            continue
                        }
                    }
                }

                // If we get here, we've exhausted retries
                break

            } catch (e: Exception) {
                logger.error("Error during generation: ${e.message}")
                lastError = e.message

                if (retryCount < maxRetries) {
                    retryCount++
                    continue
                }
                break
            }
        }

        // All retries exhausted, return failure
        logger.error("❌ Tool calling failed after $retryCount retries")
        return ToolCallResult(
            success = false,
            text = "Failed to generate valid tool call: ${lastError ?: "Unknown error"}",
            toolCalls = emptyList(),
            mode = ToolCallingMode.PROMPT_BASED
        )
    }

    /**
     * Build the full prompt combining system instructions and user message.
     */
    private fun buildFullPrompt(systemPrompt: String, userMessage: String): String {
        return """
        |$systemPrompt
        |
        |User: $userMessage
        |Assistant:
        """.trimMargin()
    }

    /**
     * Generate a response from the LLM using the loaded model's service directly.
     */
    private suspend fun generateResponse(
        prompt: String,
        options: RunAnywhereGenerationOptions?
    ): String {
        // Get the currently loaded model from the generation service
        val serviceContainer = ServiceContainer.shared
        val currentModel = serviceContainer.generationService.getCurrentModel()
            ?: throw IllegalStateException(
                "No model currently loaded. Please call RunAnywhere.loadModel(modelId) before using tool calling."
            )

        // Cast service to LLMService
        val llmService = currentModel.service as? com.runanywhere.sdk.components.llm.LLMService
            ?: throw IllegalStateException("Current model's service is not an LLMService")

        val effectiveOptions = options ?: RunAnywhereGenerationOptions()
        return llmService.generate(prompt, effectiveOptions).trim()
    }

    /**
     * Generate a response without tool calling (fallback).
     */
    private suspend fun generateRegularResponse(
        userMessage: String,
        options: RunAnywhereGenerationOptions?
    ): ToolCallResult {
        val response = generateResponse(userMessage, options)
        return ToolCallResult(
            success = true,
            text = response,
            toolCalls = emptyList(),
            mode = ToolCallingMode.PROMPT_BASED
        )
    }

    /**
     * Build error feedback message for the model to self-correct.
     */
    private fun buildErrorFeedback(reason: String, rawResponse: String): String {
        return """
        |Your previous response was invalid: $reason
        |
        |You provided: $rawResponse
        |
        |Please provide a valid JSON response with exactly these keys: "name" and "arguments"
        |Or respond with regular text if no tool is needed.
        """.trimMargin()
    }

    /**
     * Generate a unique ID for a tool call.
     */
    private fun generateToolCallId(): String {
        return "call_${System.currentTimeMillis()}_${(Math.random() * 1000).toInt()}"
    }

    /**
     * Clear deduplication history (useful when starting a new conversation).
     */
    fun clearHistory() {
        logger.debug("Clearing tool calling history")
        deduplicator.clear()
    }
}
