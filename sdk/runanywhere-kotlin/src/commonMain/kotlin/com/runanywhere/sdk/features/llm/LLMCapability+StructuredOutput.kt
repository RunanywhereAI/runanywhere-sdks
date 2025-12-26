package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.features.llm.structuredoutput.GenerationHints
import com.runanywhere.sdk.features.llm.structuredoutput.StructuredOutputGenerationService
import com.runanywhere.sdk.features.llm.structuredoutput.StructuredOutputStreamResult
import com.runanywhere.sdk.models.Generatable
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.models.StructuredOutputConfig
import kotlinx.serialization.KSerializer

/**
 * Extension functions for LLMCapability to support structured output generation
 * Matches iOS StructuredOutputGenerationService integration
 */

// Shared service instance (stateless, safe to share)
@PublishedApi
internal val structuredOutputService = StructuredOutputGenerationService()

// =============================================================================
// MARK: - Non-Streaming Structured Generation
// =============================================================================

/**
 * Generate structured output that conforms to a Generatable type
 *
 * Usage:
 * ```kotlin
 * @Serializable
 * data class Person(
 *     val name: String,
 *     val age: Int,
 *     val occupation: String
 * ) : Generatable
 *
 * val person = llmCapability.generateStructured<Person>(
 *     prompt = "Extract person info: John is a 30-year-old engineer"
 * )
 * // person.name = "John", person.age = 30, person.occupation = "engineer"
 * ```
 *
 * @param T The type to generate (must implement Generatable and be @Serializable)
 * @param prompt The prompt to generate from
 * @param options Optional generation options
 * @param hints Optional type-specific generation hints
 * @return The generated object of the specified type
 */
suspend inline fun <reified T : Generatable> LLMCapability.generateStructured(
    prompt: String,
    options: LLMGenerationOptions? = null,
    hints: GenerationHints? = null,
): T =
    structuredOutputService.generateStructured<T>(
        prompt = prompt,
        options = options,
        llmCapability = this,
        hints = hints,
    )

/**
 * Generate structured output using explicit serializer
 * Use this when reified types aren't available (e.g., in non-inline contexts)
 *
 * @param T The type to generate
 * @param prompt The prompt to generate from
 * @param serializer Kotlinx serializer for the type
 * @param schema JSON schema for the type
 * @param options Optional generation options
 * @param hints Optional type-specific generation hints
 * @return The generated object of the specified type
 */
suspend fun <T : Generatable> LLMCapability.generateStructured(
    prompt: String,
    serializer: KSerializer<T>,
    schema: String,
    options: LLMGenerationOptions? = null,
    hints: GenerationHints? = null,
): T =
    structuredOutputService.generateStructured(
        prompt = prompt,
        serializer = serializer,
        schema = schema,
        options = options,
        llmCapability = this,
        hints = hints,
    )

// =============================================================================
// MARK: - Streaming Structured Generation
// =============================================================================

/**
 * Generate structured output with streaming support
 *
 * Usage:
 * ```kotlin
 * val result = llmCapability.generateStructuredStream<Person>(
 *     content = "Extract person info from this bio..."
 * )
 *
 * // Stream tokens in real-time
 * result.tokenStream.collect { token ->
 *     print(token.text)
 * }
 *
 * // Get final parsed result
 * val person = result.result.await()
 * ```
 *
 * @param T The type to generate (must implement Generatable and be @Serializable)
 * @param content The content to generate from
 * @param options Optional generation options
 * @param hints Optional type-specific generation hints
 * @return A StructuredOutputStreamResult containing token stream and final result
 */
inline fun <reified T : Generatable> LLMCapability.generateStructuredStream(
    content: String,
    options: LLMGenerationOptions? = null,
    hints: GenerationHints? = null,
): StructuredOutputStreamResult<T> {
    val capability = this
    return structuredOutputService.generateStructuredStream<T>(
        content = content,
        options = options,
        streamGenerator = { prompt, opts -> capability.generateStream(prompt, opts) },
        hints = hints,
    )
}

/**
 * Generate structured output stream using explicit serializer
 *
 * @param T The type to generate
 * @param content The content to generate from
 * @param serializer Kotlinx serializer for the type
 * @param schema JSON schema for the type
 * @param options Optional generation options
 * @param hints Optional type-specific generation hints
 * @return A StructuredOutputStreamResult containing token stream and final result
 */
fun <T : Generatable> LLMCapability.generateStructuredStream(
    content: String,
    serializer: KSerializer<T>,
    schema: String,
    options: LLMGenerationOptions? = null,
    hints: GenerationHints? = null,
): StructuredOutputStreamResult<T> {
    val capability = this
    return structuredOutputService.generateStructuredStream(
        content = content,
        serializer = serializer,
        schema = schema,
        options = options,
        streamGenerator = { prompt, opts -> capability.generateStream(prompt, opts) },
        hints = hints,
    )
}

// =============================================================================
// MARK: - Config-Based Generation
// =============================================================================

/**
 * Generate with structured output configuration
 *
 * @param prompt The prompt to generate from
 * @param structuredOutput Structured output configuration
 * @param options Generation options
 * @return Generation result with structured data
 */
suspend fun LLMCapability.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputConfig,
    options: LLMGenerationOptions? = null,
): LLMGenerationResult =
    structuredOutputService.generateWithStructuredOutput(
        prompt = prompt,
        structuredOutput = structuredOutput,
        options = options,
        llmCapability = this,
    )
