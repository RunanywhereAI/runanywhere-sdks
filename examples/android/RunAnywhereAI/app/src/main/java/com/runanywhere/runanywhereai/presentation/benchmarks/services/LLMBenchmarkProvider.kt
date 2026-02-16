package com.runanywhere.runanywhereai.presentation.benchmarks.services

import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * Benchmarks LLM generation with short/medium/long token counts.
 * Matches iOS LLMBenchmarkProvider exactly.
 */
class LLMBenchmarkProvider : BenchmarkScenarioProvider {

    override val category: BenchmarkCategory = BenchmarkCategory.LLM

    override fun scenarios(): List<BenchmarkScenario> = listOf(
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
            // Warmup: short generate, discard
            val warmupStart = System.nanoTime()
            val warmupOptions = LLMGenerationOptions(maxTokens = 5, temperature = 0.0f)
            val warmupResult = RunAnywhere.generateStreamWithMetrics("Hello", warmupOptions)
            warmupResult.stream.collect { }
            warmupResult.result.await()
            val warmupTimeMs = (System.nanoTime() - warmupStart) / 1_000_000.0

            // Benchmark
            val benchStart = System.nanoTime()
            val options = LLMGenerationOptions(maxTokens = maxTokens, temperature = 0.0f)
            val streamResult = RunAnywhere.generateStreamWithMetrics(
                "Explain the concept of machine learning in detail.",
                options,
            )
            streamResult.stream.collect { }
            val result = streamResult.result.await()
            val endToEndMs = (System.nanoTime() - benchStart) / 1_000_000.0

            val memAfter = SyntheticInputGenerator.availableMemoryBytes()

            return BenchmarkMetrics(
                endToEndLatencyMs = endToEndMs,
                loadTimeMs = loadTimeMs,
                warmupTimeMs = warmupTimeMs,
                memoryDeltaBytes = memBefore - memAfter,
                ttftMs = result.timeToFirstTokenMs,
                tokensPerSecond = result.tokensPerSecond,
                inputTokens = result.inputTokens,
                outputTokens = result.tokensUsed,
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

    private fun tokenCount(scenario: BenchmarkScenario): Int = when {
        scenario.name.contains("50") -> 50
        scenario.name.contains("256") -> 256
        else -> 512
    }
}
