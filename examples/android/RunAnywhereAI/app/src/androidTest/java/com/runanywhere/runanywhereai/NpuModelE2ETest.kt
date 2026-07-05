package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelSource
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.npu.NPU_MODELS
import com.runanywhere.runanywhereai.ui.screens.npu.NpuFile
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModel
import com.runanywhere.runanywhereai.ui.screens.npu.category
import com.runanywhere.sdk.npu.qhexrt.QHexRT
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
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * On-device end-to-end **benchmark + parity gate** for one NPU (QHexRT) model,
 * selected per invocation. Drives the real SDK exactly like the app
 * (register -> download -> load -> inference -> delete), but unlike a smoke test it:
 *  1. captures the FULL benchmark set per model/modality/run, computing in-test
 *     anything the SDK does not surface (load ms, peak RSS/PSS, RTF, tok/s);
 *  2. compares the output to a baseline with the same rubric forge holds every model
 *     to (ASR WER<=0.05, LLM answer+coherence, TTS exact sample-rate + non-silence,
 *     VLM keyword) — see [NpuBench.kt];
 *  3. asserts the NPU actually served it (loaded framework == QHEXRT, arch match).
 *
 * A rich JSON report lands in the app external-files dir (adb-pullable) plus a compact
 * `NPU_E2E ...` logcat line the runner greps. The model is deleted in `finally`
 * (one bundle on device at a time). NOT product code — androidTest only.
 *
 * Selection (instrumentation args, `-e key value`):
 *   -e modelId <catalog-id>                          a row from NpuCatalog.NPU_MODELS
 *   OR -e hfRepo <org/repo> -e arch <v81> -e modality <llm|vlm|stt|tts> -e files "m.json,a.bin,..."
 *   -e hfToken <hf_...>   download private runanywhere/<name>_HNPU repos (never committed/logged)
 *   -e maxNew <n>         override VLM max new tokens (default 48)
 *
 * Run via scripts/run_npu_e2e.sh (loops the catalog, one model at a time, aggregates).
 */
@RunWith(AndroidJUnit4::class)
class NpuModelE2ETest {

    private val tag = "NPU_E2E"

    private companion object {
        const val LOAD_TIMEOUT_MS = 300_000L
        const val INFER_TIMEOUT_MS = 300_000L   // per inference case
        // Longer passage to probe coherence at depth (a lightweight context check; the
        // full length-sweep to 70% MAXCTX lives in forge/tools/device_sweep.py).
        const val LONG_PROMPT =
            "The history of computing is a story of steady miniaturization. Early machines " +
                "filled entire rooms and consumed enormous power, yet performed only a handful of " +
                "operations each second. Over the decades engineers placed more and more transistors " +
                "onto a single chip, and mobile devices became capable of running large neural " +
                "networks entirely on the phone. In two or three sentences, summarize why on-device " +
                "inference matters for privacy and latency."
    }

    // ---- baselines (public, HF-derived; offline provenance documented in the skill) ----
    private data class LlmCase(val prompt: String, val expect: List<String>, val maxNew: Int = 40)
    private val llmCases = listOf(
        LlmCase("The capital of France is", listOf("paris")),
        LlmCase("Question: What is 2 plus 2? Answer with just the number.\nAnswer:", listOf("4", "four")),
        LlmCase("The opposite of hot is", listOf("cold")),
        LlmCase(LONG_PROMPT, emptyList(), maxNew = 64),   // empty expect -> coherence-only
    )

    private data class AsrCase(val asset: String, val ref: String)
    private val asrCases = listOf(
        AsrCase("ls16k_libri.pcm", "Mr. Quilter is the apostle of the middle classes, and we are glad to welcome his gospel."),
        AsrCase("speech_16k_mono.pcm", "The quick brown fox jumps over the lazy dog."),
    )

    private val ttsTexts = listOf(
        "This is a test of on device speech synthesis.",
        "Hello! One, two, three, testing punctuation.",
        "The Hexagon neural processing unit runs this model.",
    )

