package com.runanywhere.runanywhereai.presentation.benchmarks.services

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.VLMImageFormat
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.loadVLMModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.unloadModel
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString

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
        model: RAModelInfo,
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
            val vlmImage =
                RAVLMImage(
                    raw_rgb = rgbData.toByteString(),
                    width = width,
                    height = height,
                    format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
                )

            // Warmup
            val warmupStart = System.nanoTime()
            val warmupOptions = RAVLMGenerationOptions(prompt = "Hi", max_tokens = 5, temperature = 0.0f)
            RunAnywhere.processImage(vlmImage, warmupOptions)
            val warmupTimeMs = (System.nanoTime() - warmupStart) / 1_000_000.0

            // Benchmark
            val benchOptions =
                RAVLMGenerationOptions(
                    prompt = "Describe this image in detail.",
                    max_tokens = 128,
                    temperature = 0.0f,
                )
            val result = RunAnywhere.processImage(vlmImage, benchOptions)

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
                    RunAnywhere.unloadModel(
                        ModelUnloadRequest(model_id = model.id),
                    )
                } catch (_: Exception) {
                }
            }
        }
    }
}
