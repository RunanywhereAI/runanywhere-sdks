package com.runanywhere.runanywhereai.ui.screens.vision

import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions

internal const val DEFAULT_VISION_PROMPT = "Describe this image in detail."

/** The product surface knows how much detail it requested without inspecting generated text. */
internal enum class VisionAnswerMode(val outputTokenCap: Int) {
    DETAILED_DESCRIPTION(160),
    FOCUSED_QUESTION(96),
    LIVE_CAPTION(48),
}

/**
 * Generation policy shared by every consumer-facing image path.
 *
 * VLM contexts include image tokens as well as the text prompt. Capping output to
 * at most one quarter of a model's declared context leaves room for both, which
 * is especially important for 512-token image models. The answer-mode cap keeps
 * a focused chart/invoice question from turning into an open-ended caption while
 * still giving the explicit detailed-description action a larger budget.
 */
internal object VisionGenerationPolicy {
    fun maxTokens(
        modelContextLength: Int,
        mode: VisionAnswerMode,
        userLimit: Int? = null,
    ): Int {
        var cap = mode.outputTokenCap
        if (modelContextLength > 0) {
            cap = minOf(cap, maxOf(1, modelContextLength / CONTEXT_OUTPUT_DIVISOR))
        }
        userLimit?.takeIf { it > 0 }?.let { cap = minOf(cap, it) }
        return maxOf(1, cap)
    }

    fun options(
        prompt: String,
        model: RAModelInfo,
        mode: VisionAnswerMode,
        userLimit: Int? = null,
        systemPrompt: String? = null,
    ): RAVLMGenerationOptions =
        RAVLMGenerationOptions(
            prompt = prompt,
            max_tokens = maxTokens(model.context_length, mode, userLimit),
            // Pin the complete greedy configuration. Temperature alone is
            // sufficient today, but explicit top-p/top-k avoids default drift.
            temperature = 0f,
            top_p = 0f,
            top_k = 0,
            system_prompt = systemPrompt?.takeIf { it.isNotBlank() },
        )

    private const val CONTEXT_OUTPUT_DIVISOR = 4
}