    private data class VlmCase(val asset: String, val prompt: String, val expect: List<String>)
    private val vlmCases = listOf(
        VlmCase("test.jpg", "Describe this image.", listOf("cat", "cats", "kitten")),
    )

    @Test
    fun runOne() {
        val args = InstrumentationRegistry.getArguments()
        val model = resolveModel(args) ?: run {
            Log.i(tag, "NPU_E2E status=FAIL phase=lookup detail=\"no -e modelId / -e hfRepo\"")
            assertTrue("missing -e modelId <id> or -e hfRepo <repo> -e modality <m> -e files <csv>", false)
            return
        }
        val maxNew = args.getString("maxNew")?.toIntOrNull() ?: 48
        val hfToken = args.getString("hfToken")?.takeIf { it.isNotBlank() }
        val outDir = InstrumentationRegistry.getInstrumentation().targetContext
            .getExternalFilesDir(null)?.let { File(it, "npu_e2e") }

        val report = RunReport(model.id, hfRepoOf(model), model.modality.name.lowercase(), model.arch)
        report.put("device_model", "${Build.MANUFACTURER} ${Build.MODEL}")

        var phase = "init"
        var line = ""
        var passed = false
        runBlocking {
            try {
                awaitSdkReady(180_000)

                // ---- NPU capability + arch match (a v79 bundle will not load on v81) ----
                phase = "probe"
                val npu = QHexRT.probeNpu()
                report.put("soc_model", npu.soc_model).put("soc_id", npu.soc_id)
                    .put("probe_arch", npu.arch_name).put("npu_supported", npu.qhexrt_supported)
                report.gate("npu_supported", npu.qhexrt_supported)
                report.gate("arch_match", npu.arch_name.equals(model.arch, ignoreCase = true))
                if (!npu.qhexrt_supported) throw AssertionError("device NPU not supported (arch=${npu.arch_name})")
                if (!npu.arch_name.equals(model.arch, ignoreCase = true)) {
                    throw AssertionError("arch mismatch: bundle=${model.arch} device=${npu.arch_name} (context binaries are arch-pinned)")
                }

                if (hfToken != null) RunAnywhere.setHfToken(hfToken)   // private repos; never logged/committed

                phase = "register"
                val registered = register(model)

                // ---- download (unbounded on time; size drives it) + real transfer metrics ----
                phase = "download"
                val dlStart = System.currentTimeMillis()
                var lastLog = 0
                var seen = 0L
                var bps = 0f
                val dl = RunAnywhere.downloadModel(registered) { p ->
                    seen = maxOf(seen, p.bytes_downloaded)
                    if (p.overall_speed_bps > 0f) bps = p.overall_speed_bps
                    val pct = ((if (p.overall_progress > 0f) p.overall_progress else p.stage_progress) * 100).toInt()
                    if (pct >= lastLog + 20) { lastLog = pct; Log.i(tag, "${model.id} download $pct%") }
                }
                val dlMs = System.currentTimeMillis() - dlStart
                val totBytes = maxOf(dl.total_bytes, dl.bytes_downloaded, seen)
                report.put("download_s", dlMs / 1000).put("download_ms", dlMs)
                    .put("download_mb", round2(totBytes / 1e6))
                    .put("download_mbps", round2((if (dl.overall_speed_bps > 0f) dl.overall_speed_bps else bps) / 1e6))

                // ---- load (SDK returns a timestamp, not a duration -> we time it) ----
                phase = "load"
                val loadStart = System.currentTimeMillis()
                val load = withTimeout(LOAD_TIMEOUT_MS) { RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id)) }
                report.put("load_ms", System.currentTimeMillis() - loadStart)
                if (!load.success) throw AssertionError(load.error_message.ifBlank { "load success=false" })
                report.put("framework", load.framework.name)
                    .gate("framework_qhexrt", load.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT)

                // ---- inference suite (multiple inputs) + full benchmark + parity ----
                // Prefer the canonical npu_suite/v1 (the SAME cases + gold forge/goal_npu uses, synced into
                // assets/npu_suites/<id>.json); fall back to the built-in heuristic cases when none is shipped.
                phase = "infer"
                val suite = NpuSuite.load(InstrumentationRegistry.getInstrumentation().context.assets, model.id)
                report.put("suite", if (suite != null) "npu_suite/v1:${suite.metric}:${suite.cases.size}cases" else "heuristic")
                when (model.modality) {
                    NpuModality.LLM -> runLlm(report, suite)
                    NpuModality.VLM -> runVlm(report, maxNew, suite)
                    NpuModality.STT -> runStt(report, suite)
                    NpuModality.TTS -> runTts(report, model, outDir, suite)
                }

                report.put("peak_rss_mb", round2(NpuMetrics.peakRssKb() / 1024.0))
                    .put("peak_pss_mb", round2(NpuMetrics.totalPssKb() / 1024.0))

                phase = "done"
                passed = report.allGatesPass()
                line = report.finish(if (passed) "PASS" else "FAIL", phase,
                    if (passed) "ok" else "gate(s) failed", outDir)
            } catch (e: TimeoutCancellationException) {
                line = report.finish("FAIL", phase, "timeout in $phase", outDir)
            } catch (e: AssertionError) {
                line = report.finish("FAIL", phase, e.message ?: "assertion", outDir)
            } catch (e: Exception) {
                line = report.finish("FAIL", phase, "${e.javaClass.simpleName}: ${e.message}", outDir)
            } finally {
                if (args.getString("keepModel") != "true") runCatching { RunAnywhere.deleteModel(model.id) }   // keep only one bundle on device
            }
        }
        Log.i(tag, line)
        assertTrue("NPU_E2E FAIL — see the NPU_E2E line / report json ($line)", line.contains("status=PASS"))
    }

    // ---------------------------------------------------------------- LLM ----
    private suspend fun runLlm(report: RunReport, suite: NpuSuite?) {
        val goldCases = suite?.cases?.filter { it.text != null && it.goldTokens != null }.orEmpty()
        if (goldCases.isNotEmpty()) {
            // Canonical-suite path over the SAME prompts forge/goal_npu uses. The app runs the model
            // CHAT-templated (no no_template option), so the GATE is answer-correctness (suite expect_keywords)
            // + coherence — a chat-formatted-but-correct answer must not fail for not being a base completion.
            // The token-level greedy_tol drift vs forge's BASE gold_tokens is REPORTED alongside (it runs high
            // precisely because the app is chat, not base); forge's own base-completion path gates on it.
            report.put("parity_metric", "answer+coherence(+greedy_tol_base)")
            var decSum = 0.0; var ttftSum = 0.0; var n = 0; var passN = 0
            for ((i, c) in goldCases.withIndex()) {
                val gold = c.goldTokens!!
                val g = withTimeout(INFER_TIMEOUT_MS) { greedyGenerate(c.text!!, maxOf(gold.size + 24, 32)) }
                val drift = NpuMetrics.normalizedTokenEdit(g.tokenIds, gold)     // vs base gold (informational)
                val coherent = g.text.isNotBlank() && NpuMetrics.wordRepeatRatio(g.text) < NpuRubric.REPEAT_MAX
                val pass = coherent && (c.keywords.isEmpty() || c.keywords.any { g.text.contains(it, ignoreCase = true) })
                if (pass) passN++
                if (g.outTok > 0) { decSum += g.decodeToks; ttftSum += g.ttftMs; n++ }
                report.addSample(JSONObject().put("idx", i).put("id", c.id).put("input", c.text!!.take(60))
                    .put("output", g.text.take(200)).put("expect", c.keywords.joinToString(","))
                    .put("metric", "answer+coherence").put("greedy_tol_base", round3(drift))
                    .put("gold_ntok", gold.size).put("dev_ntok", g.tokenIds.size)
                    .put("ttft_ms", round2(g.ttftMs)).put("decode_toks", round2(g.decodeToks))
                    .put("prefill_toks", round2(g.prefillToks)).put("tokens_per_s", round2(g.tokensPerS))
                    .put("total_ms", round2(g.totalMs)).put("out_tok", g.outTok).put("pass", pass))
            }
            val frac = passN.toDouble() / goldCases.size
            report.put("suite_pass_frac", round2(frac))
            report.gate("llm_answer_suite", frac >= suite!!.passFrac - 1e-9)
            if (n > 0) report.put("decode_toks", round2(decSum / n)).put("ttft_ms", round2(ttftSum / n))
            return
        }
        // fallback: built-in answer+coherence heuristic (no gold suite shipped for this model)
        report.put("parity_metric", "answer+coherence")
        var decSum = 0.0; var ttftSum = 0.0; var n = 0
        for ((i, c) in llmCases.withIndex()) {
            val r = withTimeout(INFER_TIMEOUT_MS) {
                RunAnywhere.aggregateStream(c.prompt, RunAnywhere.generateStream(c.prompt,
                    RALLMGenerationOptions(max_tokens = c.maxNew, temperature = 0f)))
            }
            val text = r.text.trim()
            val decTok = if (r.decode_time_ms > 0) r.tokens_generated * 1000.0 / r.decode_time_ms else r.tokens_per_second
            val coherent = text.isNotBlank() && NpuMetrics.wordRepeatRatio(text) < NpuRubric.REPEAT_MAX
            val pass = if (c.expect.isEmpty()) coherent else coherent && c.expect.any { text.contains(it, ignoreCase = true) }
            report.addSample(JSONObject().put("idx", i).put("input", c.prompt.take(60)).put("output", text.take(200))
                .put("ttft_ms", round2(r.ttft_ms ?: 0.0)).put("decode_toks", round2(decTok))
                .put("tokens_per_s", round2(r.tokens_per_second)).put("out_tok", r.tokens_generated)
                .put("metric", if (c.expect.isEmpty()) "coherence" else "answer+coherence").put("pass", pass))
            report.gate("llm_case_$i", pass)
            if (r.framework != null) report.gate("framework_result", r.framework == "qhexrt")
            if (r.tokens_generated > 0) { decSum += decTok; ttftSum += (r.ttft_ms ?: 0.0); n++ }
        }
        if (n > 0) report.put("decode_toks", round2(decSum / n)).put("ttft_ms", round2(ttftSum / n))
    }

    private data class Gen(val text: String, val tokenIds: List<Int>, val ttftMs: Double, val decodeToks: Double,
                           val prefillToks: Double, val tokensPerS: Double, val totalMs: Double, val outTok: Int)

    /** Greedy (temp=0) generation collecting per-token ids (for token-level parity) + perf metrics. */
    private suspend fun greedyGenerate(prompt: String, maxNew: Int): Gen {
        val opts = RALLMGenerationOptions(max_tokens = maxNew, temperature = 0f)
        val ids = ArrayList<Int>(); val sb = StringBuilder()
        val t0 = System.currentTimeMillis(); var ttftWall = 0.0
        var ttft = 0.0; var tps = 0.0; var decMs = 0.0; var preMs = 0.0; var totMs = 0.0; var outTok = 0; var inTok = 0
        RunAnywhere.generateStream(prompt, opts).collect { ev ->
            val tk = ev.token
            if (!tk.isNullOrEmpty()) {
                if (ttftWall == 0.0) ttftWall = (System.currentTimeMillis() - t0).toDouble()
                sb.append(tk); ids.add(ev.token_id)
            }
            if (ev.is_final) ev.result?.let { r ->
                ttft = r.time_to_first_token_ms.toDouble(); tps = r.tokens_per_second.toDouble()
                decMs = r.decode_time_ms.toDouble(); preMs = r.prompt_eval_time_ms.toDouble()
                totMs = r.total_time_ms.toDouble(); outTok = r.completion_tokens; inTok = r.prompt_tokens
            }
        }
        val totalWall = (System.currentTimeMillis() - t0).toDouble()
        if (outTok == 0) outTok = ids.size
        val ttftF = if (ttft > 0) ttft else ttftWall
        val total = if (totMs > 0) totMs else totalWall
        val decToks = if (decMs > 0) outTok * 1000.0 / decMs else if (tps > 0) tps else if (total > 0) outTok * 1000.0 / total else 0.0
        val preToks = if (preMs > 0) inTok * 1000.0 / preMs else 0.0
        return Gen(sb.toString().trim(), ids, ttftF, decToks, preToks, if (tps > 0) tps else decToks, total, outTok)
    }

    // ---------------------------------------------------------------- VLM ----
    private suspend fun runVlm(report: RunReport, maxNew: Int, suite: NpuSuite?) {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val imgCases = suite?.cases
            ?.mapNotNull { c -> c.imageAsset?.let { Triple(it, c.text ?: "Describe this image.", c.keywords) } }
            ?.takeIf { it.isNotEmpty() } ?: vlmCases.map { Triple(it.asset, it.prompt, it.expect) }
        for ((i, cc) in imgCases.withIndex()) {
            val (asset, prompt, kws) = cc
            val f = File(ctx.cacheDir, "vlm_$i.jpg").apply { writeBytes(testAsset(asset)) }
            val r = withTimeout(INFER_TIMEOUT_MS) {
                // Greedy (temperature=0, no top-p/top-k) — the parity setting: the device caption must
                // match the fp32 gold deterministically, not a sampled variant. (0f is also the option
                // default, but pin it explicitly so a future default change can't silently un-greedy the gate.)
                RunAnywhere.processImage(RAVLMImage.fromFilePath(f.absolutePath),
                    RAVLMGenerationOptions(prompt = prompt, max_tokens = maxNew, temperature = 0f, top_p = 0f, top_k = 0))
            }
            val text = r.text.trim()
            val pass = text.isNotBlank() && kws.any { text.contains(it, ignoreCase = true) }
            report.addSample(JSONObject().put("idx", i).put("input", prompt)
                .put("output", text.take(200)).put("vision_ms", round2(r.image_encode_time_ms.toDouble()))
                .put("ttft_ms", round2(r.time_to_first_token_ms.toDouble()))
                .put("tokens_per_s", round2(r.tokens_per_second.toDouble()))
                .put("total_ms", round2(r.processing_time_ms.toDouble()))
                .put("out_tok", r.completion_tokens).put("img_tok", r.image_tokens)
                .put("metric", "keyword:${kws.firstOrNull() ?: ""}").put("pass", pass))
            report.gate("vlm_case_$i", pass)
            report.put("vision_ms", round2(r.image_encode_time_ms.toDouble()))
                .put("ttft_ms", round2(r.time_to_first_token_ms.toDouble()))
                .put("tokens_per_s", round2(r.tokens_per_second.toDouble()))
        }
    }

    // ---------------------------------------------------------------- STT ----
    private suspend fun runStt(report: RunReport, suite: NpuSuite?) {
        val cases = suite?.cases?.mapNotNull { c -> c.wavAsset?.let { it to c.goldText } }?.takeIf { it.isNotEmpty() }
            ?: asrCases.map { it.asset to it.ref }
        val werMax = suite?.werMax ?: NpuRubric.WER_MAX
        var rtfSum = 0.0; var worstWer = 0.0; var n = 0
        for ((i, cc) in cases.withIndex()) {
            val (asset, ref) = cc
            val pcm = testAsset(asset)
            val audioS = pcm.size / 2.0 / 16000.0
            val start = System.currentTimeMillis()
            val r = withTimeout(INFER_TIMEOUT_MS) { RunAnywhere.transcribe(pcm) }
            val wallMs = (System.currentTimeMillis() - start).toDouble()
            val procMs = r.metadata?.processing_time_ms?.takeIf { it > 0 }?.toDouble() ?: wallMs
            val rtf = r.metadata?.real_time_factor?.takeIf { it > 0f }?.toDouble() ?: (procMs / 1000.0 / audioS)
            val text = r.text.trim()
            val wer = NpuMetrics.wer(ref, text)
            val pass = wer <= werMax
            report.addSample(JSONObject().put("idx", i).put("input", asset)
                .put("output", text.take(200)).put("reference", ref)
                .put("audio_s", round2(audioS)).put("latency_ms", round2(procMs)).put("rtf", round2(rtf))
                .put("confidence", round2(r.confidence.toDouble()))
                .put("metric", "wer").put("score", round3(wer)).put("pass", pass))
            report.gate("asr_case_$i", pass)
            rtfSum += rtf; worstWer = maxOf(worstWer, wer); n++
        }
        if (n > 0) report.put("rtf", round2(rtfSum / n)).put("wer", round3(worstWer))
    }

    // ---------------------------------------------------------------- TTS ----
    private suspend fun runTts(report: RunReport, model: NpuModel, outDir: File?, suite: NpuSuite?) {
        val texts = suite?.cases?.mapNotNull { it.text }?.takeIf { it.isNotEmpty() } ?: ttsTexts
        val expectedRate = suite?.cases?.firstOrNull { it.expectedRate > 0 }?.expectedRate
            ?: NpuRubric.expectedTtsRate(model.id)
        var rtfSum = 0.0; var n = 0
        for ((i, text) in texts.withIndex()) {
            val start = System.currentTimeMillis()
            val r = withTimeout(INFER_TIMEOUT_MS) { RunAnywhere.synthesize(text) }
            val wallMs = (System.currentTimeMillis() - start).toDouble()
            val raw = r.audio_data.toByteArray()
            val floats = if (r.audio_format.name.contains("S16") || r.audio_format.name.contains("PCM16"))
                NpuMetrics.pcm16leToFloat(raw) else NpuMetrics.float32leToFloat(raw)
            val durS = if (r.duration_ms > 0) r.duration_ms / 1000.0 else floats.size.toDouble() / maxOf(1, r.sample_rate)
            val rms = NpuMetrics.rms(floats)
            val procMs = r.metadata?.processing_time_ms?.takeIf { it > 0 }?.toDouble() ?: wallMs
            val rtf = if (durS > 0) procMs / 1000.0 / durS else 0.0
            val rateOk = if (expectedRate != null) r.sample_rate == expectedRate else r.sample_rate in NpuRubric.TTS_RATES
            val pass = rateOk && durS >= NpuRubric.TTS_MIN_SECONDS && rms >= NpuRubric.TTS_RMS_MIN && floats.isNotEmpty()
            // persist a wav so the runner round-trips it through offline whisper (intelligibility WER)
            outDir?.let { writeWav(File(it.apply { mkdirs() }, "tts_${model.id}_$i.wav"), floats, r.sample_rate) }
            report.addSample(JSONObject().put("idx", i).put("input", text)
                .put("output", "audio:${floats.size}samples@${r.sample_rate}Hz")
                .put("sample_rate", r.sample_rate).put("expected_rate", expectedRate ?: 0)
                .put("audio_s", round2(durS)).put("latency_ms", round2(procMs)).put("rtf", round2(rtf))
                .put("rms", round3(rms)).put("format", r.audio_format.name)
                .put("metric", "sample_rate+rms").put("pass", pass))
            report.gate("tts_case_$i", pass)
            rtfSum += rtf; n++
            if (i == 0) report.put("sample_rate", r.sample_rate)
        }
        if (n > 0) report.put("rtf", round2(rtfSum / n))
    }

    // ---------------------------------------------------------------- helpers ----
    private suspend fun register(model: NpuModel) =
        if (model.files.isNotEmpty()) {
            RunAnywhere.registerModel(
                multiFile = model.files.mapIndexed { idx, f ->
                    ModelFileDescriptor(
                        url = f.url, filename = f.filename, is_required = true,
                        role = if (idx == 0) ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                        else ModelFileRole.MODEL_FILE_ROLE_COMPANION,
                    )
                },
                id = model.id, name = model.name,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = model.modality.category(), source = ModelSource.MODEL_SOURCE_REMOTE,
            )
        } else {
            RunAnywhere.registerModel(
                archiveUrl = model.resolvedArchiveUrl, structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
                id = model.id, name = model.name,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = model.modality.category(), archiveType = ArchiveType.ARCHIVE_TYPE_ZIP,
            )
        }

    /** Catalog id, or an ad-hoc model synthesized from -e hfRepo/arch/modality/files. */
    private fun resolveModel(args: Bundle): NpuModel? {
        args.getString("modelId")?.let { id -> return NPU_MODELS.firstOrNull { it.id == id } }
        val repo = args.getString("hfRepo") ?: return null
        val arch = args.getString("arch") ?: "v81"
        val modality = when (args.getString("modality")?.lowercase()) {
            "llm" -> NpuModality.LLM
            "vlm" -> NpuModality.VLM
            "stt", "asr" -> NpuModality.STT
            "tts" -> NpuModality.TTS
            else -> return null
        }
        val names = (args.getString("files") ?: return null).split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (names.isEmpty()) return null
        val base = "https://huggingface.co/$repo/resolve/main"
        // The manifest + context bins + tokenizer are the runnable bundle; the HF repo-root config.json is
        // metadata the qhexrt runtime does not read. Many private repos (the NVIDIA/NeMo batch) ship NO root
        // config.json, and appending it unconditionally made the whole ad-hoc download 404. So append it only
        // when the caller explicitly opts in (`-e addConfig true`), off by default.
        val addConfig = args.getString("addConfig")?.equals("true", ignoreCase = true) == true
        val files = names.map { NpuFile(it, "$base/$arch/$it") } +
            (if (addConfig) listOf(NpuFile("config.json", "$base/config.json")) else emptyList())
        return NpuModel(
            id = "${repo.substringAfterLast('/')}_$arch", name = repo, detail = "$modality - $arch",
            modality = modality, arch = arch, files = files,
        )
    }

    private fun hfRepoOf(model: NpuModel): String =
        model.files.firstOrNull()?.url?.substringAfter("huggingface.co/")?.substringBefore("/resolve") ?: model.name

    private fun testAsset(name: String): ByteArray =
        InstrumentationRegistry.getInstrumentation().context.assets.open(name).use { it.readBytes() }

    /** Minimal 16-bit PCM WAV writer so the runner can transcribe the TTS output offline. */
    private fun writeWav(file: File, samples: FloatArray, sampleRate: Int) {
        val pcm = ByteArrayOutputStream()
        for (v in samples) {
            val s = (v.coerceIn(-1f, 1f) * 32767f).toInt()
            pcm.write(s and 0xFF); pcm.write((s shr 8) and 0xFF)
        }
        val body = pcm.toByteArray()
        val out = ByteArrayOutputStream()
        fun le32(v: Int) { out.write(v and 0xFF); out.write((v shr 8) and 0xFF); out.write((v shr 16) and 0xFF); out.write((v ushr 24) and 0xFF) }
        fun le16(v: Int) { out.write(v and 0xFF); out.write((v shr 8) and 0xFF) }
        out.write("RIFF".toByteArray()); le32(36 + body.size); out.write("WAVE".toByteArray())
        out.write("fmt ".toByteArray()); le32(16); le16(1); le16(1); le32(sampleRate)
        le32(sampleRate * 2); le16(2); le16(16)
        out.write("data".toByteArray()); le32(body.size); out.write(body)
        runCatching { file.writeBytes(out.toByteArray()) }
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

    private fun round2(v: Double) = Math.round(v * 100) / 100.0
    private fun round3(v: Double) = Math.round(v * 1000) / 1000.0
}
