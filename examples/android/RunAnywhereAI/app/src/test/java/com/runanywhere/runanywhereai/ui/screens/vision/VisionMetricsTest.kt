package com.runanywhere.runanywhereai.ui.screens.vision

import com.runanywhere.sdk.public.api.GenerationResult
import org.junit.Assert.assertEquals
import org.junit.Test

class VisionMetricsTest {
    @Test
    fun `maps canonical engine metrics with a measured processing time`() {
        val metrics = GenerationResult(
            text = "A bar chart.",
            outputTokens = 37,
            tokensPerSecond = 14.25f,
            timeToFirstTokenMs = 640,
        ).toUiMetrics(processingMs = 2_800)

        assertEquals(37, metrics.tokens)
        assertEquals(14.25, metrics.tokensPerSecond, 0.0001)
        assertEquals(2_800L, metrics.processingMs)
        assertEquals(640L, metrics.ttftMs)
    }

    @Test
    fun `shows a useful fallback when the engine returns blank text`() {
        assertEquals(
            "I could not read that image.",
            GenerationResult(text = "  \n").toDisplayText(),
        )
    }
}
