package com.runanywhere.runanywhereai.services

import com.runanywhere.runanywhereai.models.BenchmarkCategory
import com.runanywhere.runanywhereai.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.models.BenchmarkProgressUpdate
import com.runanywhere.runanywhereai.models.BenchmarkResult
import com.runanywhere.runanywhereai.models.BenchmarkScenario
import com.runanywhere.runanywhereai.models.ComponentModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.loadVLMModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.transcribeWithOptions
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import com.runanywhere.sdk.public.extensions.unloadSTTModel
import com.runanywhere.sdk.public.extensions.unloadTTSVoice
import com.runanywhere.sdk.public.extensions.unloadVLMModel
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

// -- Provider Interface --

interface BenchmarkScenarioProvider {
    val category: BenchmarkCategory
    fun scenarios(): List<BenchmarkScenario>
    suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics
}

// -- Runner Errors --

sealed class BenchmarkRunnerError(message: String) : Exception(message) {
    class NoModelsAvailable(skippedCategories: List<BenchmarkCategory>) : BenchmarkRunnerError(
        "No downloaded models found for: ${skippedCategories.joinToString { it.displayName }}. Download models first from the Models tab.",
    )

    class FetchModelsFailed(cause: Throwable) : BenchmarkRunnerError(
        "Failed to fetch available models: ${cause.localizedMessage ?: cause.message ?: "Unknown error"}",
    )
}

// -- Preflight Result --

data class BenchmarkPreflightResult(
    val availableCategories: Map<BenchmarkCategory, List<ModelInfo>>,
    val skippedCategories: List<BenchmarkCategory>,
    val totalWorkItems: Int,
)

// -- Run Result --

data class BenchmarkRunResult(
    val results: List<BenchmarkResult>,
    val skippedCategories: List<BenchmarkCategory>,
)

// -- Runner --

class BenchmarkRunner {

    private val providers: Map<BenchmarkCategory, BenchmarkScenarioProvider>

    init {
        val all = listOf(
            LLMBenchmarkProvider(),
            STTBenchmarkProvider(),
            TTSBenchmarkProvider(),
            VLMBenchmarkProvider(),
        )
        providers = all.associateBy { it.category }
    }

    suspend fun preflight(categories: Set<BenchmarkCategory>): BenchmarkPreflightResult {
        val allModels: List<ModelInfo> = try {
            RunAnywhere.availableModels()
        } catch (e: Exception) {
            throw BenchmarkRunnerError.FetchModelsFailed(e)
        }

        val available = mutableMapOf<BenchmarkCategory, List<ModelInfo>>()
        val skipped = mutableListOf<BenchmarkCategory>()

        for (category in BenchmarkCategory.entries) {
            if (category !in categories) continue
            if (providers[category] == null) {
                skipped.add(category)
                continue
            }
            val models = allModels.filter {
                it.category == category.modelCategory && it.isDownloaded && !it.isBuiltIn
            }
            if (models.isEmpty()) {
                skipped.add(category)
            } else {
                available[category] = models
            }
        }

        var totalItems = 0
        for ((category, models) in available) {
            val scenarioCount = providers[category]?.scenarios()?.size ?: 0
            totalItems += models.size * scenarioCount
        }

        return BenchmarkPreflightResult(
            availableCategories = available,
            skippedCategories = skipped,
            totalWorkItems = totalItems,
        )
    }

