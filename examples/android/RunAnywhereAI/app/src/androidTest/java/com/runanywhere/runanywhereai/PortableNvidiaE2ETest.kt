package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelUnloadRequest
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.embeddings
import com.runanywhere.sdk.public.api.models
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.unloadModel
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RASTTOptions
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.sqrt

/**
 * Portable-backend (llama.cpp / Sherpa-ONNX) counterpart to [NpuModelE2ETest]: register → download →
 * load → run → delete for one catalog row, driven entirely through the public SDK.
 *
 * Deliberately touches ONLY `CatalogModel.id` and `CatalogModel.register()`. Every other accessor on
 * the app's catalog data classes (`getFiles`, `getName`, `getFramework`, …) is stripped by R8 in the
 * release build, which is what makes [PortableCanarySmokeTest] unrunnable against a release APK.
 *
 * Run:
 *   -e class com.runanywhere.runanywhereai.PortableNvidiaE2ETest
 *   -e modelId <catalog id>
 *   -e mode stt|embed|chat            (default stt)
 *   -e pcmAsset <test-apk asset>      | -e pcmPath <device path>   (stt; 16 kHz mono s16le)
 *   -e reference "<gold text>"        (stt, optional — enables WER)
 *   -e lang en|ja|…                   (stt, optional)
 *   -e prompt "<prompt>"              (chat)
 *   -e keep true                      (skip the delete phase)
 */
@RunWith(AndroidJUnit4::class)
class PortableNvidiaE2ETest {
    private val tag = "PORTABLE_NV_E2E"

    @Test
    fun downloadRunDelete() {
        val args = InstrumentationRegistry.getArguments()
        val modelId = requireNotNull(args.getString("modelId")?.takeIf { it.isNotBlank() }) {
            "-e modelId is required"
        }
        val mode = args.getString("mode")?.takeIf { it.isNotBlank() } ?: "stt"
        val keep = args.getString("keep")?.toBoolean() ?: false
        val fields = LinkedHashMap<String, String>()
        fields["id"] = modelId
        fields["mode"] = mode
        fields["memAvailKbAtStart"] = memAvailableKb().toString()

        var phase = "init"
        var ok = false
        runBlocking {
            try {
                awaitSdkReady(180_000)

                if (mode == "delete") {
                    // Catalog-free teardown so an NPU row (which lives in npuCatalog, not
                    // ModelCatalog.models) can be reclaimed after a NpuLoadOnlyTest run.
                    ok = true
                    return@runBlocking
                }

                phase = "register"
                val catalog = ModelCatalog.models.single { it.id == modelId }
                val registerStarted = System.currentTimeMillis()
                val registered = requireNotNull(catalog.register()) { "register() returned null" }
                fields["registerMs"] = (System.currentTimeMillis() - registerStarted).toString()
                fields["registeredId"] = registered.id
                fields["framework"] = registered.framework.name
                fields["declaredDownloadBytes"] = registered.download_size_bytes.toString()
                fields["declaredMemoryBytes"] = registered.memory_required_bytes.toString()

                phase = "download"
                var lastPercent = -20
                val downloadStarted = System.currentTimeMillis()
                val terminal =
                    withTimeout(1_800_000) {
                        RunAnywhere.downloadModel(registered) { progress ->
                            val fraction =
                                if (progress.overall_progress > 0f) {
                                    progress.overall_progress
                                } else {
                                    progress.stage_progress
                                }
                            val percent = (fraction * 100).toInt()
                            if (percent >= lastPercent + 20) {
                                lastPercent = percent
                                Log.i(
                                    tag,
                                    "DOWNLOAD id=$modelId state=${progress.state} stage=${progress.stage} " +
                                        "percent=$percent bytes=${progress.bytes_downloaded}/${progress.total_bytes}",
                                )
                            }
                        }
                    }
                val downloadMs = System.currentTimeMillis() - downloadStarted
                fields["downloadMs"] = downloadMs.toString()
                fields["downloadedBytes"] = terminal.total_bytes.toString()
                val downloadOk =
                    terminal.state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
                        terminal.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED
                check(downloadOk) { "download did not complete: state=${terminal.state} stage=${terminal.stage}" }
                fields["memAvailKbAfterDownload"] = memAvailableKb().toString()

                phase = "run"
                when (mode) {
                    "embed" -> runEmbed(modelId, fields)
                    "chat" -> runChat(modelId, registered, args, fields)
                    else -> runStt(modelId, registered, args, fields)
                }
                ok = true
            } catch (t: Throwable) {
                fields["failedPhase"] = phase
                fields["error"] = "${t.javaClass.simpleName}: ${t.message?.replace('\n', ' ')}"
            } finally {
                try {
                    if (!keep) {
                        phase = "delete"
                        val deleteStarted = System.currentTimeMillis()
                        val deleted = withTimeout(300_000) { RunAnywhere.deleteModel(modelId) }
                        fields["deleteMs"] = (System.currentTimeMillis() - deleteStarted).toString()
                        fields["deletedBytes"] = deleted.deleted_bytes.toString()
                        fields["filesDeleted"] = deleted.files_deleted.toString()
                        fields["registryUpdated"] = deleted.registry_updated.toString()
                    }
                } catch (t: Throwable) {
                    fields["deleteError"] = "${t.javaClass.simpleName}: ${t.message?.replace('\n', ' ')}"
                }
                fields["memAvailKbAtEnd"] = memAvailableKb().toString()
            }
        }

        fields["status"] = if (ok) "PASS" else "FAIL"
        val line = "PORTABLE_NV " + fields.entries.joinToString(" ") { (k, v) -> "$k=\"$v\"" }
        Log.i(tag, line)
        writeReport(modelId, fields)
        assertTrue(line, ok)
    }

