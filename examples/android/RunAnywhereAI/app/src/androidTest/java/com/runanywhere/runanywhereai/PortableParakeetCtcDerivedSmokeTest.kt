package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.ModelUnloadRequest
import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.importModel
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.unloadModel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest

/**
 * Device-only validation for an unpublished, locally derived Parakeet CTC bundle.
 *
 * This is intentionally not a catalog test: the bundle is staged under the
 * isolated test app and registered as MODEL_SOURCE_LOCAL through public APIs.
 */
@RunWith(AndroidJUnit4::class)
class PortableParakeetCtcDerivedSmokeTest {
    private val tag = "PARAKEET_CTC_DERIVED_E2E"

    @Test
    fun importLoadAndTranscribeDerivedBundle() {
        runBlocking {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val targetContext = instrumentation.targetContext
            val rawBundlePath =
                requireNotNull(
                    InstrumentationRegistry.getArguments().getString("localBundlePath")?.takeIf {
                        it.isNotBlank()
                    },
                ) { "-e localBundlePath is required" }
            val bundleRoot = File(rawBundlePath).canonicalFile
            val allowedRoots =
                listOfNotNull(
                    targetContext.filesDir.canonicalFile,
                    targetContext.getExternalFilesDir(null)?.canonicalFile,
                )
            require(allowedRoots.any { bundleRoot.path.startsWith(it.path + File.separator) }) {
                "local bundle must be staged under an isolated app-owned files root"
            }

            awaitSdkReady(180_000)
            logMemory(targetContext, "before_hash")

            val modelFile = verifyFile(bundleRoot, MODEL_FILENAME, MODEL_BYTES, MODEL_SHA256)
            val tokensFile = verifyFile(bundleRoot, TOKENS_FILENAME, TOKENS_BYTES, TOKENS_SHA256)
            val descriptors =
                listOf(
                    descriptor(modelFile, ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL, MODEL_SHA256),
                    descriptor(tokensFile, ModelFileRole.MODEL_FILE_ROLE_VOCABULARY, TOKENS_SHA256),
                )
            assertEquals(BUNDLE_BYTES, descriptors.sumOf { requireNotNull(it.size_bytes) })
            Log.i(
                tag,
                "VERIFIED localOnly=true root=$bundleRoot bundleBytes=$BUNDLE_BYTES " +
                    "modelSha256=$MODEL_SHA256 tokensSha256=$TOKENS_SHA256",
            )

            val registered =
                RunAnywhere.registerModel(
                    multiFile = descriptors,
                    id = MODEL_ID,
                    name = "Derived local Parakeet CTC 1.1B INT8 validation bundle",
                    framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                    modality = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                    memoryRequirement = BUNDLE_BYTES,
                    source = ModelSource.MODEL_SOURCE_LOCAL,
                )
            val imported =
                RunAnywhere.importModel(
                    ModelImportRequest(
                        model = registered.copy(source = ModelSource.MODEL_SOURCE_LOCAL),
                        source_path = bundleRoot.path,
                        copy_into_managed_storage = false,
                        overwrite_existing = true,
                        files = descriptors,
                        validate_before_register = false,
                    ),
                )
            assertTrue(imported.error_message.ifBlank { "local import failed" }, imported.success)
            assertTrue("local import was not registered", imported.registered)
            assertFalse("commons must not claim it copied the local bundle", imported.copied_into_managed_storage)
            assertEquals(bundleRoot.path, imported.local_path)
            assertEquals(BUNDLE_BYTES, imported.imported_bytes)
            val importedModel = requireNotNull(imported.model)
            assertEquals(ModelSource.MODEL_SOURCE_LOCAL, importedModel.source)
            Log.i(
                tag,
                "IMPORT model=${importedModel.id} localOnly=true bytes=${imported.imported_bytes} " +
                    "path=${imported.local_path} warnings=${imported.warnings}",
            )

            var loaded = false
            try {
                logMemory(targetContext, "before_load")
                val loadStarted = System.currentTimeMillis()
                val load = withTimeout(300_000) { RunAnywhere.loadModel(importedModel) }
                val loadMs = System.currentTimeMillis() - loadStarted
                assertTrue(load.error_message.ifBlank { "derived Parakeet CTC load failed" }, load.success)
                assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, load.framework)
                loaded = true
                logMemory(targetContext, "after_load")

                val pcm =
                    instrumentation.context.assets
                        .open("ls16k_libri.pcm")
                        .use { it.readBytes() }
                val audioSeconds = pcm.size / 2.0 / 16_000.0
                val inferenceStarted = System.currentTimeMillis()
                val result = withTimeout(300_000) { RunAnywhere.transcribe(pcm) }
                val inferenceMs = System.currentTimeMillis() - inferenceStarted
                val transcript = result.text.trim()
                val wer = NpuMetrics.wer(REFERENCE_TEXT, transcript)
                val rtf = inferenceMs / 1_000.0 / audioSeconds
                assertTrue("derived Parakeet CTC returned an empty transcript", transcript.isNotBlank())
                assertTrue("derived Parakeet CTC WER $wer exceeds 0.15; transcript=$transcript", wer <= 0.15)
                Log.i(
                    tag,
                    "PASS localOnly=true model=$MODEL_ID bundleBytes=$BUNDLE_BYTES loadMs=$loadMs " +
                        "inferenceMs=$inferenceMs audioSeconds=$audioSeconds rtf=$rtf wer=$wer " +
                        "transcript=\"$transcript\" pssKb=${Debug.getPss()}",
                )
            } finally {
                if (loaded) {
                    val unload =
                        withTimeout(180_000) {
                            RunAnywhere.unloadModel(
                                ModelUnloadRequest(
                                    model_id = MODEL_ID,
                                    category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                                    framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                                ),
                            )
                        }
                    assertTrue(unload.error_message.ifBlank { "derived Parakeet CTC unload failed" }, unload.success)
                    Log.i(tag, "UNLOAD model=$MODEL_ID ids=${unload.unloaded_model_ids}")
                    logMemory(targetContext, "after_unload")
                }
            }
        }
    }

    private fun descriptor(
        file: File,
        role: ModelFileRole,
        sha256: String,
    ): ModelFileDescriptor =
        ModelFileDescriptor(
            url = "local://$MODEL_ID/${file.name}",
            filename = file.name,
            is_required = true,
            size_bytes = file.length(),
            relative_path = file.name,
            local_path = file.path,
            role = role,
            checksum_sha256 = sha256,
        )

    private fun verifyFile(
        root: File,
        filename: String,
        expectedBytes: Long,
        expectedSha256: String,
    ): File {
        val file = File(root, filename).canonicalFile
        require(file.parentFile == root) { "unsafe local filename: $filename" }
        require(file.isFile) { "missing local bundle file: $file" }
        assertEquals("unexpected size for $filename", expectedBytes, file.length())
        assertEquals("unexpected sha256 for $filename", expectedSha256, sha256(file))
        return file
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun logMemory(context: Context, phase: String) {
        val activityManager = context.getSystemService(ActivityManager::class.java)
        val info = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(info)
        Log.i(
            tag,
            "MEMORY phase=$phase availBytes=${info.availMem} totalBytes=${info.totalMem} " +
                "thresholdBytes=${info.threshold} lowMemory=${info.lowMemory} pssKb=${Debug.getPss()}",
        )
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

    private companion object {
        const val MODEL_ID = "local-derived-parakeet-ctc-1.1b-int8"
        const val MODEL_FILENAME = "model.int8.onnx"
        const val MODEL_BYTES = 1_110_014_145L
        const val MODEL_SHA256 = "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98"
        const val TOKENS_FILENAME = "tokens.txt"
        const val TOKENS_BYTES = 10_374L
        const val TOKENS_SHA256 = "ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921"
        const val BUNDLE_BYTES = MODEL_BYTES + TOKENS_BYTES
        const val REFERENCE_TEXT =
            "Mr. Quilter is the apostle of the middle classes, and we are glad to welcome his gospel."
    }
}
