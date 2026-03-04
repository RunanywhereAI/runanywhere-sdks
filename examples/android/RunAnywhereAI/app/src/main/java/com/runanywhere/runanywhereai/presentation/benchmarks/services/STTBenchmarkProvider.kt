package com.runanywhere.runanywhereai.presentation.benchmarks.services

import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.transcribeWithOptions
import com.runanywhere.sdk.public.extensions.unloadSTTModel
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * Benchmarks STT transcription with synthetic audio inputs.
 * Matches iOS STTBenchmarkProvider exactly.
 */
class STTBenchmarkProvider : BenchmarkScenarioProvider {

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

        // Load
        val loadStart = System.nanoTime()
        RunAnywhere.loadSTTModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0

        try {
            // Generate audio
            val audioDuration: Double
            val audioData: ByteArray
            if (scenario.name.contains("Silent")) {
                audioDuration = 2.0
                audioData = SyntheticInputGenerator.silentAudio(durationSeconds = audioDuration)
            } else {
                audioDuration = 3.0
                audioData = SyntheticInputGenerator.sineWaveAudio(durationSeconds = audioDuration)
            }

            // Transcribe
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
                try {
                    RunAnywhere.unloadSTTModel()
                } catch (_: Exception) {
                }
            }
        }
    }
}