    private suspend fun runStt(
        modelId: String,
        registered: ai.runanywhere.proto.v1.ModelInfo,
        args: android.os.Bundle,
        fields: LinkedHashMap<String, String>,
    ) {
        val loadStarted = System.currentTimeMillis()
        val load = withTimeout(600_000) { RunAnywhere.loadModel(registered) }
        fields["loadMs"] = (System.currentTimeMillis() - loadStarted).toString()
        check(load.success) { load.error_message.ifBlank { "load failed" } }
        fields["loadedFramework"] = load.framework.name
        fields["memAvailKbAfterLoad"] = memAvailableKb().toString()

        val pcm = readPcm(args)
        val audioSeconds = pcm.size / 2.0 / 16_000.0
        fields["audioBytes"] = pcm.size.toString()
        fields["audioSeconds"] = String.format("%.3f", audioSeconds)

        val language = args.getString("lang")?.takeIf { it.isNotBlank() }
        val options =
            RASTTOptions.defaults().let { defaults ->
                if (language == null) {
                    defaults
                } else {
                    defaults.copy(language = language)
                }
            }

        try {
            val inferStarted = System.currentTimeMillis()
            val result = withTimeout(900_000) { RunAnywhere.transcribe(pcm, options) }
            val inferMs = System.currentTimeMillis() - inferStarted
            val transcript = result.text.trim()
            fields["inferMs"] = inferMs.toString()
            fields["rtf"] = String.format("%.4f", inferMs / 1_000.0 / audioSeconds)
            fields["transcriptChars"] = transcript.length.toString()
            fields["u2581Count"] = transcript.count { it == '\u2581' }.toString()
            fields["transcript"] = transcript.replace('\n', ' ')
            check(transcript.isNotBlank()) { "empty transcript" }
            args.getString("reference")?.takeIf { it.isNotBlank() }?.let { reference ->
                fields["reference"] = reference
                fields["wer"] = String.format("%.4f", NpuMetrics.wer(reference, transcript))
            }
        } finally {
            runCatching {
                withTimeout(300_000) {
                    RunAnywhere.unloadModel(
                        ModelUnloadRequest(
                            model_id = modelId,
                            category = registered.category,
                            framework = registered.framework,
                        ),
                    )
                }
            }
        }
    }

    private suspend fun runEmbed(modelId: String, fields: LinkedHashMap<String, String>) {
        val query = "query: Which planet is known as the Red Planet?"
        val positive = "passage: Mars is commonly called the Red Planet because of iron oxide on its surface."
        val negative = "passage: The Pacific Ocean is the largest ocean on Earth."
        try {
            val firstStarted = System.currentTimeMillis()
            RunAnywhere.models.load(modelId)
            val queryVector = embedOne(query)
            // The load is explicit in v3, so this span still covers load + first embed.
            fields["firstEmbedMsIncludingLoad"] = (System.currentTimeMillis() - firstStarted).toString()
            fields["memAvailKbAfterLoad"] = memAvailableKb().toString()
            val warmStarted = System.currentTimeMillis()
            val positiveVector = embedOne(positive)
            val negativeVector = embedOne(negative)
            fields["twoWarmEmbedsMs"] = (System.currentTimeMillis() - warmStarted).toString()

            val vectors = listOf(queryVector, positiveVector, negativeVector)
            fields["dims"] = vectors.joinToString(",") { it.size.toString() }
            fields["norms"] = vectors.joinToString(",") { String.format("%.6f", l2Norm(it)) }
            val positiveCosine = cosine(queryVector, positiveVector)
            val negativeCosine = cosine(queryVector, negativeVector)
            fields["positiveCosine"] = String.format("%.6f", positiveCosine)
            fields["negativeCosine"] = String.format("%.6f", negativeCosine)
            fields["margin"] = String.format("%.6f", positiveCosine - negativeCosine)
            fields["allFinite"] = vectors.all { v -> v.all(Float::isFinite) }.toString()
            check(vectors.all { v -> v.all(Float::isFinite) }) { "non-finite embedding value" }
            check(positiveCosine > negativeCosine) { "distractor outranked the related passage" }
        } finally {
            runCatching {
                withTimeout(300_000) {
                    RunAnywhere.models.unload(ModelCategory.MODEL_CATEGORY_EMBEDDING)
                }
            }
        }
    }

