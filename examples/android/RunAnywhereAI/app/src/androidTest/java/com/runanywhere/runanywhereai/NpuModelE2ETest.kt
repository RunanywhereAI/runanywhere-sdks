package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ThinkingTagPattern
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.data.SingleFileModel
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.aggregateStream
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.embeddings
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
import org.json.JSONArray
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
     *   -e modelId <catalog-id>                          a row from ModelCatalog.npuCatalog
 *   OR -e hfRepo <org/repo> -e arch <v81> -e modality <llm|vlm|stt|tts> -e manifest <m.json>
 *      (legacy: -e files "m.json,..." — only the first name, the manifest, is used)
 *   -e hfToken <hf_...>   download private runanywhere/<name>_HNPU repos (never committed/logged)
 *   -e maxNew <n>         override LLM/VLM max new tokens (default 48)
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
        val THINKING_TAGS = ThinkingTagPattern(open_tag = "<think>", close_tag = "</think>")
        val ARCH_SUFFIX = Regex("(.+)_(v(?:75|79|81|83))$")
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

    private data class VlmCase(val asset: String, val prompt: String, val expect: List<String>, val maxNew: Int = 48)
    private val vlmCases = listOf(
        VlmCase("test.jpg", "Describe this image.", listOf("cat", "cats", "kitten")),
    )

    @Test
    fun runOne() {
        val args = InstrumentationRegistry.getArguments()
        val selection = resolveModel(args) ?: run {
            val requestedModelId = args.getString("modelId")?.takeIf { it.isNotBlank() }
            val message = requestedModelId?.let {
                "unknown -e modelId '$it' (expected a ModelCatalog.npuCatalog id, optionally suffixed with _v75/_v79/_v81/_v83)"
            } ?: "missing -e modelId <id> or -e hfRepo <repo> -e modality <m> -e manifest <m.json>"
            Log.i(tag, "NPU_E2E status=FAIL phase=lookup detail=\"$message\"")
            assertTrue(message, false)
            return
        }
        val (model, requestedArch) = selection
        val maxNew = args.getString("maxNew")?.toIntOrNull() ?: 48
        val hfToken = args.getString("hfToken")?.takeIf { it.isNotBlank() }
        val outDir = InstrumentationRegistry.getInstrumentation().targetContext
            .getExternalFilesDir(null)?.let { File(it, "npu_e2e") }

        val report = RunReport(model.id, hfRepoOf(model), modalityName(model.category), requestedArch ?: "native-auto")
        report.put("device_model", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("request", JSONObject()
                .put("selection", if (args.getString("modelId").isNullOrBlank()) "ad_hoc" else "catalog")
                .put("model_id", args.getString("modelId") ?: JSONObject.NULL)
                .put("hf_repo", args.getString("hfRepo") ?: JSONObject.NULL)
                .put("manifest", args.getString("manifest") ?: args.getString("files") ?: JSONObject.NULL)
                .put("arch", requestedArch ?: "native-auto")
                .put("max_new", maxNew))
            .put("sdk_source", JSONObject()
                .put("git_revision", args.getString("sdkGitRevision") ?: JSONObject.NULL)
                .put("git_dirty", args.getString("sdkGitDirty")?.toBooleanStrictOrNull() ?: JSONObject.NULL)
                .put("app_version", BuildConfig.VERSION_NAME)
                .put("app_version_code", BuildConfig.VERSION_CODE))

        var phase = "init"
        var line = ""
        var finalStatus = "FAIL"
        var finalPhase = phase
        var finalDetail = "run did not complete"
        runBlocking {
            try {
                awaitSdkReady(180_000)

                // ---- NPU capability + arch match (a v79 bundle will not load on v81) ----
                phase = "probe"
                val npu = QHexRT.probeNpu()
                report.put("soc_model", npu.soc_model).put("soc_id", npu.soc_id)
                    .put("probe_arch", npu.arch_name).put("npu_supported", npu.qhexrt_supported)
                    .put("arch", npu.arch_name)
                report.gate("npu_supported", npu.qhexrt_supported)
                val expectedArch = requestedArch ?: npu.arch_name
                report.put("expected_arch", expectedArch)
                report.gate("arch_match", npu.arch_name.equals(expectedArch, ignoreCase = true))
                if (!npu.qhexrt_supported) throw AssertionError("device NPU not supported (arch=${npu.arch_name})")
                if (!npu.arch_name.equals(expectedArch, ignoreCase = true)) {
                    throw AssertionError("arch mismatch: requested=$expectedArch device=${npu.arch_name} (context binaries are arch-pinned)")
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
                val suite = loadSuite(model.id, expectedArch)
                report.put("suite", if (suite != null) "npu_suite/v1:${suite.metric}:${suite.cases.size}cases" else "heuristic")
                    .put("suite_id", suite?.suiteId)
                    .put("suite_sha256", suite?.sha256)
                    .gate("canonical_suite", suite != null)
                when (model.category) {
                    ModelCategory.MODEL_CATEGORY_LANGUAGE -> runLlm(report, suite, maxNew)
                    ModelCategory.MODEL_CATEGORY_MULTIMODAL -> runVlm(report, maxNew, suite)
                    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> runStt(report, suite)
                    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> runTts(report, model, outDir, suite)
                    ModelCategory.MODEL_CATEGORY_EMBEDDING -> runEmbedding(report, model)
                    else -> throw AssertionError("unsupported NPU modality: ${model.category}")
                }

                report.put("peak_rss_mb", round2(NpuMetrics.peakRssKb() / 1024.0))
                    .put("peak_pss_mb", round2(NpuMetrics.totalPssKb() / 1024.0))

                phase = "done"
                finalStatus = if (report.allGatesPass()) "PASS" else "FAIL"
                finalPhase = phase
                finalDetail = if (finalStatus == "PASS") "ok" else "gate(s) failed"
            } catch (e: TimeoutCancellationException) {
                finalPhase = phase
                finalDetail = "timeout in $phase"
            } catch (e: AssertionError) {
                finalPhase = phase
                finalDetail = e.message ?: "assertion"
            } catch (e: Exception) {
                finalPhase = phase
                finalDetail = "${e.javaClass.simpleName}: ${e.message}"
            } finally {
                val keepModel = args.getString("keepModel") == "true"
                if (keepModel) {
                    report.put("delete", JSONObject()
                        .put("requested", false)
                        .put("success", false)
                        .put("reason", "keepModel=true"))
                        .gate("delete_model", false)
                    finalStatus = "FAIL"
                    finalPhase = "delete"
                    finalDetail = appendDetail(finalDetail, "model deletion skipped because keepModel=true")
                } else {
                    val deleteStart = System.currentTimeMillis()
                    try {
                        val result = RunAnywhere.deleteModel(model.id)
                        val modelIdDeleted = model.id in result.deleted_model_ids
                        val deleteOk = result.success && modelIdDeleted && result.failed_model_ids.isEmpty() &&
                            result.skipped_model_ids.isEmpty() && result.files_deleted &&
                            result.registry_updated && !result.dry_run
                        report.put("delete", JSONObject()
                            .put("requested", true)
                            .put("success", result.success)
                            .put("duration_ms", System.currentTimeMillis() - deleteStart)
                            .put("deleted_bytes", result.deleted_bytes)
                            .put("deleted_model_ids", JSONArray(result.deleted_model_ids))
                            .put("failed_model_ids", JSONArray(result.failed_model_ids))
                            .put("skipped_model_ids", JSONArray(result.skipped_model_ids))
                            .put("warnings", JSONArray(result.warnings))
                            .put("files_deleted", result.files_deleted)
                            .put("registry_updated", result.registry_updated)
                            .put("dry_run", result.dry_run)
                            .put("error_message", result.error_message))
                            .gate("delete_model", deleteOk)
                        if (!deleteOk) {
                            finalStatus = "FAIL"
                            finalPhase = "delete"
                            val reason = result.error_message.ifBlank {
                                "delete result did not confirm files + registry cleanup for ${model.id}"
                            }
                            finalDetail = appendDetail(finalDetail, reason)
                        }
                    } catch (e: Exception) {
                        report.put("delete", JSONObject()
                            .put("requested", true)
                            .put("success", false)
                            .put("duration_ms", System.currentTimeMillis() - deleteStart)
                            .put("error_message", "${e.javaClass.simpleName}: ${e.message}"))
                            .gate("delete_model", false)
                        finalStatus = "FAIL"
                        finalPhase = "delete"
                        finalDetail = appendDetail(finalDetail, "model deletion failed: ${e.javaClass.simpleName}: ${e.message}")
                    }
                }
                if (!report.allGatesPass()) finalStatus = "FAIL"
                line = report.finish(finalStatus, finalPhase, finalDetail, outDir)
            }
        }
        Log.i(tag, line)
        assertTrue("NPU_E2E FAIL — see the NPU_E2E line / report json ($line)", line.contains("status=PASS"))
    }

    private fun appendDetail(current: String, extra: String): String =
        if (current == "ok" || current.isBlank()) extra else "$current; $extra"

    // ---------------------------------------------------------------- LLM ----
    private suspend fun runLlm(report: RunReport, suite: NpuSuite?, maxNew: Int) {
        val suiteCases = suite?.cases
            ?.filter { it.text != null && (it.goldTokens != null || it.keywords.isNotEmpty()) }
            .orEmpty()
        if (suiteCases.isNotEmpty()) {
            // Canonical-suite path over the SAME prompts forge/goal_npu uses. The app runs the model
            // CHAT-templated (no no_template option), so the GATE is answer-correctness (suite expect_keywords)
            // + coherence — a chat-formatted-but-correct answer must not fail for not being a base completion.
            // The token-level greedy_tol drift vs forge's BASE gold_tokens is REPORTED alongside (it runs high
            // precisely because the app is chat, not base); forge's own base-completion path gates on it.
            report.put("parity_metric", "answer+coherence(+greedy_tol_base)")
            var decSum = 0.0; var ttftSum = 0.0; var n = 0; var passN = 0
            for ((i, c) in suiteCases.withIndex()) {
                val gold = c.goldTokens
                val budget = maxOf(maxNew, suite!!.maxNew, c.maxNew, (gold?.size ?: 0) + 24, 32)
                val g = withTimeout(INFER_TIMEOUT_MS) { greedyGenerate(c.text!!, budget) }
                val drift = gold?.let { NpuMetrics.normalizedTokenEdit(g.tokenIds, it) } // vs base gold (informational)
                val coherent = g.text.isNotBlank() && NpuMetrics.wordRepeatRatio(g.text) < NpuRubric.REPEAT_MAX
                val pass = coherent && (c.keywords.isEmpty() || c.keywords.any { g.text.contains(it, ignoreCase = true) })
                if (pass) passN++
                if (g.outTok > 0) { decSum += g.decodeToks; ttftSum += g.ttftMs; n++ }
                val sample = JSONObject().put("idx", i).put("id", c.id).put("input", c.text!!.take(60))
                    .put("output", g.text.take(200)).put("expect", c.keywords.joinToString(","))
                    .put("metric", "answer+coherence").put("max_new", budget)
                    .put("dev_ntok", g.tokenIds.size)
                    .put("ttft_ms", round2(g.ttftMs)).put("decode_toks", round2(g.decodeToks))
                    .put("prefill_toks", round2(g.prefillToks)).put("tokens_per_s", round2(g.tokensPerS))
                    .put("total_ms", round2(g.totalMs)).put("out_tok", g.outTok).put("pass", pass)
                if (gold != null) sample.put("greedy_tol_base", round3(drift!!)).put("gold_ntok", gold.size)
                report.addSample(sample)
            }
            val frac = passN.toDouble() / suiteCases.size
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
                    RALLMGenerationOptions(
                        max_tokens = c.maxNew,
                        temperature = 0f,
                        top_p = 1f,
                        disable_thinking = true,
                    )))
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
        val opts = RALLMGenerationOptions(
            max_tokens = maxNew,
            temperature = 0f,
            top_p = 1f,
            thinking_pattern = THINKING_TAGS,
        )
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
            ?.mapNotNull { c -> c.imageAsset?.let { VlmCase(it, c.text ?: "Describe this image.", c.keywords, c.maxNew) } }
            ?.takeIf { it.isNotEmpty() } ?: vlmCases
        for ((i, cc) in imgCases.withIndex()) {
            val (asset, prompt, kws, caseMaxNew) = cc
            val suiteBudget = maxOf(suite?.maxNew ?: 0, caseMaxNew)
            val budget = if (suiteBudget > 0) suiteBudget else maxOf(maxNew, 1)
            val f = File(ctx.cacheDir, "vlm_$i.jpg").apply { writeBytes(testAsset(asset)) }
            val r = withTimeout(INFER_TIMEOUT_MS) {
                // Greedy (temperature=0, no top-p/top-k) — the parity setting: the device caption must
                // match the fp32 gold deterministically, not a sampled variant. (0f is also the option
                // default, but pin it explicitly so a future default change can't silently un-greedy the gate.)
                RunAnywhere.processImage(RAVLMImage.fromFilePath(f.absolutePath),
                    RAVLMGenerationOptions(prompt = prompt, max_tokens = budget, temperature = 0f, top_p = 0f, top_k = 0))
            }
            val text = r.text.trim()
            val pass = text.isNotBlank() && kws.any { text.contains(it, ignoreCase = true) }
            report.addSample(JSONObject().put("idx", i).put("input", prompt)
                .put("output", text.take(200)).put("vision_ms", round2(r.image_encode_time_ms.toDouble()))
                .put("ttft_ms", round2(r.time_to_first_token_ms.toDouble()))
                .put("tokens_per_s", round2(r.tokens_per_second.toDouble()))
                .put("total_ms", round2(r.processing_time_ms.toDouble()))
                .put("out_tok", r.completion_tokens).put("img_tok", r.image_tokens)
                .put("metric", "keyword:${kws.firstOrNull() ?: ""}").put("max_new", budget).put("pass", pass))
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

    // ------------------------------------------------------------- EMBEDDING ----
    // Self-consistent cosine gate (needs no external gold vector): a paraphrase pair must be MORE
    // similar than an unrelated pair, and by a clear margin. Proves the QHexRT embedding op produces
    // a meaningful sentence vector on the NPU end-to-end via RunAnywhere.embeddings.embed.
    private suspend fun runEmbedding(report: RunReport, model: SingleFileModel) {
        suspend fun vec(t: String): FloatArray {
            val start = System.currentTimeMillis()
            val r = withTimeout(INFER_TIMEOUT_MS) { RunAnywhere.embeddings.embed(t, model.id) }
            report.put("last_embed_ms", System.currentTimeMillis() - start)
            return (r.vectors.firstOrNull()?.values ?: emptyList()).toFloatArray()
        }
        // SigLIP2 / CLIP-style DUAL-TOWER embedder: zero-shot IMAGE classification through the SAME
        // embedding API. embed(<image file path>) runs the image tower (the native adapter detects a
        // readable *.jpg/*.png path), embed(<label text>) the text tower. The image (two cats) must be
        // MORE similar to its true label than to a distractor — real vision inference, not text-only.
        if (model.id.contains("siglip")) {
            val ctx = InstrumentationRegistry.getInstrumentation().targetContext
            val img = File(ctx.cacheDir, "siglip_img.jpg").apply { writeBytes(testAsset("test.jpg")) }
            val label = "a photo of two cats"; val distractor = "a photo of a red car"
            val iv = vec(img.absolutePath); val rel = vec(label); val irr = vec(distractor)
            val dimOk = iv.isNotEmpty() && rel.size == iv.size && irr.size == iv.size
            val simRel = if (dimOk) cosine(iv, rel) else 0.0
            val simIrr = if (dimOk) cosine(iv, irr) else 0.0
            val ok = dimOk && simRel > simIrr && (simRel - simIrr) >= 0.03
            report.addSample(JSONObject().put("idx", 0).put("kind", "zeroshot_classify")
                .put("image", "test.jpg").put("label", label).put("distractor", distractor)
                .put("dim", iv.size).put("sim_label", round3(simRel)).put("sim_distractor", round3(simIrr))
                .put("metric", "clip_margin").put("score", round3(simRel - simIrr)).put("pass", ok))
            report.gate("embed_dim_ok", dimOk)
            report.gate("clip_zeroshot", ok)
            report.put("embedding_dim", iv.size)
            return
        }
        val anchor = "The capital of France is Paris."
        val paraphrase = "Paris is the capital city of France."
        val unrelated = "A cat slept quietly on the warm windowsill all afternoon."
        val a = vec(anchor)
        val dim = a.size
        // A reranker (e.g. nv_rerankqa) emits a single relevance SCORE (dim<=1), not a sentence vector, so the
        // cosine gate does not apply — and the SDK's rerank primitive is retired. Report it ran (produced a
        // finite scalar on the NPU) instead of a misleading semantic FAIL.
        if (dim <= 1) {
            val score = a.firstOrNull()?.toDouble() ?: Double.NaN
            val ran = a.isNotEmpty() && score.isFinite()
            report.addSample(JSONObject().put("idx", 0).put("kind", "reranker")
                .put("anchor", anchor).put("dim", dim).put("rerank_score", round3(score))
                .put("metric", "reranker_scalar").put("note", "reranker score output; cosine gate N/A (rerank primitive retired)")
                .put("pass", ran))
            report.gate("embed_dim_ok", ran)
            report.gate("reranker_ran", ran)
            report.put("embedding_dim", dim).put("is_reranker", true)
            return
        }
        val p = vec(paraphrase); val u = vec(unrelated)
        val dimOk = p.size == dim && u.size == dim
        val simPara = if (dimOk) cosine(a, p) else 0.0
        val simUnrel = if (dimOk) cosine(a, u) else 0.0
        val semanticOk = dimOk && simPara > simUnrel && (simPara - simUnrel) >= NpuRubric.EMBED_MARGIN
        report.addSample(JSONObject().put("idx", 0)
            .put("anchor", anchor).put("paraphrase", paraphrase).put("unrelated", unrelated)
            .put("dim", dim).put("sim_paraphrase", round3(simPara)).put("sim_unrelated", round3(simUnrel))
            .put("metric", "cosine_margin").put("score", round3(simPara - simUnrel)).put("pass", semanticOk))
        report.gate("embed_dim_ok", dimOk)
        report.gate("embed_semantic", semanticOk)
        report.put("embedding_dim", dim).put("sim_paraphrase", round3(simPara)).put("sim_unrelated", round3(simUnrel))
    }

    private fun cosine(a: FloatArray, b: FloatArray): Double {
        var dot = 0.0; var na = 0.0; var nb = 0.0
        val n = minOf(a.size, b.size)
        for (i in 0 until n) { dot += a[i] * b[i]; na += (a[i] * a[i]).toDouble(); nb += (b[i] * b[i]).toDouble() }
        val denom = kotlin.math.sqrt(na) * kotlin.math.sqrt(nb)
        return if (denom > 0.0) dot / denom else 0.0
    }

    // ---------------------------------------------------------------- TTS ----
    private suspend fun runTts(report: RunReport, model: SingleFileModel, outDir: File?, suite: NpuSuite?) {
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
    private suspend fun register(bundle: SingleFileModel) =
        RunAnywhere.registerModel(
            id = bundle.id, name = bundle.name, url = bundle.url,
            framework = bundle.framework,
            modality = bundle.category,
        )

    /** Catalog id, or an ad-hoc bundle synthesized from -e hfRepo/arch/modality/manifest. */
    private fun resolveModel(args: Bundle): Pair<SingleFileModel, String?>? {
        args.getString("modelId")?.takeIf { it.isNotBlank() }?.let { rawId ->
            val (logicalId, requestedArch) = logicalIdAndArch(rawId)
            val model = ModelCatalog.npuCatalog.firstOrNull { it.id == rawId }
                ?: ModelCatalog.npuCatalog.firstOrNull { it.id == logicalId }
            return model?.let { it to (requestedArch ?: args.getString("arch")?.takeIf { arch -> arch.isNotBlank() }) }
        }
        val repo = args.getString("hfRepo") ?: return null
        val arch = args.getString("arch") ?: "v81"
        val category = when (args.getString("modality")?.lowercase()) {
            "llm" -> ModelCategory.MODEL_CATEGORY_LANGUAGE
            "vlm" -> ModelCategory.MODEL_CATEGORY_MULTIMODAL
            "stt", "asr" -> ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
            "tts" -> ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
            "embed", "embedding" -> ModelCategory.MODEL_CATEGORY_EMBEDDING
            else -> return null
        }
        // Only the manifest is named; commons + the engine bundle policy resolve the rest of the
        // file set from the HF tree (incl. the repo-root config.json automatically when present).
        val manifest = args.getString("manifest")?.trim()?.takeIf { it.isNotEmpty() }
            ?: args.getString("files")?.split(",")?.map { it.trim() }?.firstOrNull { it.isNotEmpty() }
            ?: return null
        return SingleFileModel(
            id = repo.substringAfterLast('/').removeSuffix("_HNPU"),
            name = repo,
            url = "https://huggingface.co/$repo/$manifest",
            framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
            category = category,
            memoryBytes = 0L,
        ) to arch
    }

    private fun modalityName(category: ModelCategory): String = when (category) {
        ModelCategory.MODEL_CATEGORY_LANGUAGE -> "llm"
        ModelCategory.MODEL_CATEGORY_MULTIMODAL -> "vlm"
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> "stt"
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> "tts"
        ModelCategory.MODEL_CATEGORY_EMBEDDING -> "embedding"
        else -> category.name.lowercase()
    }

    private fun hfRepoOf(bundle: SingleFileModel): String =
        bundle.url.removePrefix("https://huggingface.co/").split("/").take(2).joinToString("/")

    private fun logicalIdAndArch(rawId: String): Pair<String, String?> {
        val match = ARCH_SUFFIX.matchEntire(rawId) ?: return rawId to null
        return match.groupValues[1] to match.groupValues[2]
    }

    private fun loadSuite(modelId: String, arch: String): NpuSuite? {
        val assets = InstrumentationRegistry.getInstrumentation().context.assets
        return NpuSuite.load(assets, modelId) ?: NpuSuite.load(assets, "${modelId}_$arch")
    }

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
