package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.events.SDKGenerationEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.generation.StructuredOutputHandler
import com.runanywhere.sdk.models.Generatable
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import com.runanywhere.sdk.models.structuredoutput.StreamAccumulator
import com.runanywhere.sdk.models.structuredoutput.StreamToken
import com.runanywhere.sdk.models.structuredoutput.StructuredOutputStreamResult
import com.runanywhere.sdk.public.RunAnywhereSDK
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flow
import kotlin.reflect.KClass

/**
 * Structured Output extension APIs for RunAnywhere SDK
 * Mirrors iOS RunAnywhere+StructuredOutput.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+StructuredOutput.swift
 *
 * Provides two essential APIs:
 * 1. generateStructured<T>() - Non-streaming structured generation
 * 2. generateStructuredStream<T>() - Streaming structured generation with token accumulation
 */

private val structuredOutputLogger = SDKLogger("StructuredOutputAPI")

/**
 * Generate structured output that conforms to a Generatable type (non-streaming)
 * Mirrors iOS generateStructured(_:prompt:options:) (Lines 96-149)
 *
 * This is a convenience inline reified version that wraps the interface method.
 *
 * @param T The type to generate (must conform to Generatable)
 * @param prompt The prompt to generate from
 * @param options Generation options (structured output config will be added automatically)
 * @return The generated object of the specified type
 */
suspend inline fun <reified T : Generatable> RunAnywhereSDK.generateStructured(
    prompt: String,
    options: RunAnywhereGenerationOptions? = null
): T {
    return generateStructured(T::class, prompt, options)
}

/**
 * Generate structured output with streaming support
 * Mirrors iOS generateStructuredStream(_:content:options:) (Lines 157-254)
 *
 * @param type The type to generate (must conform to Generatable)
 * @param content The content to generate from (e.g., educational content for quiz)
 * @param options Generation options (optional)
 * @return A structured output stream containing tokens and final result
 */
suspend fun <T : Generatable> RunAnywhereSDK.generateStructuredStream(
    type: KClass<T>,
    content: String,
    options: RunAnywhereGenerationOptions? = null
): StructuredOutputStreamResult<T> = coroutineScope {
    structuredOutputLogger.debug("Generating structured output stream for type: ${type.simpleName}")

    // Create a shared accumulator
    val accumulator = StreamAccumulator()

    // Create structured output handler
    val handler = StructuredOutputHandler()

    // Get system prompt for structured output
    val systemPrompt = handler.getSystemPrompt(type)

    // Build user prompt
    val userPrompt = handler.buildUserPrompt(type, content)

    // Create effective options with system prompt
    val effectiveOptions = (options ?: RunAnywhereGenerationOptions.DEFAULT).copy(
        systemPrompt = systemPrompt,
        streamingEnabled = true
    )

    // Create token stream
    val tokenStream = flow {
        var tokenIndex = 0

        try {
            // Stream tokens from generate
            generateStream(userPrompt, effectiveOptions).collect { token ->
                val streamToken = StreamToken.create(
                    text = token,
                    tokenIndex = tokenIndex
                )

                // Accumulate for parsing
                accumulator.append(token)

                // Yield to UI
                emit(streamToken)
                tokenIndex++
            }

            accumulator.markComplete()
        } catch (e: Exception) {
            structuredOutputLogger.error("Streaming failed: ${e.message}")
            accumulator.markComplete()
            throw e
        }
    }

    // Create result deferred that waits for streaming to complete
    val resultDeferred = async {
        // Wait for accumulation to complete
        accumulator.waitForCompletion()

        // Get full response
        val fullResponse = accumulator.getFullText()

        // Parse using StructuredOutputHandler with retry logic (matching iOS 3 attempts)
        var lastError: Exception? = null

        for (attempt in 1..3) {
            try {
                structuredOutputLogger.debug("Parsing attempt $attempt/3")
                return@async handler.parseStructuredOutput(fullResponse, type)
            } catch (e: Exception) {
                lastError = e
                structuredOutputLogger.warn("Parse attempt $attempt failed: ${e.message}")
                if (attempt < 3) {
                    // Brief delay before retry (matching iOS 100ms)
                    delay(100)
                }
            }
        }

        structuredOutputLogger.error("Failed to parse structured output after 3 attempts")
        throw lastError ?: Exception("Failed to parse structured output after 3 attempts")
    }

    StructuredOutputStreamResult(
        tokenStream = tokenStream,
        result = resultDeferred
    )
}

/**
 * Generate structured output with streaming support (inline reified version)
 * Convenience method for reified type parameter
 *
 * @param T The type to generate (must conform to Generatable)
 * @param content The content to generate from
 * @param options Generation options (optional)
 * @return A structured output stream containing tokens and final result
 */
suspend inline fun <reified T : Generatable> RunAnywhereSDK.generateStructuredStream(
    content: String,
    options: RunAnywhereGenerationOptions? = null
): StructuredOutputStreamResult<T> {
    return generateStructuredStream(T::class, content, options)
}
