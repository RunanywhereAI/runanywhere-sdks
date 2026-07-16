package com.runanywhere.runanywhereai.data.benchmark

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.VLMImageFormat
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import com.runanywhere.runanywhereai.ui.screens.models.LlmModelChangeInterlock
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.aggregateStream
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.unloadModel
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.FileOutputStream

// Runs the benchmark suite: every downloaded model of each selected category, each
// against a fixed set of deterministic scenarios. Each (model x scenario) is loaded
// and warmed up ONCE, then measured over `trials` repeated passes whose per-metric
// median is reported with an observed min/max range (variance). Metrics are read off
// the SDK results (same fields the chat screen trusts), never estimated.
//
// The LLM path uses generateStream + aggregateStream (not one-shot generate) so TTFT
// has a client-side first-token fallback when the backend does not surface it —
// matching the iOS example (the source of truth). Scenarios and the
// load -> warmup -> measure -> unload flow also mirror the iOS providers.
class BenchmarkRunner(private val context: Context) {

    fun deviceInfo(): BenchDeviceInfo {
        val mi = SyntheticInput.memoryInfo(context)
        return BenchDeviceInfo(
            device = Build.MODEL,
            manufacturer = Build.MANUFACTURER,
            androidSdk = Build.VERSION.SDK_INT,
            totalRamBytes = mi.totalMem,
            availableRamBytes = mi.availMem,
            chipset = socName(),
        )
    }