    suspend fun runBenchmarks(
        categories: Set<BenchmarkCategory>,
        onProgress: (BenchmarkProgressUpdate) -> Unit,
    ): BenchmarkRunResult {
        val preflightResult = preflight(categories)

        if (preflightResult.availableCategories.isEmpty()) {
            throw BenchmarkRunnerError.NoModelsAvailable(preflightResult.skippedCategories)
        }

        data class WorkItem(
            val category: BenchmarkCategory,
            val model: ModelInfo,
            val scenario: BenchmarkScenario,
        )

        val workItems = mutableListOf<WorkItem>()
        for (category in BenchmarkCategory.entries) {
            if (category !in categories) continue
            val provider = providers[category] ?: continue
            val models = preflightResult.availableCategories[category] ?: continue
            val scenarioList = provider.scenarios()
            for (model in models) {
                for (scenario in scenarioList) {
                    workItems.add(WorkItem(category, model, scenario))
                }
            }
        }

        val total = workItems.size
        val results = mutableListOf<BenchmarkResult>()

        for ((index, item) in workItems.withIndex()) {
            coroutineContext.ensureActive()

            onProgress(
                BenchmarkProgressUpdate(
                    completedCount = index,
                    totalCount = total,
                    currentScenario = item.scenario.name,
                    currentModel = item.model.name,
                ),
            )

            val metrics: BenchmarkMetrics = try {
                val provider = providers[item.category] ?: continue
                provider.execute(
                    scenario = item.scenario,
                    model = item.model,
                    deviceInfo = BenchmarkDeviceInfo(
                        modelName = "",
                        chipName = "",
                        totalMemoryBytes = 0,
                        availableMemoryBytes = SyntheticInputGenerator.availableMemoryBytes(),
                        osVersion = "",
                    ),
                )
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                BenchmarkMetrics(
                    errorMessage = "${item.category.displayName} [${item.model.name}]: ${e.localizedMessage ?: e.message ?: "Unknown error"}",
                )
            }

            results.add(
                BenchmarkResult(
                    category = item.category,
                    scenario = item.scenario,
                    modelInfo = ComponentModelInfo.from(item.model),
                    metrics = metrics,
                ),
            )
        }

        onProgress(
            BenchmarkProgressUpdate(
                completedCount = total,
                totalCount = total,
                currentScenario = "Done",
                currentModel = "",
            ),
        )

        return BenchmarkRunResult(
            results = results,
            skippedCategories = preflightResult.skippedCategories,
        )
    }
}

// =============================================================================
// LLM Benchmark Provider
// =============================================================================

private class LLMBenchmarkProvider : BenchmarkScenarioProvider {

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

        val loadStart = System.nanoTime()
        RunAnywhere.loadLLMModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            // Warmup
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
                try { RunAnywhere.unloadLLMModel() } catch (_: Exception) { }
            }
        }
    }

    private fun tokenCount(scenario: BenchmarkScenario): Int = when {
        scenario.name.contains("50") -> 50
        scenario.name.contains("256") -> 256
        else -> 512
    }
}

// =============================================================================
// STT Benchmark Provider
// =============================================================================

private class STTBenchmarkProvider : BenchmarkScenarioProvider {

    override val category: BenchmarkCategory = BenchmarkCategory.STT

    override fun scenarios(): List<BenchmarkScenario> = listOf(
        BenchmarkScenario(name = "Silent 2s", category = BenchmarkCategory.STT),
        BenchmarkScenario(name = "Sine Tone 3s", category = BenchmarkCategory.STT),
    )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val memBefore = SyntheticInputGenerator.availableMemoryBytes()

        val loadStart = System.nanoTime()
        RunAnywhere.loadSTTModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            val audioDuration: Double
            val audioData: ByteArray
            if (scenario.name.contains("Silent")) {
                audioDuration = 2.0
                audioData = SyntheticInputGenerator.silentAudio(durationSeconds = audioDuration)
            } else {
                audioDuration = 3.0
                audioData = SyntheticInputGenerator.sineWaveAudio(durationSeconds = audioDuration)
            }

            val benchStart = System.nanoTime()
            val options = STTOptions()
            val result = RunAnywhere.transcribeWithOptions(audioData, options)
            val endToEndMs = (System.nanoTime() - benchStart) / 1_000_000.0

            val memAfter = SyntheticInputGenerator.availableMemoryBytes()

            return BenchmarkMetrics(
                endToEndLatencyMs = endToEndMs,
                loadTimeMs = loadTimeMs,
                memoryDeltaBytes = memBefore - memAfter,
                audioLengthSeconds = audioDuration,
                realTimeFactor = result.metadata.realTimeFactor,
            )
        } finally {
            withContext(NonCancellable) {
                try { RunAnywhere.unloadSTTModel() } catch (_: Exception) { }
            }
        }
    }
}

