package com.runanywhere.sdk.generation

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Resolves and validates generation options
 * Applies defaults and ensures options are within valid ranges
 */
class GenerationOptionsResolver {

    private val logger = SDKLogger("GenerationOptionsResolver")

    companion object {
        // Default values
        const val DEFAULT_TEMPERATURE = 0.7f
        const val DEFAULT_MAX_TOKENS = 1000
        const val DEFAULT_TOP_P = 0.9f
        const val DEFAULT_TOP_K = 40

        // Valid ranges
        val TEMPERATURE_RANGE = 0.0f..2.0f
        val MAX_TOKENS_RANGE = 1..100000
        val TOP_P_RANGE = 0.0f..1.0f
        val TOP_K_RANGE = 1..100
    }

    /**
     * Resolve generation options with defaults and validation
     */
    fun resolve(options: GenerationOptions?): GenerationOptions {
        val input = options ?: GenerationOptions()

        return GenerationOptions(
            model = resolveModel(input.model),
            temperature = clampTemperature(input.temperature),
            maxTokens = clampMaxTokens(input.maxTokens),
            topP = clampTopP(input.topP),
            topK = clampTopK(input.topK),
            stopSequences = input.stopSequences,
            streaming = input.streaming,
            seed = input.seed
        )
    }

    /**
     * Merge two sets of options, with override taking precedence
     */
    fun merge(
        base: GenerationOptions,
        override: GenerationOptions?
    ): GenerationOptions {
        if (override == null) return base

        return GenerationOptions(
            model = override.model ?: base.model,
            temperature = override.temperature,
            maxTokens = override.maxTokens,
            topP = override.topP,
            topK = override.topK,
            stopSequences = if (override.stopSequences.isNotEmpty()) {
                override.stopSequences
            } else {
                base.stopSequences
            },
            streaming = override.streaming,
            seed = override.seed ?: base.seed
        )
    }

    /**
     * Create options optimized for different use cases
     */
    fun createForUseCase(useCase: GenerationUseCase): GenerationOptions {
        return when (useCase) {
            GenerationUseCase.CREATIVE_WRITING -> GenerationOptions(
                temperature = 0.9f,
                topP = 0.95f,
                topK = 50,
                maxTokens = 2000
            )

            GenerationUseCase.CODE_GENERATION -> GenerationOptions(
                temperature = 0.3f,
                topP = 0.9f,
                topK = 20,
                maxTokens = 1500,
                stopSequences = listOf("```", "\n\n\n")
            )

            GenerationUseCase.FACTUAL_QA -> GenerationOptions(
                temperature = 0.1f,
                topP = 0.8f,
                topK = 10,
                maxTokens = 500
            )

            GenerationUseCase.CONVERSATION -> GenerationOptions(
                temperature = 0.7f,
                topP = 0.9f,
                topK = 40,
                maxTokens = 1000
            )

            GenerationUseCase.SUMMARIZATION -> GenerationOptions(
                temperature = 0.3f,
                topP = 0.85f,
                topK = 20,
                maxTokens = 300
            )
        }
    }

    // Private validation methods

    private fun resolveModel(model: String?): String? {
        // TODO: Validate against available models
        return model
    }

    private fun clampTemperature(temp: Float): Float {
        return if (temp in TEMPERATURE_RANGE) {
            temp
        } else {
            logger.warning("Temperature $temp out of range, using default")
            DEFAULT_TEMPERATURE
        }
    }

    private fun clampMaxTokens(tokens: Int): Int {
        return if (tokens in MAX_TOKENS_RANGE) {
            tokens
        } else {
            logger.warning("Max tokens $tokens out of range, using default")
            DEFAULT_MAX_TOKENS
        }
    }

    private fun clampTopP(topP: Float): Float {
        return if (topP in TOP_P_RANGE) {
            topP
        } else {
            logger.warning("Top-p $topP out of range, using default")
            DEFAULT_TOP_P
        }
    }

    private fun clampTopK(topK: Int): Int {
        return if (topK in TOP_K_RANGE) {
            topK
        } else {
            logger.warning("Top-k $topK out of range, using default")
            DEFAULT_TOP_K
        }
    }
}

/**
 * Predefined generation use cases
 */
enum class GenerationUseCase {
    CREATIVE_WRITING,
    CODE_GENERATION,
    FACTUAL_QA,
    CONVERSATION,
    SUMMARIZATION
}
