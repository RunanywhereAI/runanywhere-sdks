package com.runanywhere.runanywhereai.presentation.benchmarks.services

import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import ai.runanywhere.proto.v1.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Benchmarks LLM generation with short/medium/long token counts.
 * Matches iOS LLMBenchmarkProvider exactly.
 */
class LLMBenchmarkProvider : BenchmarkScenarioProvider {
    override val category: BenchmarkCategory = BenchmarkCategory.LLM

    override fun scenarios(): List<BenchmarkScenario> =
        listOf(
            BenchmarkScenario(name = "Short (50 tokens)", category = BenchmarkCategory.LLM),
            BenchmarkScenario(name = "Medium (256 tokens)", category = BenchmarkCategory.LLM),
            BenchmarkScenario(name = "Long (512 tokens)", category = BenchmarkCategory.LLM),
        )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val maxTokens = tokenCount(scenario)
        val memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        val loadStart = System.nanoTime()
        RunAnywhere.loadLLMModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            // v2 close-out Phase G-2: generateStream returns Flow<LLMStreamEvent>;
            // compute TTFT + tokens/sec from the event sequence directly.
            val warmupStart = System.nanoTime()
            val warmupOptions = LLMGenerationOptions(max_tokens = 5, temperature = 0.0f)
            // B-AK-20-003 — takeWhile closes the Flow on is_final; timeout guards a missing terminal event.
            withTimeoutOrNull(10_000L) {
                RunAnywhere.generateStream("Hello", warmupOptions)
                    .takeWhile { !it.is_final }
                    .collect { _ ->
                        // warmup only primes the model; no metrics needed
                    }
            }
            val warmupTimeMs = (System.nanoTime() - warmupStart) / 1_000_000.0

            // Benchmark
            val benchStart = System.nanoTime()
            val options = LLMGenerationOptions(max_tokens = maxTokens, temperature = 0.0f)
            val prompt = "Explain the concept of machine learning in detail."

            var tokenCount = 0
            var firstTokenTimeNs: Long? = null
            // B-AK-20-003 — takeWhile closes the Flow on is_final; timeout guards a missing terminal event.
            withTimeoutOrNull(60_000L) {
                RunAnywhere.generateStream(prompt, options)
                    .takeWhile { !it.is_final }
                    .collect { event ->
                        if (event.token.isNotEmpty()) {
                            if (firstTokenTimeNs == null) firstTokenTimeNs = System.nanoTime()
                            tokenCount++
                        }
                    }
            }
            val endToEndMs = (System.nanoTime() - benchStart) / 1_000_000.0
            val ttftMs: Double? = firstTokenTimeNs?.let { (it - benchStart) / 1_000_000.0 }
            val tokensPerSecond: Double = if (endToEndMs > 0) tokenCount.toDouble() / (endToEndMs / 1000.0) else 0.0
            val inputTokens = maxOf(1, prompt.length / 4)

            val memAfter = SyntheticInputGenerator.availableMemoryBytes()

            return BenchmarkMetrics(
                endToEndLatencyMs = endToEndMs,
                loadTimeMs = loadTimeMs,
                warmupTimeMs = warmupTimeMs,
                memoryDeltaBytes = memBefore - memAfter,
                ttftMs = ttftMs,
                tokensPerSecond = tokensPerSecond,
                inputTokens = inputTokens,
                outputTokens = tokenCount,
            )
        } finally {
            withContext(NonCancellable) {
                try {
                    RunAnywhere.unloadLLMModel()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun tokenCount(scenario: BenchmarkScenario): Int =
        when {
            scenario.name.contains("50") -> 50
            scenario.name.contains("256") -> 256
            else -> 512
        }
}
