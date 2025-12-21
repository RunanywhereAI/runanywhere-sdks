package com.runanywhere.sdk.features.llm.structuredoutput

import com.runanywhere.sdk.features.llm.LLMCapability
import com.runanywhere.sdk.features.llm.LLMGenerationResult
import com.runanywhere.sdk.features.llm.LLMStreamingResult
import com.runanywhere.sdk.models.Generatable
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.models.StructuredOutputConfig
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.serialization.KSerializer
import kotlinx.serialization.serializer

/**
 * Service for generating structured output from LLMs
 * Matches iOS StructuredOutputGenerationService
 */
class StructuredOutputGenerationService {
    @PublishedApi
    internal val handler = StructuredOutputHandler()

    // =========================================================================
    // MARK: - Non-Streaming Generation
    // =========================================================================

    /**
     * Generate structured output that conforms to a Generatable type (non-streaming)
     *
     * @param T The type to generate (must implement Generatable)
     * @param prompt The prompt to generate from
     * @param options Generation options (structured output config will be added automatically)
     * @param llmCapability The LLM capability to use for generation
     * @param hints Optional generation hints for this type
     * @return The generated object of the specified type
     */
    suspend inline fun <reified T : Generatable> generateStructured(
        prompt: String,
        options: LLMGenerationOptions? = null,
        llmCapability: LLMCapability,
        hints: GenerationHints? = null,
    ): T {
        val schema = Generatable.getJsonSchema(T::class)
        return generateStructuredWithSchema(
            prompt = prompt,
            schema = schema,
            options = options,
            llmCapability = llmCapability,
            hints = hints,
            parse = { text -> handler.parseStructuredOutput<T>(text) },
        )
    }

    /**
     * Generate structured output using a serializer (for non-reified contexts)
     */
    suspend fun <T : Generatable> generateStructured(
        prompt: String,
        serializer: KSerializer<T>,
        schema: String,
        options: LLMGenerationOptions? = null,
        llmCapability: LLMCapability,
        hints: GenerationHints? = null,
    ): T =
        generateStructuredWithSchema(
            prompt = prompt,
            schema = schema,
            options = options,
            llmCapability = llmCapability,
            hints = hints,
            parse = { text -> handler.parseStructuredOutput(text, serializer) },
        )

    /**
     * Internal implementation for structured generation
     */
    @PublishedApi
    internal suspend fun <T : Generatable> generateStructuredWithSchema(
        prompt: String,
        schema: String,
        options: LLMGenerationOptions?,
        llmCapability: LLMCapability,
        hints: GenerationHints?,
        parse: (String) -> T,
    ): T {
        // Get system prompt for structured output
        val systemPrompt = handler.getSystemPrompt<T>(schema)

        // Determine effective options
        val baseOptions = options ?: LLMGenerationOptions.DEFAULT
        val effectiveOptions =
            baseOptions.copy(
                maxTokens = hints?.maxTokens ?: baseOptions.maxTokens,
                temperature = hints?.temperature ?: baseOptions.temperature,
                streamingEnabled = false,
                systemPrompt = systemPrompt,
                structuredOutput =
                    StructuredOutputConfig(
                        typeName = "Structured",
                        includeSchemaInPrompt = false,
                        jsonSchema = schema,
                    ),
            )

        // Build user prompt
        val userPrompt = handler.buildUserPrompt(prompt)

        // Generate the text using LLMCapability
        val generationResult = llmCapability.generate(userPrompt, effectiveOptions)

        // Parse using StructuredOutputHandler
        return parse(generationResult.text)
    }

    // =========================================================================
    // MARK: - Streaming Generation
    // =========================================================================

    /**
     * Generate structured output with streaming support
     *
     * @param T The type to generate (must implement Generatable)
     * @param content The content to generate from
     * @param options Generation options (optional)
     * @param streamGenerator Function to generate token stream
     * @param hints Optional generation hints for this type
     * @return A structured output stream containing tokens and final result
     */
    inline fun <reified T : Generatable> generateStructuredStream(
        content: String,
        options: LLMGenerationOptions? = null,
        noinline streamGenerator: suspend (String, LLMGenerationOptions) -> LLMStreamingResult,
        hints: GenerationHints? = null,
    ): StructuredOutputStreamResult<T> {
        val schema = Generatable.getJsonSchema(T::class)
        return generateStructuredStreamWithSchema(
            content = content,
            schema = schema,
            options = options,
            streamGenerator = streamGenerator,
            hints = hints,
            parse = { text -> handler.parseStructuredOutput<T>(text) },
        )
    }

