package com.runanywhere.runanywhereai.data.benchmark

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LLMStreamFinalResult
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.VLMImageFormat
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.unloadModel
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
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
// against a fixed set of deterministic scenarios, with a warmup. Metrics are read
// off the SDK results (same fields the chat screen trusts), not estimated.
// Scenarios and the load -> warmup -> measure -> unload flow mirror the iOS
// example's benchmark providers (source of truth).
class BenchmarkRunner(private val context: Context) {

    fun deviceInfo(): BenchDeviceInfo {
        val mi = SyntheticInput.memoryInfo(context)
        return BenchDeviceInfo(Build.MODEL, Build.MANUFACTURER, Build.VERSION.SDK_INT, mi.totalMem, mi.availMem)
    }

    suspend fun run(
        categories: Set<BenchmarkCategory>,
        onProgress: (BenchmarkProgress) -> Unit,
        onResult: (BenchmarkResult) -> Unit,
    ) {
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
        work.forEachIndexed { index, w ->
            onProgress(BenchmarkProgress(index + 1, work.size, w.category, w.scenario, w.model.name))
            val outcome = runCatching {
                when (w.category) {
                    BenchmarkCategory.LLM -> llmRun(w.model, w.maxTokens)
                    BenchmarkCategory.STT -> sttRun(w.model, w.scenario)
                    BenchmarkCategory.TTS -> ttsRun(w.model, w.scenario)
                    BenchmarkCategory.VLM -> vlmRun(w.model)
                }
            }
            onResult(
                outcome.fold(
                    onSuccess = { metrics -> result(w, true, null, metrics) },
                    onFailure = { e ->
                        if (e is kotlin.coroutines.cancellation.CancellationException) throw e
                        result(w, false, e.message ?: "Benchmark failed", BenchmarkMetrics())
                    },
                ),
            )
        }
    }

    private fun result(w: Work, success: Boolean, error: String?, metrics: BenchmarkMetrics) =
        BenchmarkResult(
            category = w.category,
            scenario = w.scenario,
            modelId = w.model.id,
            modelName = w.model.name,
            framework = frameworkName(w.model),
            success = success,
            errorMessage = error,
            metrics = metrics,
        )

