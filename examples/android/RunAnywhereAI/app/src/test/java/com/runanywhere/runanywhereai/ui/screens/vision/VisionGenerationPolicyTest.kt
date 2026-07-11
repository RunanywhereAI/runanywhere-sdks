package com.runanywhere.runanywhereai.ui.screens.vision

import ai.runanywhere.proto.v1.ModelInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class VisionGenerationPolicyTest {
    @Test
    fun `512 context preserves detailed answers without consuming the image window`() {
        assertEquals(
            128,
            VisionGenerationPolicy.maxTokens(512, VisionAnswerMode.DETAILED_DESCRIPTION),
        )
    }

    @Test
    fun `focused and live requests use smaller product budgets`() {
        assertEquals(
            96,
            VisionGenerationPolicy.maxTokens(512, VisionAnswerMode.FOCUSED_QUESTION),
        )
        assertEquals(
            48,
            VisionGenerationPolicy.maxTokens(512, VisionAnswerMode.LIVE_CAPTION),
        )
    }

    @Test
    fun `model context and user preference can only tighten the mode budget`() {
        assertEquals(
            64,
            VisionGenerationPolicy.maxTokens(256, VisionAnswerMode.FOCUSED_QUESTION),
        )
        assertEquals(
            24,
            VisionGenerationPolicy.maxTokens(
                modelContextLength = 512,
                mode = VisionAnswerMode.LIVE_CAPTION,
                userLimit = 24,
            ),
        )
        assertEquals(
            160,
            VisionGenerationPolicy.maxTokens(0, VisionAnswerMode.DETAILED_DESCRIPTION),
        )
    }

    @Test
    fun `generation options pin greedy decoding and carry the system prompt`() {
        val options = VisionGenerationPolicy.options(
            prompt = "Read the total.",
            model = ModelInfo(id = "vision", context_length = 512),
            mode = VisionAnswerMode.FOCUSED_QUESTION,
            systemPrompt = "Be precise.",
        )

        assertEquals(96, options.max_tokens)
        assertEquals(0f, options.temperature)
        assertEquals(0f, options.top_p)
        assertEquals(0, options.top_k)
        assertEquals("Be precise.", options.system_prompt)
    }
}
