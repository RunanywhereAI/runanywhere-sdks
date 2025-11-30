package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.models.LLMGenerationChunk
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
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
expect class LlamaCppService(configuration: LLMConfiguration) : LLMService {
    override suspend fun initialize(modelPath: String?)
    override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String
    override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    )
    override suspend fun cleanup()
    override val isReady: Boolean
    override val currentModel: String?

    // EnhancedLLMService
    override suspend fun process(input: LLMInput): LLMOutput
    override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>
    override suspend fun loadModel(modelInfo: ModelInfo)
    override fun cancelCurrent()
    override fun getTokenCount(text: String): Int
    override fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
