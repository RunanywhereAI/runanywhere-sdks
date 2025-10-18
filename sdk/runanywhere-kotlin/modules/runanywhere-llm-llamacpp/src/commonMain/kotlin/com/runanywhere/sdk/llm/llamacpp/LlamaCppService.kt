package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.flow.Flow

/**
 * Expected platform-specific implementation of LlamaCpp service
 * Actual implementations are in jvmAndroidMain, jvmMain, or androidMain
 */
expect class LlamaCppService(configuration: LLMConfiguration) : LLMService {
    // Core initialization and lifecycle
    override suspend fun initialize(modelPath: String?)
    override suspend fun loadModel(modelInfo: ModelInfo)
    override suspend fun cleanup()

    // Simple text generation (automatically applies chat templates)
    override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String
    override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    )

    // Structured message-based generation
    override suspend fun process(input: LLMInput): LLMOutput
    override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>

    // Utility methods
    override fun cancelCurrent()
    override fun getTokenCount(text: String): Int
    override fun fitsInContext(prompt: String, maxTokens: Int): Boolean

    // State properties
    override val isReady: Boolean
    override val currentModel: String?
}
