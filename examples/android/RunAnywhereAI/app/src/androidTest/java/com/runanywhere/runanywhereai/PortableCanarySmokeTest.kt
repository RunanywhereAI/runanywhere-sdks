package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelUnloadRequest
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.data.MultiFileModel
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.unloadModel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Physical-device public-SDK lifecycle smoke for the exact curated Canary bundle.
 *
 * The isolated test app owns its download; this test deliberately retains the
 * downloaded bundle for inspection while always unloading the active recognizer.
 */
@RunWith(AndroidJUnit4::class)
class PortableCanarySmokeTest {
    private val tag = "PORTABLE_CANARY_E2E"

    @Test
    fun downloadLoadAndTranscribeCatalogCanary() {
        runBlocking {
            awaitSdkReady(180_000)

            val catalog =
                ModelCatalog.models
                    .filterIsInstance<MultiFileModel>()
                    .single { it.id == MODEL_ID }
            val expectedSizes = listOf(132_678_643L, 74_437_848L, 53_555L)
            assertEquals(expectedSizes, catalog.files.map { it.sizeBytes })
            assertEquals(EXPECTED_BUNDLE_BYTES, catalog.files.sumOf { requireNotNull(it.sizeBytes) })

            val registered = catalog.register()
            assertEquals(EXPECTED_BUNDLE_BYTES, registered.download_size_bytes)
            assertEquals(expectedSizes, registered.multi_file?.files?.map { it.size_bytes })
            Log.i(
                tag,
                "REGISTER model=${registered.id} framework=${registered.framework} " +
                    "aggregateBytes=${registered.download_size_bytes} fileBytes=$expectedSizes",
            )

            var loaded = false
            try {
                var lastLoggedPercent = -10
                val downloadStarted = System.currentTimeMillis()
                val terminal =
                    withTimeout(900_000) {
                        RunAnywhere.downloadModel(registered) { progress ->
                            val fraction =
                                if (progress.overall_progress > 0f) {
                                    progress.overall_progress
                                } else {
                                    progress.stage_progress
                                }
                            val percent = (fraction * 100).toInt()
                            if (percent >= lastLoggedPercent + 10 || progress.state.isTerminal) {
                                lastLoggedPercent = percent
                                Log.i(
                                    tag,
                                    "DOWNLOAD state=${progress.state} stage=${progress.stage} " +
                                        "percent=$percent bytes=${progress.bytes_downloaded}/${progress.total_bytes}",
                                )
                            }
                        }
                    }
                val downloadMs = System.currentTimeMillis() - downloadStarted
                assertTrue(
                    "download did not complete: state=${terminal.state} stage=${terminal.stage}",
                    terminal.state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
                        terminal.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED,
                )
                assertEquals(EXPECTED_BUNDLE_BYTES, terminal.total_bytes)

                val loadStarted = System.currentTimeMillis()
                val load = withTimeout(300_000) { RunAnywhere.loadModel(registered) }
                val loadMs = System.currentTimeMillis() - loadStarted
                assertTrue(load.error_message.ifBlank { "Canary load failed" }, load.success)
                assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, load.framework)
                loaded = true

                val pcm =
                    InstrumentationRegistry.getInstrumentation().context.assets
                        .open("ls16k_libri.pcm")
                        .use { it.readBytes() }
                val audioSeconds = pcm.size / 2.0 / 16_000.0
                val inferenceStarted = System.currentTimeMillis()
                val result = withTimeout(300_000) { RunAnywhere.transcribe(pcm) }
                val inferenceMs = System.currentTimeMillis() - inferenceStarted
                val transcript = result.text.trim()
                val wer = NpuMetrics.wer(REFERENCE_TEXT, transcript)
                val rtf = inferenceMs / 1_000.0 / audioSeconds
                assertTrue("Canary returned an empty transcript", transcript.isNotBlank())
                assertTrue("Canary WER $wer exceeds smoke threshold; transcript=$transcript", wer <= 0.15)

                Log.i(
                    tag,
                    "PASS model=$MODEL_ID bundleBytes=${terminal.total_bytes} downloadMs=$downloadMs " +
                        "loadMs=$loadMs inferenceMs=$inferenceMs audioSeconds=$audioSeconds rtf=$rtf " +
                        "wer=$wer transcript=\"$transcript\"",
                )
            } finally {
                if (loaded) {
                    val unload =
                        withTimeout(180_000) {
                            RunAnywhere.unloadModel(
                                ModelUnloadRequest(
                                    model_id = catalog.id,
                                    category = catalog.category,
                                    framework = catalog.framework,
                                ),
                            )
                        }
                    assertTrue(unload.error_message.ifBlank { "Canary unload failed" }, unload.success)
                    Log.i(tag, "UNLOAD model=$MODEL_ID ids=${unload.unloaded_model_ids}")
                }
            }
        }
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

    private val DownloadState.isTerminal: Boolean
        get() =
            this == DownloadState.DOWNLOAD_STATE_COMPLETED ||
                this == DownloadState.DOWNLOAD_STATE_FAILED ||
                this == DownloadState.DOWNLOAD_STATE_CANCELLED

    private companion object {
        const val MODEL_ID = "sherpa-nemo-canary-180m-flash-int8"
        const val EXPECTED_BUNDLE_BYTES = 207_170_046L
        const val REFERENCE_TEXT =
            "Mr. Quilter is the apostle of the middle classes, and we are glad to welcome his gospel."
    }
}