    /**
     * Generate structured output stream using a serializer (for non-reified contexts)
     */
    fun <T : Generatable> generateStructuredStream(
        content: String,
        serializer: KSerializer<T>,
        schema: String,
        options: LLMGenerationOptions? = null,
        streamGenerator: suspend (String, LLMGenerationOptions) -> LLMStreamingResult,
        hints: GenerationHints? = null,
    ): StructuredOutputStreamResult<T> =
        generateStructuredStreamWithSchema(
            content = content,
            schema = schema,
            options = options,
            streamGenerator = streamGenerator,
            hints = hints,
            parse = { text -> handler.parseStructuredOutput(text, serializer) },
        )

    /**
     * Internal implementation for streaming structured generation
     */
    @PublishedApi
    internal fun <T : Generatable> generateStructuredStreamWithSchema(
        content: String,
        schema: String,
        options: LLMGenerationOptions?,
        streamGenerator: suspend (String, LLMGenerationOptions) -> LLMStreamingResult,
        hints: GenerationHints?,
        parse: (String) -> T,
    ): StructuredOutputStreamResult<T> {
        // Create a shared accumulator
        val accumulator = StreamAccumulator()
        val resultDeferred = CompletableDeferred<T>()

        // Get system prompt for structured output
        val systemPrompt = handler.getSystemPrompt<T>(schema)

        // Create effective options with system prompt
        val baseOptions = options ?: LLMGenerationOptions.DEFAULT
        val effectiveOptions =
            baseOptions.copy(
                maxTokens = hints?.maxTokens ?: baseOptions.maxTokens,
                temperature = hints?.temperature ?: baseOptions.temperature,
                streamingEnabled = true,
                systemPrompt = systemPrompt,
                structuredOutput =
                    StructuredOutputConfig(
                        typeName = "Structured",
                        includeSchemaInPrompt = false,
                        jsonSchema = schema,
                    ),
            )

        // Build user prompt
        val userPrompt = handler.buildUserPrompt(content)

        // Create token stream flow
        val tokenStream: Flow<StreamToken> =
            flow {
                var tokenIndex = 0

                try {
                    // Stream tokens
                    val streamingResult = streamGenerator(userPrompt, effectiveOptions)

                    streamingResult.stream.collect { token ->
                        val streamToken = StreamToken.create(text = token, tokenIndex = tokenIndex)

                        // Accumulate for parsing
                        accumulator.append(token)

                        // Emit to collectors
                        emit(streamToken)
                        tokenIndex++
                    }

                    accumulator.markComplete()

                    // Parse result after streaming completes
                    parseWithRetry(accumulator, parse, resultDeferred)
                } catch (e: Exception) {
                    accumulator.markComplete()
                    resultDeferred.completeExceptionally(e)
                    throw e
                }
            }

        return StructuredOutputStreamResult(
            tokenStream = tokenStream,
            result = resultDeferred,
        )
    }

    /**
     * Parse with retry logic (matches iOS behavior)
     */
    private suspend fun <T : Generatable> parseWithRetry(
        accumulator: StreamAccumulator,
        parse: (String) -> T,
        resultDeferred: CompletableDeferred<T>,
    ) {
        val fullResponse = accumulator.getFullText()
        var lastError: Exception? = null

        for (attempt in 1..MAX_RETRY_ATTEMPTS) {
            try {
                val result = parse(fullResponse)
                resultDeferred.complete(result)
                return
            } catch (e: Exception) {
                lastError = e
                if (attempt < MAX_RETRY_ATTEMPTS) {
                    // Brief delay before retry
                    delay(RETRY_DELAY_MS)
                }
            }
        }

        resultDeferred.completeExceptionally(
            lastError ?: StructuredOutputError.ExtractionFailed(
                "Failed to parse structured output after $MAX_RETRY_ATTEMPTS attempts",
            ),
        )
    }

    // =========================================================================
    // MARK: - Generation with Config
    // =========================================================================

    /**
     * Generate with structured output configuration
     * Matches iOS generateWithStructuredOutput method
     *
     * @param prompt The prompt to generate from
     * @param structuredOutput Structured output configuration
     * @param options Generation options
     * @param llmCapability The LLM capability to use for generation
     * @return Generation result with structured data
     */
    suspend fun generateWithStructuredOutput(
        prompt: String,
        structuredOutput: StructuredOutputConfig,
        options: LLMGenerationOptions? = null,
        llmCapability: LLMCapability,
    ): LLMGenerationResult {
        // Generate using regular generation with structured config in options
        val baseOptions = options ?: LLMGenerationOptions.DEFAULT
        val internalOptions =
            baseOptions.copy(
                structuredOutput = structuredOutput,
            )

        return llmCapability.generate(prompt, internalOptions)
    }

    companion object {
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val RETRY_DELAY_MS = 100L
    }
}
