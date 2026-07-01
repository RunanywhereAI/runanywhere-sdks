package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelSource
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.npu.NPU_MODELS
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModel
import com.runanywhere.runanywhereai.ui.screens.npu.category
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.aggregateStream
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.fromFilePath
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Throwaway on-device end-to-end check for one NPU model, selected by the
 * `modelId` instrumentation arg. Drives the real SDK exactly like the app:
 * register -> download -> load -> run a modality-appropriate inference -> delete.
 *
 * NOT part of the product. Run via the `run_npu_e2e.sh` loop; emits a single
 * `NPU_E2E <key>=<val> ...` line to logcat that the runner greps for.
 */
@RunWith(AndroidJUnit4::class)
class NpuModelE2ETest {

    private val tag = "NPU_E2E"

    private companion object {
        // No download timeout on purpose: large models on a throttled link can take
        // a long time and that is NOT a failure. Only compute (load/infer) is bounded,
        // since a stuck NPU op is a real failure rather than a slow transfer.
        const val LOAD_TIMEOUT_MS = 300_000L
        const val INFER_TIMEOUT_MS = 300_000L
    }

    @Test
    fun runOne() {
        val args = InstrumentationRegistry.getArguments()
        val modelId = args.getString("modelId")
            ?: error("missing -e modelId <id>")
        val report = StringBuilder("NPU_E2E id=$modelId")

        val model = NPU_MODELS.firstOrNull { it.id == modelId }
        if (model == null) {
            emit(report, status = "FAIL", phase = "lookup", detail = "not in catalog")
            return
        }

        try {
            awaitSdkReady(timeoutMs = 180_000)
        } catch (e: Exception) {
            emit(report, status = "FAIL", phase = "init", detail = e.message ?: "sdk not ready")
            return
        }

        runBlocking {
            // ----- register -----
            val registered = try {
                register(model)
            } catch (e: Exception) {
                emit(report, "FAIL", "register", e.message ?: "register failed")
                return@runBlocking
            }

            // ----- download (unbounded — size, not time, drives this) -----
            val dlStart = System.currentTimeMillis()
            try {
                var lastLog = 0
                RunAnywhere.downloadModel(registered) { p ->
                    val pct = ((if (p.overall_progress > 0f) p.overall_progress else p.stage_progress) * 100).toInt()
                    if (pct >= lastLog + 20) { lastLog = pct; Log.i(tag, "$modelId download $pct%") }
                }
            } catch (e: Exception) {
                emit(report, "FAIL", "download", e.message ?: "download failed")
                cleanup(model); return@runBlocking
            }
            val dlSec = (System.currentTimeMillis() - dlStart) / 1000
            report.append(" download_s=$dlSec")

            // ----- load -----
            try {
                val r = withTimeout(LOAD_TIMEOUT_MS) {
                    RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id))
                }
                if (!r.success) {
                    emit(report, "FAIL", "load", r.error_message.ifBlank { "load returned success=false" })
                    cleanup(model); return@runBlocking
                }
            } catch (e: TimeoutCancellationException) {
                emit(report, "FAIL", "load", "timeout after ${LOAD_TIMEOUT_MS / 1000}s")
                cleanup(model); return@runBlocking
            } catch (e: Exception) {
                emit(report, "FAIL", "load", e.message ?: "load threw")
                cleanup(model); return@runBlocking
            }

            // ----- inference -----
            try {
                val out = withTimeout(INFER_TIMEOUT_MS) { infer(model) }
                report.append(" out_len=${out.length}")
                if (out.isBlank()) {
                    emit(report, "FAIL", "infer", "empty output")
                } else {
                    report.append(" sample=\"${out.take(80).replace('\n', ' ')}\"")
                    emit(report, "PASS", "infer", "ok")
                }
            } catch (e: TimeoutCancellationException) {
                emit(report, "FAIL", "infer", "timeout after ${INFER_TIMEOUT_MS / 1000}s")
            } catch (e: Exception) {
                emit(report, "FAIL", "infer", e.message ?: "inference threw")
            } finally {
                cleanup(model)
            }
        }
    }

    private suspend fun infer(model: NpuModel): String = when (model.modality) {
        NpuModality.LLM -> {
            val opts = RALLMGenerationOptions(
                max_tokens = 64,
                temperature = 0.7f,
                disable_thinking = true,
            )
            val prompt = "What is 2 + 2? Answer in one short sentence."
            val events = RunAnywhere.generateStream(prompt, opts)
            RunAnywhere.aggregateStream(prompt, events).text
        }
        NpuModality.VLM -> {
            // QHexRT consumes the image by file path (it decodes the container
            // itself); spool the asset into the app cache and hand over the path.
            val bytes = testAsset("test.jpg")
            val ctx = InstrumentationRegistry.getInstrumentation().targetContext
            val file = java.io.File(ctx.cacheDir, "vlm_test_input.jpg")
            file.writeBytes(bytes)
            val image = RAVLMImage.fromFilePath(file.absolutePath)
            RunAnywhere.processImage(image, RAVLMGenerationOptions(prompt = "Describe this image.", max_tokens = 64)).text
        }
        NpuModality.STT -> {
            val pcm = testAsset("speech_16k_mono.pcm")
            RunAnywhere.transcribe(pcm).text
        }
        NpuModality.TTS -> {
            val out = RunAnywhere.synthesize("Hello from the on device test.")
            if (out.audio_data.size > 0) "audio:${out.audio_data.size}bytes" else ""
        }
    }

    private suspend fun register(model: NpuModel) =
        if (model.files.isNotEmpty()) {
            RunAnywhere.registerModel(
                multiFile = model.files.mapIndexed { idx, f ->
                    ModelFileDescriptor(
                        url = f.url,
                        filename = f.filename,
                        is_required = true,
                        role = if (idx == 0) ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                        else ModelFileRole.MODEL_FILE_ROLE_COMPANION,
                    )
                },
                id = model.id,
                name = model.name,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = model.modality.category(),
                source = ModelSource.MODEL_SOURCE_REMOTE,
            )
        } else {
            RunAnywhere.registerModel(
                archiveUrl = model.resolvedArchiveUrl,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
                id = model.id,
                name = model.name,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = model.modality.category(),
                archiveType = ArchiveType.ARCHIVE_TYPE_ZIP,
            )
        }

    private suspend fun cleanup(model: NpuModel) {
        runCatching { RunAnywhere.deleteModel(model.id) }
    }

    private fun testAsset(name: String): ByteArray =
        InstrumentationRegistry.getInstrumentation().context.assets.open(name).use { it.readBytes() }

    private fun awaitSdkReady(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (GlobalState.ready) return
            GlobalState.initError?.let { error("SDK init failed: $it") }
            Thread.sleep(500)
        }
        error("SDK not ready within ${timeoutMs}ms")
    }

    private fun emit(sb: StringBuilder, status: String, phase: String, detail: String) {
        sb.append(" status=$status phase=$phase detail=\"$detail\"")
        Log.i(tag, sb.toString())
    }
}
