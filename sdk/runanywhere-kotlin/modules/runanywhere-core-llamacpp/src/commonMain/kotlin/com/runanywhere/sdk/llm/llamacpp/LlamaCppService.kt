package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.llm.LLMInput
import com.runanywhere.sdk.features.llm.LLMOutput
import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.models.LLMGenerationChunk
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.flow.Flow

/**
 * LlamaCpp service implementation backed by RunAnywhere Core.
 *
 * This wraps the runanywhere-core C++ library which has proper chat template support
 * for all models including Qwen, LFM2, Llama, and others.
 *
 * Usage:
 * ```kotlin
 * val service = LlamaCppService(configuration)
 * service.initialize("/path/to/model.gguf")
 *
 * // Generate text
 * val result = service.generate("Hello", options)
 *
 * // Stream generation
 * service.streamGenerate("Tell me a story", options) { token ->
 *     print(token)
 * }
 * ```
 */
expect class LlamaCppService(
    configuration: LLMConfiguration,
) : LLMService {
    // Core LLMService interface methods (from iOS LLMService protocol)
    override suspend fun initialize(modelPath: String?)

    override suspend fun generate(prompt: String, options: LLMGenerationOptions): String

    override suspend fun streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: (String) -> Unit,
    )

    override suspend fun cleanup()

    override val isReady: Boolean
    override val currentModel: String?

    // Additional utility methods (not part of LLMService interface, but useful for direct service access)
    suspend fun process(input: LLMInput): LLMOutput

    fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>

    suspend fun loadModel(modelInfo: ModelInfo)

    fun cancelCurrent()

    fun getTokenCount(text: String): Int

    fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
