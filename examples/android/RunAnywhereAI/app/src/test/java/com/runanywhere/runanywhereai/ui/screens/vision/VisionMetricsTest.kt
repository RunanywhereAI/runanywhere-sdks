package com.runanywhere.runanywhereai.ui.screens.vision

import ai.runanywhere.proto.v1.VLMResult
import org.junit.Assert.assertEquals
import org.junit.Test

class VisionMetricsTest {
    @Test
    fun `maps canonical engine metrics without wall clock substitution`() {
        val metrics = VLMResult(
            completion_tokens = 37,
            tokens_per_second = 14.25f,
            processing_time_ms = 2_800,
            image_encode_time_ms = 315,
            time_to_first_token_ms = 640,
        ).toUiMetrics()

        assertEquals(37, metrics.tokens)
        assertEquals(14.25, metrics.tokensPerSecond, 0.0001)
        assertEquals(2_800L, metrics.processingMs)
        assertEquals(315L, metrics.imageEncodeMs)
        assertEquals(640L, metrics.ttftMs)
    }

    @Test
    fun `shows a useful fallback when the engine returns blank text`() {
        assertEquals(
            "I could not read that image.",
            VLMResult(text = "  \n").toDisplayText(),
        )
    }
}
