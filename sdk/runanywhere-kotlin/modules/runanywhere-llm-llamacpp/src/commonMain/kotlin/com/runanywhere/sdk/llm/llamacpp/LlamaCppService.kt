package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.flow.Flow

/**
 * Expected platform-specific implementation of LlamaCpp service
 * Actual implementations are in jvmAndroidMain, jvmMain, or androidMain
 */
expect class LlamaCppService(configuration: LLMConfiguration) : EnhancedLLMService {
    override suspend fun initialize(modelPath: String?)
    override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String
    override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    )
    override val isReady: Boolean
    override val currentModel: String?
    override suspend fun cleanup()

    // EnhancedLLMService methods
    override suspend fun process(input: LLMInput): LLMOutput
    override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>
    override suspend fun loadModel(modelInfo: ModelInfo)
    override fun cancelCurrent()
    override fun getTokenCount(text: String): Int
    override fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