    private suspend fun runChat(
        modelId: String,
        registered: ai.runanywhere.proto.v1.ModelInfo,
        args: android.os.Bundle,
        fields: LinkedHashMap<String, String>,
    ) {
        val prompt = args.getString("prompt")?.takeIf { it.isNotBlank() }
            ?: "In one sentence, what is a neural processing unit?"
        val maxNew = args.getString("maxNew")?.toIntOrNull() ?: 64
        val loadStarted = System.currentTimeMillis()
        val load = withTimeout(900_000) { RunAnywhere.loadModel(registered) }
        fields["loadMs"] = (System.currentTimeMillis() - loadStarted).toString()
        check(load.success) { load.error_message.ifBlank { "load failed" } }
        fields["loadedFramework"] = load.framework.name
        fields["memAvailKbAfterLoad"] = memAvailableKb().toString()
        try {
            val systemPrompt = args.getString("sys")?.takeIf { it.isNotBlank() }
            val options =
                RALLMGenerationOptions(
                    max_output_tokens = maxNew,
                    temperature = 0f,
                    top_p = 1f,
                    system_prompt = systemPrompt,
                )
            fields["systemPrompt"] = systemPrompt ?: "<none>"
            val text = StringBuilder()
            var promptTokens = 0
            var completionTokens = 0
            val inferStarted = System.currentTimeMillis()
            withTimeout(900_000) {
                RunAnywhere.generateStream(prompt, options).collect { event ->
                    event.token?.let { if (it.isNotEmpty()) text.append(it) }
                    if (event.is_final) {
                        event.result?.let {
                            promptTokens = it.input_tokens
                            completionTokens = it.output_tokens
                        }
                    }
                }
            }
            val inferMs = System.currentTimeMillis() - inferStarted
            fields["prompt"] = prompt
            fields["inferMs"] = inferMs.toString()
            fields["promptTokens"] = promptTokens.toString()
            fields["completionTokens"] = completionTokens.toString()
            if (completionTokens > 0) {
                fields["tokensPerSecond"] = String.format("%.2f", completionTokens * 1000.0 / inferMs)
            }
            val out = text.toString().trim().replace('\n', ' ')
            fields["output"] = out.take(600)
            check(out.isNotBlank()) { "empty generation" }
        } finally {
            runCatching {
                withTimeout(300_000) {
                    RunAnywhere.unloadModel(
                        ModelUnloadRequest(
                            model_id = modelId,
                            category = registered.category,
                            framework = registered.framework,
                        ),
                    )
                }
            }
        }
    }

    private suspend fun embedOne(text: String): FloatArray =
        withTimeout(600_000) { RunAnywhere.embeddings.embed(listOf(text)) }
            .single()
            .vector

    private fun readPcm(args: android.os.Bundle): ByteArray {
        args.getString("pcmPath")?.takeIf { it.isNotBlank() }?.let { return File(it).readBytes() }
        val asset = args.getString("pcmAsset")?.takeIf { it.isNotBlank() } ?: "ls16k_libri.pcm"
        return InstrumentationRegistry.getInstrumentation().context.assets
            .open(asset)
            .use { it.readBytes() }
    }

    private fun writeReport(modelId: String, fields: Map<String, String>) {
        val dir =
            InstrumentationRegistry.getInstrumentation().targetContext
                .getExternalFilesDir(null)
                ?.let { File(it, "portable_nv") }
                ?: return
        dir.mkdirs()
        val json =
            fields.entries.joinToString(",\n  ", prefix = "{\n  ", postfix = "\n}") { (k, v) ->
                "\"$k\": \"${v.replace("\\", "\\\\").replace("\"", "\\\"")}\""
            }
        File(dir, "portable_nv_$modelId.json").writeText(json)
    }

    private fun awaitSdkReady(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (GlobalState.ready) return
            GlobalState.initError?.let { error("SDK init failed: $it") }
            Thread.sleep(500)
        }
        error("SDK not ready within ${timeoutMs}ms")
    }

    private fun memAvailableKb(): Long =
        runCatching {
            File("/proc/meminfo").readLines()
                .first { it.startsWith("MemAvailable:") }
                .filter { it.isDigit() }
                .toLong()
        }.getOrDefault(-1L)

    private fun l2Norm(vector: FloatArray): Double = sqrt(vector.sumOf { it.toDouble() * it })

    private fun cosine(a: FloatArray, b: FloatArray): Double {
        require(a.size == b.size)
        var dot = 0.0
        var aSquared = 0.0
        var bSquared = 0.0
        for (index in a.indices) {
            dot += a[index].toDouble() * b[index]
            aSquared += a[index].toDouble() * a[index]
            bSquared += b[index].toDouble() * b[index]
        }
        return dot / (sqrt(aSquared) * sqrt(bSquared))
    }
}
