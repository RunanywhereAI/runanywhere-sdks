package com.runanywhere.runanywhereai.data.benchmark

import com.runanywhere.sdk.public.types.RALLMGenerationResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BenchmarkMetricPolicyTest {
    @Test
    fun `qhex terminal metrics retain native token count and throughput`() {
        val metrics = llmBenchmarkMetrics(
            result = RALLMGenerationResult(
                input_tokens = 41,
                tokens_generated = 256,
                generation_time_ms = 20_500.0,
                ttft_ms = 500.0,
                tokens_per_second = 12.8,
            ),
            loadTimeMs = 900.0,
            warmupTimeMs = 400.0,
            measuredEndToEndMs = 21_000.0,
            memoryDeltaBytes = 123L,
        )

        assertEquals(256, metrics.outputTokens)
        assertEquals(12.8, metrics.tokensPerSecond!!, 0.0001)
        assertEquals(20_000.0, metrics.decodeMs!!, 0.0001)
        assertEquals(500.0, metrics.promptEvalMs!!, 0.0001)
        assertEquals(20_500.0, metrics.endToEndLatencyMs, 0.0001)
    }

    @Test
    fun `throughput is derived from native decode time when backend omits it`() {
        val metrics = llmBenchmarkMetrics(
            result = RALLMGenerationResult(
                tokens_generated = 256,
                generation_time_ms = 20_500.0,
                tokens_per_second = 0.0,
                decode_time_ms = 20_000,
            ),
            loadTimeMs = 0.0,
            warmupTimeMs = 0.0,
            measuredEndToEndMs = 21_000.0,
            memoryDeltaBytes = 0L,
        )

        assertEquals(12.8, metrics.tokensPerSecond!!, 0.0001)
    }

    @Test
    fun `zero output cannot be reported as a successful llm benchmark`() {
        assertThrows(IllegalArgumentException::class.java) {
            llmBenchmarkMetrics(
                result = RALLMGenerationResult(tokens_generated = 0, generation_time_ms = 1_000.0),
                loadTimeMs = 0.0,
                warmupTimeMs = 0.0,
                measuredEndToEndMs = 1_000.0,
                memoryDeltaBytes = 0L,
            )
        }
    }

    @Test
    fun `zero output vlm metrics fail the shared success policy`() {
        assertThrows(IllegalArgumentException::class.java) {
            BenchmarkMetrics(outputTokens = 0)
                .requireSuccessfulOutput(BenchmarkCategory.VLM)
        }
    }
}