// =============================================================================
// TTS Benchmark Provider
// =============================================================================

private class TTSBenchmarkProvider : BenchmarkScenarioProvider {

    override val category: BenchmarkCategory = BenchmarkCategory.TTS

    override fun scenarios(): List<BenchmarkScenario> = listOf(
        BenchmarkScenario(name = "Short Text", category = BenchmarkCategory.TTS),
        BenchmarkScenario(name = "Medium Text", category = BenchmarkCategory.TTS),
    )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val text = if (scenario.name.contains("Short")) {
            "Hello, this is a test."
        } else {
            "The quick brown fox jumps over the lazy dog. Machine learning models can generate speech from text with remarkable quality and natural intonation."
        }

        val memBefore = SyntheticInputGenerator.availableMemoryBytes()

        val loadStart = System.nanoTime()
        RunAnywhere.loadTTSVoice(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            val benchStart = System.nanoTime()
            val options = TTSOptions()
            val result = RunAnywhere.synthesize(text, options)
            val endToEndMs = (System.nanoTime() - benchStart) / 1_000_000.0

            val memAfter = SyntheticInputGenerator.availableMemoryBytes()

            return BenchmarkMetrics(
                endToEndLatencyMs = endToEndMs,
                loadTimeMs = loadTimeMs,
                memoryDeltaBytes = memBefore - memAfter,
                audioDurationSeconds = result.duration,
                charactersProcessed = result.metadata.characterCount,
            )
        } finally {
            withContext(NonCancellable) {
                try { RunAnywhere.unloadTTSVoice() } catch (_: Exception) { }
            }
        }
    }
}

// =============================================================================
// VLM Benchmark Provider
// =============================================================================

private class VLMBenchmarkProvider : BenchmarkScenarioProvider {

    override val category: BenchmarkCategory = BenchmarkCategory.VLM

    override fun scenarios(): List<BenchmarkScenario> = listOf(
        BenchmarkScenario(name = "Solid Red Image", category = BenchmarkCategory.VLM),
        BenchmarkScenario(name = "Gradient Image", category = BenchmarkCategory.VLM),
    )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val memBefore = SyntheticInputGenerator.availableMemoryBytes()

        val loadStart = System.nanoTime()
        RunAnywhere.loadVLMModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            val width = 224
            val height = 224
            val rgbData = if (scenario.name.contains("Solid")) {
                SyntheticInputGenerator.solidColorRgb(width, height)
            } else {
                SyntheticInputGenerator.gradientRgb(width, height)
            }
            val vlmImage = VLMImage.fromRGBPixels(rgbData, width, height)

            // Warmup
            val warmupStart = System.nanoTime()
            val warmupOptions = VLMGenerationOptions(maxTokens = 5, temperature = 0.0f)
            RunAnywhere.processImage(vlmImage, "Hi", warmupOptions)
            val warmupTimeMs = (System.nanoTime() - warmupStart) / 1_000_000.0

            // Benchmark
            val benchOptions = VLMGenerationOptions(maxTokens = 128, temperature = 0.0f)
            val result = RunAnywhere.processImage(
                vlmImage,
                "Describe this image in detail.",
                benchOptions,
            )

            val memAfter = SyntheticInputGenerator.availableMemoryBytes()

            return BenchmarkMetrics(
                endToEndLatencyMs = result.totalTimeMs.toDouble(),
                loadTimeMs = loadTimeMs,
                warmupTimeMs = warmupTimeMs,
                memoryDeltaBytes = memBefore - memAfter,
                tokensPerSecond = result.tokensPerSecond.toDouble(),
                promptTokens = result.promptTokens,
                completionTokens = result.completionTokens,
            )
        } finally {
            withContext(NonCancellable) {
                try { RunAnywhere.unloadVLMModel() } catch (_: Exception) { }
            }
        }
    }
}
