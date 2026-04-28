package com.runanywhere.runanywhereai.presentation.benchmarks.services

import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import com.runanywhere.sdk.public.extensions.loadVLMModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.unloadVLMModel
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * Benchmarks VLM image understanding with synthetic images.
 * Matches iOS VLMBenchmarkProvider exactly.
 */
class VLMBenchmarkProvider : BenchmarkScenarioProvider {
    override val category: BenchmarkCategory = BenchmarkCategory.VLM

    override fun scenarios(): List<BenchmarkScenario> =
        listOf(
            BenchmarkScenario(name = "Solid Red Image", category = BenchmarkCategory.VLM),
            BenchmarkScenario(name = "Gradient Image", category = BenchmarkCategory.VLM),
        )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        val loadStart = System.nanoTime()
        RunAnywhere.loadVLMModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            // Generate synthetic image as RGB pixels
            val width = 224
            val height = 224
            val rgbData =
                if (scenario.name.contains("Solid")) {
                    SyntheticInputGenerator.solidColorRgb(width, height)
                } else {
                    SyntheticInputGenerator.gradientRgb(width, height)
                }
            val vlmImage = com.runanywhere.sdk.foundation.protoext.vlmImageFromRgbPixels(rgbData, width, height)

            // Warmup
            val warmupStart = System.nanoTime()
            val warmupOptions = VLMGenerationOptions(max_tokens = 5, temperature = 0.0f)
            RunAnywhere.processImage(vlmImage, "Hi", warmupOptions)
            val warmupTimeMs = (System.nanoTime() - warmupStart) / 1_000_000.0

            // Benchmark
            val benchOptions = VLMGenerationOptions(max_tokens = 128, temperature = 0.0f)
            val result =
                RunAnywhere.processImage(
                    vlmImage,
                    "Describe this image in detail.",
                    benchOptions,
                )

            val memAfter = SyntheticInputGenerator.availableMemoryBytes()

            return BenchmarkMetrics(
                endToEndLatencyMs = result.processing_time_ms.toDouble(),
                loadTimeMs = loadTimeMs,
                warmupTimeMs = warmupTimeMs,
                memoryDeltaBytes = memBefore - memAfter,
                tokensPerSecond = result.tokens_per_second.toDouble(),
                promptTokens = result.prompt_tokens,
                completionTokens = result.completion_tokens,
            )
        } finally {
            withContext(NonCancellable) {
                try {
                    RunAnywhere.unloadVLMModel()
                } catch (_: Exception) {
                }
            }
        }
    }
}