    // Best-effort SoC / chipset name. Build.SOC_MODEL/SOC_MANUFACTURER are API 31+;
    // fall back to Build.HARDWARE on older devices or when the SoC is not reported.
    private fun socName(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val parts = listOf(Build.SOC_MANUFACTURER, Build.SOC_MODEL)
                .filter { it.isNotBlank() && !it.equals("unknown", ignoreCase = true) }
            if (parts.isNotEmpty()) return parts.joinToString(" ")
        }
        return Build.HARDWARE.orEmpty()
    }

    suspend fun run(
        categories: Set<BenchmarkCategory>,
        trials: Int,
        onProgress: (BenchmarkProgress) -> Unit,
        onResult: (BenchmarkResult) -> Unit,
    ) {
        val trialCount = trials.coerceAtLeast(1)
        val work = buildList {
            for (category in BenchmarkCategory.entries.filter { it in categories }) {
                val models = modelsFor(category)
                for (model in models) {
                    for ((scenario, maxTokens) in scenariosFor(category)) {
                        add(Work(category, model, scenario, maxTokens))
                    }
                }
            }
        }
        check(work.isNotEmpty()) {
            "No downloaded models match the selected benchmark categories. Download a model first."
        }
        work.forEachIndexed { index, w ->
            onProgress(BenchmarkProgress(index + 1, work.size, w.category, w.scenario, w.model.name))
            val outcome = runCatching {
                when (w.category) {
                    BenchmarkCategory.LLM -> llmRun(w.model, w.maxTokens, trialCount)
                    BenchmarkCategory.STT -> sttRun(w.model, w.scenario, trialCount)
                    BenchmarkCategory.TTS -> ttsRun(w.model, w.scenario, trialCount)
                    BenchmarkCategory.VLM -> vlmRun(w.model, trialCount)
                }
            }
            onResult(
                outcome.fold(
                    onSuccess = { agg -> result(w, true, null, agg) },
                    onFailure = { e ->
                        if (e is kotlin.coroutines.cancellation.CancellationException) throw e
                        result(w, false, e.message ?: "Benchmark failed", AggregatedBenchmark(BenchmarkMetrics(), null))
                    },
                ),
            )
        }
    }

    private fun result(w: Work, success: Boolean, error: String?, agg: AggregatedBenchmark) =
        BenchmarkResult(
            category = w.category,
            scenario = w.scenario,
            modelId = w.model.id,
            modelName = w.model.name,
            framework = frameworkName(w.model),
            success = success,
            errorMessage = error,
            metrics = agg.metrics,
            trials = agg.variance?.trials ?: 1,
            variance = agg.variance,
        )

    private suspend fun llmRun(model: RAModelInfo, maxTokens: Int, trials: Int): AggregatedBenchmark {
        // Ensure clean state: unload any LLM left over from chat or a previous run.
        unload(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        val loadMs = load(model, ModelCategory.MODEL_CATEGORY_LANGUAGE)
        try {
            val warmupMs = measureMs { warmupLlm() }
            val perTrial = ArrayList<BenchmarkMetrics>(trials)
            repeat(trials) {
                val (measured, e2eMs) = measureLlm(maxTokens)
                val memAfter = SyntheticInput.availableMemoryBytes(context)
                perTrial += llmBenchmarkMetrics(
                    result = measured,
                    loadTimeMs = loadMs,
                    warmupTimeMs = warmupMs,
                    measuredEndToEndMs = e2eMs,
                    memoryDeltaBytes = memBefore - memAfter,
                ).requireSuccessfulOutput(BenchmarkCategory.LLM)
            }
            return aggregateTrials(perTrial)
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        }
    }

    // One short generation to warm caches / JIT before the measured passes. Timed by
    // the caller; its output is validated but never contributes to reported metrics.
    private suspend fun warmupLlm() {
        val warmup = withTimeoutOrNull(WARMUP_TIMEOUT) {
            withContext(Dispatchers.Default) {
                RunAnywhere.generate(
                    "Hello",
                    RALLMGenerationOptions(max_tokens = 5, temperature = 0f),
                )
            }
        } ?: throw IllegalStateException("LLM benchmark warmup timed out")
        check(warmup.error_message.isNullOrBlank()) {
            warmup.error_message ?: "LLM benchmark warmup failed"
        }
        check(warmup.tokens_generated > 0) {
            "LLM benchmark warmup produced zero output tokens"
        }
    }

    // One measured generation via the streaming path so aggregateStream can supply a
    // wall-clock TTFT fallback when the backend omits it (parity with iOS).
    private suspend fun measureLlm(maxTokens: Int): Pair<RALLMGenerationResult, Double> {
        val options = RALLMGenerationOptions(
            max_tokens = maxTokens,
            temperature = 0f,
            system_prompt = LLM_SYSTEM_PROMPT,
        )
        val start = System.nanoTime()
        val measured = withTimeoutOrNull(BENCH_TIMEOUT) {
            withContext(Dispatchers.Default) {
                RunAnywhere.aggregateStream(
                    prompt = LLM_PROMPT,
                    events = RunAnywhere.generateStream(LLM_PROMPT, options),
                )
            }
        } ?: throw IllegalStateException("LLM benchmark timed out")
        val e2eMs = (System.nanoTime() - start) / 1_000_000.0
        return measured to e2eMs
    }

    private suspend fun sttRun(model: RAModelInfo, scenario: String, trials: Int): AggregatedBenchmark {
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        val loadMs = load(model, ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
        try {
            val silent = scenario.contains("Silent")
            val seconds = if (silent) 2.0 else 3.0
            val pcm = if (silent) SyntheticInput.silentPcm(seconds) else SyntheticInput.sinePcm(seconds)
            val options = RASTTOptions(
                language = STTLanguage.STT_LANGUAGE_EN,
                enable_punctuation = true,
                enable_word_timestamps = true,
            )
            // Warmup: one discarded transcription so first-run cache/JIT cost is not
            // charged to the first measured pass (parity with the LLM/VLM warmup).
            val warmupMs = measureMs {
                runCatching { RunAnywhere.transcribe(SyntheticInput.silentPcm(WARMUP_AUDIO_SECONDS), options) }
            }
            val perTrial = ArrayList<BenchmarkMetrics>(trials)
            repeat(trials) {
                val start = System.nanoTime()
                val out = RunAnywhere.transcribe(pcm, options)
                val e2eMs = (System.nanoTime() - start) / 1_000_000.0
                val memAfter = SyntheticInput.availableMemoryBytes(context)
                perTrial += BenchmarkMetrics(
                    loadTimeMs = loadMs,
                    warmupTimeMs = warmupMs,
                    endToEndLatencyMs = e2eMs,
                    realTimeFactor = out.metadata?.real_time_factor?.toDouble()?.takeIf { it > 0 },
                    audioLengthSeconds = seconds,
                    memoryDeltaBytes = memBefore - memAfter,
                )
            }
            return aggregateTrials(perTrial)
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
        }
    }

    private suspend fun ttsRun(model: RAModelInfo, scenario: String, trials: Int): AggregatedBenchmark {
        val text = if (scenario.contains("Short")) TTS_SHORT else TTS_MEDIUM
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        val loadMs = load(model, ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
        try {
            val options = RATTSOptions(
                language_code = "en-US",
                speaking_rate = 1f,
                pitch = 1f,
                volume = 1f,
                audio_format = AudioFormat.AUDIO_FORMAT_PCM,
                sample_rate = 22050,
            )
            // Warmup: one discarded synthesis so first-run cache/JIT cost is excluded.
            val warmupMs = measureMs {
                runCatching { RunAnywhere.synthesize(TTS_WARMUP, options) }
            }
            val perTrial = ArrayList<BenchmarkMetrics>(trials)
            repeat(trials) {
                val start = System.nanoTime()
                val out = RunAnywhere.synthesize(text, options)
                val e2eMs = (System.nanoTime() - start) / 1_000_000.0
                val memAfter = SyntheticInput.availableMemoryBytes(context)
                perTrial += BenchmarkMetrics(
                    loadTimeMs = loadMs,
                    warmupTimeMs = warmupMs,
                    endToEndLatencyMs = e2eMs,
                    audioDurationSeconds = out.duration_ms / 1000.0,
                    charactersProcessed = out.metadata?.character_count ?: text.length,
                    memoryDeltaBytes = memBefore - memAfter,
                )
            }
            return aggregateTrials(perTrial)
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
        }
    }

    private suspend fun vlmRun(model: RAModelInfo, trials: Int): AggregatedBenchmark {
        // Ensure clean state: unload any leftover VLM plus any lingering LLM to free
        // memory headroom, then give the OS a moment to reclaim it before measuring.
        unload(ModelCategory.MODEL_CATEGORY_MULTIMODAL)
        unload(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        delay(VLM_MEMORY_SETTLE_MS)
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        try {
            val loadMs = load(model, ModelCategory.MODEL_CATEGORY_MULTIMODAL)
            val file = withContext(Dispatchers.IO) { writeJpeg(SyntheticInput.gradientImage()) }
            try {
                val image = RAVLMImage(file_path = file.absolutePath, format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH)
                val warmupMs = measureMs {
                    runCatching {
                        RunAnywhere.processImage(image, RAVLMGenerationOptions(prompt = "Hi", max_tokens = 1, temperature = 0f))
                    }
                }
                val perTrial = ArrayList<BenchmarkMetrics>(trials)
                repeat(trials) {
                    // Flush any lingering generation state / KV cache before each measured run.
                    RunAnywhere.cancelVLMGeneration()
                    val result = RunAnywhere.processImage(
                        image,
                        RAVLMGenerationOptions(prompt = VLM_PROMPT, max_tokens = 128, temperature = 0f),
                    )
                    val memAfter = SyntheticInput.availableMemoryBytes(context)
                    perTrial += BenchmarkMetrics(
                        loadTimeMs = loadMs,
                        warmupTimeMs = warmupMs,
                        endToEndLatencyMs = result.processing_time_ms.toDouble(),
                        tokensPerSecond = result.tokens_per_second.toDouble().takeIf { it > 0 },
                        ttftMs = result.time_to_first_token_ms.toDouble().takeIf { it > 0 },
                        inputTokens = result.prompt_tokens,
                        outputTokens = result.completion_tokens,
                        memoryDeltaBytes = memBefore - memAfter,
                    ).requireSuccessfulOutput(BenchmarkCategory.VLM)
                }
                return aggregateTrials(perTrial)
            } finally {
                file.delete()
            }
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_MULTIMODAL, settleMs = VLM_UNLOAD_SETTLE_MS)
        }
    }

    private suspend fun load(model: RAModelInfo, category: ModelCategory): Double {
        if (category == ModelCategory.MODEL_CATEGORY_LANGUAGE) {
            LlmModelChangeInterlock.awaitReadyForModelChange()
        }
        val start = System.nanoTime()
        val res = RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id, category = category))
        if (!res.success) throw IllegalStateException(res.error_message.ifBlank { "Model load failed" })
        RuntimeModelSelection.queryCurrent(selectionContext(category), listOf(model))
        return (System.nanoTime() - start) / 1_000_000.0
    }

    // Best-effort unload (result ignored, matching iOS). NonCancellable so the model
    // is still released when the benchmark job is cancelled mid-scenario.
    private suspend fun unload(category: ModelCategory, settleMs: Long = 0L) {
        withContext(NonCancellable) {
            if (category == ModelCategory.MODEL_CATEGORY_LANGUAGE) {
                LlmModelChangeInterlock.awaitReadyForModelChange()
            }
            RunAnywhere.unloadModel(ModelUnloadRequest(category = category))
            RuntimeModelSelection.queryCurrent(selectionContext(category))
            if (settleMs > 0) delay(settleMs)
        }
    }

    private fun selectionContext(category: ModelCategory): ModelSelectionContext = when (category) {
        ModelCategory.MODEL_CATEGORY_LANGUAGE -> ModelSelectionContext.LLM
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> ModelSelectionContext.STT
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> ModelSelectionContext.TTS
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ModelCategory.MODEL_CATEGORY_VISION,
        -> ModelSelectionContext.VLM
        else -> error("Unsupported benchmark lifecycle category: $category")
    }

    private suspend fun modelsFor(category: BenchmarkCategory): List<RAModelInfo> {
        val all = RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
        return all.filter { accepts(category, it) && it.isDownloadedOnDisk && !isBuiltIn(it) }
    }

    // True when at least one non-built-in model is downloaded on disk for any of the
    // given categories — used to guide the user to the model screen when none exist.
    suspend fun hasDownloadedModels(categories: Set<BenchmarkCategory>): Boolean {
        val all = RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
        return all.any { model ->
            model.isDownloadedOnDisk && !isBuiltIn(model) &&
                categories.any { accepts(it, model) }
        }
    }

    private fun accepts(category: BenchmarkCategory, model: RAModelInfo): Boolean = when (category) {
        BenchmarkCategory.LLM -> model.category == ModelCategory.MODEL_CATEGORY_LANGUAGE
        BenchmarkCategory.STT -> model.category == ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        BenchmarkCategory.TTS -> model.category == ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        BenchmarkCategory.VLM -> model.category == ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
            model.category == ModelCategory.MODEL_CATEGORY_VISION
    }

    private fun scenariosFor(category: BenchmarkCategory): List<Pair<String, Int>> = when (category) {
        BenchmarkCategory.LLM -> listOf("Short (50 tokens)" to 50, "Medium (256 tokens)" to 256, "Long (512 tokens)" to 512)
        BenchmarkCategory.STT -> listOf("Silent 2s" to 0, "Sine Tone 3s" to 0)
        BenchmarkCategory.TTS -> listOf("Short Text" to 0, "Medium Text" to 0)
        BenchmarkCategory.VLM -> listOf("Image Description" to 0)
    }

    private fun isBuiltIn(model: RAModelInfo): Boolean =
        model.framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
            model.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

    private fun frameworkName(model: RAModelInfo): String =
        model.framework.name.removePrefix("INFERENCE_FRAMEWORK_").lowercase().replace('_', ' ')

    private fun writeJpeg(bitmap: Bitmap): File {
        val file = File.createTempFile("bench_", ".jpg", context.cacheDir)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return file
    }

    private suspend fun measureMs(block: suspend () -> Unit): Double {
        val start = System.nanoTime()
        block()
        return (System.nanoTime() - start) / 1_000_000.0
    }

    private data class Work(
        val category: BenchmarkCategory,
        val model: RAModelInfo,
        val scenario: String,
        val maxTokens: Int,
    )

    private companion object {
        const val LLM_SYSTEM_PROMPT = "You are a helpful assistant. Always give extremely detailed, " +
            "thorough responses. Never stop early. Use the full response length available " +
            "to you. Elaborate on every point with examples and explanations."
        const val LLM_PROMPT = "Write a very long and detailed explanation of how neural networks work, " +
            "covering perceptrons, activation functions, backpropagation, gradient descent, " +
            "loss functions, convolutional layers, recurrent layers, transformers, attention " +
            "mechanisms, and training procedures. Be as thorough as possible."
        const val VLM_PROMPT = "Describe this image in detail."
        const val TTS_SHORT = "Hello, this is a test."
        const val TTS_MEDIUM =
            "The quick brown fox jumps over the lazy dog. Machine learning models can " +
                "generate speech from text with remarkable quality and natural intonation."
        const val TTS_WARMUP = "Hi."
        const val WARMUP_AUDIO_SECONDS = 0.5
        const val WARMUP_TIMEOUT = 30_000L
        // Generous per-generation ceiling: a slow 1-bit model can need ~1 min for the
        // 512-token scenario, so 60s truncated real runs. This bounds a genuinely hung
        // backend without failing legitimately slow decodes (iOS has no such cap).
        const val BENCH_TIMEOUT = 180_000L
        const val VLM_MEMORY_SETTLE_MS = 500L
        const val VLM_UNLOAD_SETTLE_MS = 300L
    }
}
