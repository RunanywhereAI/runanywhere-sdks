package com.runanywhere.runanywhereai

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.fromFilePath
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Local-iteration only (a SEPARATE class from [NpuModelE2ETest] so `-e class NpuModelE2ETest` with no
 * `#method` — the standard QHexRT/device_suites/run_android_e2e.sh invocation — still runs exactly one
 * test): load an ALREADY
 * registered/downloaded model_id directly and synthesize, skipping register()/downloadModel() entirely.
 * Used to test a manifest hand-staged into the model's on-device directory via adb (e.g. a new capability
 * not yet published to HF), without a normal registerModel() call re-downloading over the hand-staged files.
 *
 * Run: -e class com.runanywhere.runanywhereai.NpuLoadOnlyTest -e modelId <id> -e text "<text>"
 */
@RunWith(AndroidJUnit4::class)
class NpuLoadOnlyTest {
    private val tag = "NPU_E2E"

    @Test
    fun loadOnly() {
        val args = InstrumentationRegistry.getArguments()
        val modelId = args.getString("modelId") ?: return
        val text = args.getString("text") ?: "Hexagon neural processing unit."
        val mode = args.getString("mode") ?: "tts"
        val maxNew = args.getString("maxNew")?.toIntOrNull() ?: 64
        val outDir = InstrumentationRegistry.getInstrumentation().targetContext
            .getExternalFilesDir(null)?.let { File(it, "npu_e2e") }
        var line = "NPU_E2E id=$modelId phase=init status=FAIL"
        runBlocking {
            try {
                val deadline = System.currentTimeMillis() + 180_000
                while (System.currentTimeMillis() < deadline && !GlobalState.ready) {
                    GlobalState.initError?.let { error("SDK init failed: $it") }
                    Thread.sleep(500)
                }
                val load = withTimeout(180_000) { RunAnywhere.loadModel(RAModelLoadRequest(model_id = modelId, validate_availability = true)) }
                if (!load.success) { line = "NPU_E2E id=$modelId phase=load status=FAIL detail=\"${load.error_message}\""; return@runBlocking }
                if (mode == "llm") {
                    val opts = RALLMGenerationOptions(max_tokens = maxNew, temperature = 0f, top_p = 1f)
                    val sb = StringBuilder(); var inTok = 0; var outTok = 0
                    withTimeout(180_000) {
                        RunAnywhere.generateStream(text, opts).collect { ev ->
                            ev.token?.let { if (it.isNotEmpty()) sb.append(it) }
                            if (ev.is_final) ev.result?.let { inTok = it.prompt_tokens; outTok = it.completion_tokens }
                        }
                    }
                    val out = sb.toString().trim().replace("\n", " ")
                    line = "NPU_E2E id=$modelId phase=done status=PASS framework=${load.framework.name} " +
                        "promptTokens=$inTok outTokens=$outTok text=\"${out.take(240)}\""
                    Log.i(tag, line); assertTrue(line, line.contains("status=PASS")); return@runBlocking
                }
                if (mode == "vlm") {
                    // Read test.jpg (two cats) from the TEST apk assets; sys != "" exercises the system-prompt
                    // vstart shift the splice/deepstack fix addresses.
                    val testCtx = InstrumentationRegistry.getInstrumentation().context
                    val bytes = testCtx.assets.open(args.getString("img") ?: "test.jpg").use { it.readBytes() }
                    val f = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "vlm_test.jpg")
                        .apply { writeBytes(bytes) }
                    val sys = args.getString("sys")?.takeIf { it.isNotBlank() }
                    val r = withTimeout(180_000) {
                        RunAnywhere.processImage(
                            RAVLMImage.fromFilePath(f.absolutePath),
                            RAVLMGenerationOptions(prompt = text, system_prompt = sys, max_tokens = maxNew, temperature = 0f, top_p = 0f, top_k = 0),
                        )
                    }
                    val out = r.text.trim().replace("\n", " ")
                    line = "NPU_E2E id=$modelId phase=done status=PASS framework=${load.framework.name} " +
                        "sys=${if (sys != null) "Y" else "N"} imgTok=${r.image_tokens} outTok=${r.completion_tokens} text=\"${out.take(240)}\""
                    Log.i(tag, line); assertTrue(line, line.contains("status=PASS")); return@runBlocking
                }
                val r = withTimeout(60_000) { RunAnywhere.synthesize(text) }
                val raw = r.audio_data.toByteArray()
                val floats = if (r.audio_format.name.contains("S16") || r.audio_format.name.contains("PCM16")) {
                    val n = raw.size / 2
                    FloatArray(n) { i -> (((raw[2 * i + 1].toInt() shl 8) or (raw[2 * i].toInt() and 0xFF)).toShort()) / 32768.0f }
                } else {
                    val n = raw.size / 4
                    FloatArray(n) { i -> java.nio.ByteBuffer.wrap(raw, i * 4, 4).order(java.nio.ByteOrder.LITTLE_ENDIAN).float }
                }
                var ss = 0.0; for (v in floats) ss += v * v
                val rms = if (floats.isNotEmpty()) Math.sqrt(ss / floats.size) else 0.0
                line = "NPU_E2E id=$modelId phase=done status=PASS framework=${load.framework.name} " +
                    "samples=${floats.size} rate=${r.sample_rate} rms=$rms"
            } catch (e: Exception) {
                line = "NPU_E2E id=$modelId phase=exception status=FAIL detail=\"${e.javaClass.simpleName}: ${e.message}\""
            }
        }
        Log.i(tag, line)
        assertTrue(line, line.contains("status=PASS"))
    }
}
