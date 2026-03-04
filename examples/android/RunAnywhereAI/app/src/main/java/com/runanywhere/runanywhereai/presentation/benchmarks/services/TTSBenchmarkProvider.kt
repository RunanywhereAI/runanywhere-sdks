package com.runanywhere.runanywhereai.presentation.benchmarks.services

import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.unloadTTSVoice
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * Benchmarks TTS synthesis with short and medium text inputs.
 * Matches iOS TTSBenchmarkProvider exactly.
 */
class TTSBenchmarkProvider : BenchmarkScenarioProvider {

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

        // Load (TTS uses "voice" API on Kotlin)
        val loadStart = System.nanoTime()
        RunAnywhere.loadTTSVoice(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            // Synthesize (not speak)
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
                try {
                    RunAnywhere.unloadTTSVoice()
                } catch (_: Exception) {
                }
            }
        }
    }
}