    private suspend fun llmRun(model: RAModelInfo, maxTokens: Int): BenchmarkMetrics {
        // Ensure clean state: unload any LLM left over from chat or a previous run.
        unload(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        val loadMs = load(model, ModelCategory.MODEL_CATEGORY_LANGUAGE)
        try {
            val warmupMs = measureMs {
                withTimeoutOrNull(WARMUP_TIMEOUT) {
                    RunAnywhere.generateStream("Hello", RALLMGenerationOptions(max_tokens = 5, temperature = 0f))
                        .collect { }
                }
            }
            var tokens = 0
            var firstTokenNs: Long? = null
            var final: LLMStreamFinalResult? = null
            val start = System.nanoTime()
            withTimeoutOrNull(BENCH_TIMEOUT) {
                RunAnywhere.generateStream(
                    LLM_PROMPT,
                    RALLMGenerationOptions(max_tokens = maxTokens, temperature = 0f, system_prompt = LLM_SYSTEM_PROMPT),
                ).collect { event ->
                    if (event.is_final) {
                        final = event.result
                        return@collect
                    }
                    if (event.token.isNotEmpty()) {
                        if (firstTokenNs == null) firstTokenNs = System.nanoTime()
                        tokens++
                    }
                }
            }
            val e2eMs = (System.nanoTime() - start) / 1_000_000.0
            val r = final
            val outTokens = r?.completion_tokens?.takeIf { it > 0 } ?: tokens
            val memAfter = SyntheticInput.availableMemoryBytes(context)
            return BenchmarkMetrics(
                loadTimeMs = loadMs,
                warmupTimeMs = warmupMs,
                endToEndLatencyMs = r?.total_time_ms?.toDouble()?.takeIf { it > 0 } ?: e2eMs,
                tokensPerSecond = r?.tokens_per_second?.toDouble()?.takeIf { it > 0 }
                    ?: (outTokens * 1000.0 / e2eMs).takeIf { e2eMs > 0 && outTokens > 0 },
                ttftMs = r?.time_to_first_token_ms?.toDouble()?.takeIf { it > 0 }
                    ?: firstTokenNs?.let { (it - start) / 1_000_000.0 },
                inputTokens = r?.prompt_tokens,
                outputTokens = outTokens,
                promptEvalMs = r?.prompt_eval_time_ms?.toDouble()?.takeIf { it > 0 },
                decodeMs = r?.decode_time_ms?.toDouble()?.takeIf { it > 0 },
                memoryDeltaBytes = memBefore - memAfter,
            )
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        }
    }

    private suspend fun sttRun(model: RAModelInfo, scenario: String): BenchmarkMetrics {
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        val loadMs = load(model, ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
        try {
            val silent = scenario.contains("Silent")
            val seconds = if (silent) 2.0 else 3.0
            val pcm = if (silent) SyntheticInput.silentPcm(seconds) else SyntheticInput.sinePcm(seconds)
            val start = System.nanoTime()
            val out = RunAnywhere.transcribe(
                pcm,
                RASTTOptions(
                    language = STTLanguage.STT_LANGUAGE_EN,
                    enable_punctuation = true,
                    enable_word_timestamps = true,
                ),
            )
            val e2eMs = (System.nanoTime() - start) / 1_000_000.0
            val memAfter = SyntheticInput.availableMemoryBytes(context)
            return BenchmarkMetrics(
                loadTimeMs = loadMs,
                endToEndLatencyMs = e2eMs,
                realTimeFactor = out.metadata?.real_time_factor?.toDouble()?.takeIf { it > 0 },
                audioLengthSeconds = seconds,
                memoryDeltaBytes = memBefore - memAfter,
            )
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
        }
    }

    private suspend fun ttsRun(model: RAModelInfo, scenario: String): BenchmarkMetrics {
        val text = if (scenario.contains("Short")) TTS_SHORT else TTS_MEDIUM
        val memBefore = SyntheticInput.availableMemoryBytes(context)
        val loadMs = load(model, ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
        try {
            val start = System.nanoTime()
            val out = RunAnywhere.synthesize(
                text,
                RATTSOptions(
                    language_code = "en-US",
                    speaking_rate = 1f,
                    pitch = 1f,
                    volume = 1f,
                    audio_format = AudioFormat.AUDIO_FORMAT_PCM,
                    sample_rate = 22050,
                ),
            )
            val e2eMs = (System.nanoTime() - start) / 1_000_000.0
            val memAfter = SyntheticInput.availableMemoryBytes(context)
            return BenchmarkMetrics(
                loadTimeMs = loadMs,
                endToEndLatencyMs = e2eMs,
                audioDurationSeconds = out.duration_ms / 1000.0,
                charactersProcessed = out.metadata?.character_count ?: text.length,
                memoryDeltaBytes = memBefore - memAfter,
            )
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
        }
    }

    private suspend fun vlmRun(model: RAModelInfo): BenchmarkMetrics {
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
                // Flush any lingering generation state / KV cache before the real run.
                RunAnywhere.cancelVLMGeneration()
                val result = RunAnywhere.processImage(
                    image,
                    RAVLMGenerationOptions(prompt = VLM_PROMPT, max_tokens = 128, temperature = 0f),
                )
                val memAfter = SyntheticInput.availableMemoryBytes(context)
                return BenchmarkMetrics(
                    loadTimeMs = loadMs,
                    warmupTimeMs = warmupMs,
                    endToEndLatencyMs = result.processing_time_ms.toDouble(),
                    tokensPerSecond = result.tokens_per_second.toDouble().takeIf { it > 0 },
                    ttftMs = result.time_to_first_token_ms.toDouble().takeIf { it > 0 },
                    inputTokens = result.prompt_tokens,
                    outputTokens = result.completion_tokens,
                    memoryDeltaBytes = memBefore - memAfter,
                )
            } finally {
                file.delete()
            }
        } finally {
            unload(ModelCategory.MODEL_CATEGORY_MULTIMODAL, settleMs = VLM_UNLOAD_SETTLE_MS)
        }
    }

    private suspend fun load(model: RAModelInfo, category: ModelCategory): Double {
        val start = System.nanoTime()
        val res = RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id, category = category))
        if (!res.success) throw IllegalStateException(res.error_message.ifBlank { "Model load failed" })
        return (System.nanoTime() - start) / 1_000_000.0
    }

    // Best-effort unload (result ignored, matching iOS). NonCancellable so the model
    // is still released when the benchmark job is cancelled mid-scenario.
    private suspend fun unload(category: ModelCategory, settleMs: Long = 0L) {
        withContext(NonCancellable) {
            RunAnywhere.unloadModel(ModelUnloadRequest(category = category))
            if (settleMs > 0) delay(settleMs)
        }
    }

    private suspend fun modelsFor(category: BenchmarkCategory): List<RAModelInfo> {
        val all = RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
        return all.filter { accepts(category, it) && it.isDownloadedOnDisk && !isBuiltIn(it) }
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
        const val WARMUP_TIMEOUT = 10_000L
        const val BENCH_TIMEOUT = 60_000L
        const val VLM_MEMORY_SETTLE_MS = 500L
        const val VLM_UNLOAD_SETTLE_MS = 300L
    }
}
