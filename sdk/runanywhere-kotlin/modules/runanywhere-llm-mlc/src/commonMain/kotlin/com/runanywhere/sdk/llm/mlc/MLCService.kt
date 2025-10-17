package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.models.LLMGenerationChunk
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import kotlinx.coroutines.flow.Flow

/**
 * MLC-LLM Service interface
 *
 * Provides on-device LLM inference using MLC-compiled models with GPU acceleration.
 * Uses expect/actual pattern to allow platform-specific implementations.
 *
 * ## Platform Support
 * - Android: Full support with OpenCL GPU acceleration
 * - JVM: Not supported (MLC-LLM is mobile-optimized)
 *
 * ## Requirements
 * - MLC-compiled model files
 * - Model library name (modelLib) in configuration.frameworkOptions
 * - Minimum Android API 24
 *
 * ## Usage
 * ```kotlin
 * val config = LLMConfiguration(
 *     modelId = "/path/to/model",
 *     frameworkOptions = mapOf("modelLib" to "model_lib_name")
 * )
 *
 * val service = MLCService(configuration)
 * service.initialize()
 *
 * // Generate text
 * val response = service.generate("Hello!", options)
 *
 * // Stream generation
 * service.streamGenerate("Hello!", options) { token ->
 *     print(token)
 * }
 *
 * // Cleanup
 * service.cleanup()
 * ```
 */
expect class MLCService(configuration: LLMConfiguration) : EnhancedLLMService {

    // Basic LLMService methods

    /**
     * Initialize the service and load the model
     *
     * Loads the MLC-compiled model and prepares it for inference.
     * This is a blocking operation that may take several seconds.
     *
     * @param modelPath Optional path to model directory. If null, uses configuration.modelId
     * @throws IllegalArgumentException if no model path is provided
     * @throws IllegalStateException if model loading fails
     */
    override suspend fun initialize(modelPath: String?)

    /**
     * Generate text from a prompt
     *
     * Performs synchronous text generation and returns the complete result.
     *
     * @param prompt The input prompt
     * @param options Generation options (temperature, max tokens, etc.)
     * @return Generated text
     * @throws IllegalStateException if service is not initialized
     */
    override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String

    /**
     * Stream generation token by token
     *
     * Performs streaming text generation, calling onToken for each generated token.
     *
     * @param prompt The input prompt
     * @param options Generation options
     * @param onToken Callback invoked for each generated token
     * @throws IllegalStateException if service is not initialized
     */
    override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    )

    /**
     * Check if service is ready for generation
     */
    override val isReady: Boolean

    /**
     * Get current model identifier
     */
    override val currentModel: String?

    /**
     * Cleanup resources and unload model
     */
    override suspend fun cleanup()

    // EnhancedLLMService methods

    /**
     * Process structured LLM input with rich metadata
     *
     * @param input Structured input with messages, system prompt, and options
     * @return Structured output with text, token usage, and metadata
     * @throws IllegalStateException if service is not initialized
     */
    override suspend fun process(input: LLMInput): LLMOutput

    /**
     * Stream generation with structured input/output
     *
     * @param input Structured input with messages and options
     * @return Flow of generation chunks with completion status
     */
    override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>

    /**
     * Load a specific model using ModelInfo
     *
     * @param modelInfo Model information including path and metadata
     */
    override suspend fun loadModel(modelInfo: ModelInfo)

    /**
     * Cancel current generation
     *
     * Sets a cancellation flag that will stop generation at the next token boundary.
     */
    override fun cancelCurrent()

    /**
     * Get token count for text
     *
     * Estimates the number of tokens in the given text. This is a rough estimate
     * using the heuristic of ~4 characters per token.
     *
     * @param text Text to count tokens for
     * @return Estimated token count
     */
    override fun getTokenCount(text: String): Int

    /**
     * Check if prompt fits within context window
     *
     * @param prompt The prompt to check
     * @param maxTokens Maximum tokens to generate
     * @return true if prompt + maxTokens <= context length
     */
    override fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
