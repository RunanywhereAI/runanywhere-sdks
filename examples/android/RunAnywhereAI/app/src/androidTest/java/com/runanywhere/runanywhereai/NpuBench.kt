package com.runanywhere.runanywhereai

import android.os.Debug
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.sqrt

/**
 * Rubric thresholds, metric math, and the shareable report record for
 * [NpuModelE2ETest]. Pure host-side logic (no SDK / QNN types) so it mirrors the
 * forge per-modality rubric (`forge/forge/eval/suite.py`, `forge/forge/validate/{text,parity,audio}.py`)
 * independently of the runtime it is checking. androidTest only — NOT product code.
 *
 * The bars come straight from forge:
 *   WER_MAX 0.05 · greedy_tol edit 0.10 · repetition_ratio 0.50 · MeloTTS 44100 Hz.
 */
object NpuRubric {
    const val WER_MAX = 0.05            // ASR word-error-rate ceiling      (forge WER_MAX)
    const val EDIT_TOL = 0.10          // LLM greedy_tol token-edit ceiling (forge balanced edit_tol)
    const val REPEAT_MAX = 0.50        // coherence: immediate-repeat ratio (forge W8_SWEEP_REPEAT)
    const val TTS_RMS_MIN = 0.005      // TTS output must not be silence
    const val TTS_MIN_SECONDS = 0.30   // TTS must produce real audio
    val TTS_RATES = setOf(16000, 22050, 24000, 44100, 48000)

    /** Exact output sample rates baked into the published bundles (QHexRT TTS docs). */
    fun expectedTtsRate(modelId: String): Int? = when {
        modelId.contains("melotts", true) -> 44100
        modelId.contains("kokoro", true) -> 24000
        modelId.contains("kitten", true) -> 24000
        else -> null
    }
}

/** Metric functions that reproduce forge's parity math, token-for-token. */
object NpuMetrics {
    private val WORD = Regex("[\\p{L}\\p{N}]+(?:'[\\p{L}\\p{N}]+)*")

    /** Unicode word runs (intra-word apostrophes kept), lowercased — forge text.normalize_text. */
    fun words(s: String): List<String> = WORD.findAll(s.lowercase()).map { it.value }.toList()

    /** word-level WER = Levenshtein(ref_words, hyp_words) / |ref_words|  (forge text.wer). */
    fun wer(ref: String, hyp: String): Double {
        val r = words(ref); val h = words(hyp)
        if (r.isEmpty()) return if (h.isEmpty()) 0.0 else 1.0
        return levenshtein(r, h).toDouble() / r.size
    }

    /** normalized token-edit = Levenshtein(dev[:|gold|], gold)/|gold|  (forge parity.normalized_token_edit). */
    fun normalizedTokenEdit(dev: List<Int>, gold: List<Int>): Double {
        if (gold.isEmpty()) return if (dev.isEmpty()) 0.0 else 1.0
        return levenshtein(dev.take(gold.size), gold).toDouble() / gold.size
    }

    /** fraction of tokens equal to the immediately-preceding token  (forge repetition_ratio). */
    fun repeatRatio(ids: List<Int>): Double {
        if (ids.size < 2) return 0.0
        var rep = 0
        for (i in 1 until ids.size) if (ids[i] == ids[i - 1]) rep++
        return rep.toDouble() / (ids.size - 1)
    }

    /** word-level immediate-repeat ratio, for coherence checks on text without token ids. */
    fun wordRepeatRatio(s: String): Double {
        val w = words(s); if (w.size < 2) return 0.0
        var rep = 0
        for (i in 1 until w.size) if (w[i] == w[i - 1]) rep++
        return rep.toDouble() / (w.size - 1)
    }

    private fun <T> levenshtein(a: List<T>, b: List<T>): Int {
        val n = a.size; val m = b.size
        if (n == 0) return m
        if (m == 0) return n
        var prev = IntArray(m + 1) { it }
        var cur = IntArray(m + 1)
        for (i in 1..n) {
            cur[0] = i
            for (j in 1..m) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                cur[j] = minOf(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            val t = prev; prev = cur; cur = t
        }
        return prev[m]
    }

    /** 16-bit little-endian PCM bytes -> normalized float [-1,1]. */
    fun pcm16leToFloat(bytes: ByteArray): FloatArray {
        val n = bytes.size / 2
        val out = FloatArray(n)
        var j = 0
        for (i in 0 until n) {
            val lo = bytes[j].toInt() and 0xFF
            val hi = bytes[j + 1].toInt()
            out[i] = ((hi shl 8) or lo).toShort().toFloat() / 32768f
            j += 2
        }
        return out
    }

    /** 32-bit little-endian float PCM bytes -> float samples (QHexRT TTS emits Float32). */
    fun float32leToFloat(bytes: ByteArray): FloatArray {
        val bb = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        return FloatArray(bytes.size / 4) { bb.float }
    }

    fun rms(x: FloatArray): Double {
        if (x.isEmpty()) return 0.0
        var s = 0.0
        for (v in x) s += v.toDouble() * v
        return sqrt(s / x.size)
    }

    /** Process peak RSS (kB) — high-water mark, /proc/self/status VmHWM. -1 if unreadable. */
    fun peakRssKb(): Long = try {
        File("/proc/self/status").readLines()
            .firstOrNull { it.startsWith("VmHWM") }
            ?.let { Regex("\\d+").find(it)?.value?.toLongOrNull() } ?: -1L
    } catch (e: Exception) { -1L }

    /** Current total PSS (kB) via Debug.MemoryInfo — sample right after inference. -1 on failure. */
    fun totalPssKb(): Long = try {
        val mi = Debug.MemoryInfo(); Debug.getMemoryInfo(mi); mi.totalPss.toLong()
    } catch (e: Exception) { -1L }
}

/**
 * Accumulates one model's run into a single shareable JSON report (written to the
 * app files dir, adb-pullable) plus a compact `NPU_E2E …` logcat line the runner greps.
 */
class RunReport(
    private val modelId: String,
    hfRepo: String,
    private val modality: String,
    arch: String,
) {
    private val root = JSONObject()
    private val samples = JSONArray()
    private val gates = JSONObject()
    private val startMs = System.currentTimeMillis()

    init {
        root.put("schema", "npu_e2e/v1")
            .put("model_id", modelId).put("hf_repo", hfRepo)
            .put("modality", modality).put("arch", arch)
            .put("started_unix_ms", startMs)
    }

    fun put(key: String, value: Any?) = apply { root.put(key, value ?: JSONObject.NULL) }
    fun gate(name: String, pass: Boolean) = apply { gates.put(name, pass) }
    fun addSample(sample: JSONObject) = apply { samples.put(sample) }

    fun allGatesPass(): Boolean {
        val keys = gates.keys()
        while (keys.hasNext()) if (!gates.getBoolean(keys.next())) return false
        return true
    }

    /** Finalize + persist the full report; returns the compact one-line summary. */
    fun finish(status: String, phase: String, detail: String, outDir: File?): String {
        root.put("gates", gates).put("samples", samples)
            .put("status", status).put("phase", phase).put("detail", detail)
            .put("duration_ms", System.currentTimeMillis() - startMs)
        outDir?.let {
            runCatching {
                it.mkdirs()
                File(it, "npu_e2e_${modelId}.json").writeText(root.toString(2))
            }
        }
        // compact, greppable, one token per key — headline metric is modality-specific.
        val sb = StringBuilder("NPU_E2E id=$modelId modality=$modality arch=${root.optString("arch")}")
        sb.append(" status=$status phase=$phase")
        for (k in listOf("framework", "soc_model", "download_s", "load_ms",
                "decode_toks", "ttft_ms", "tokens_per_s", "rtf", "wer",
                "sample_rate", "peak_rss_mb", "vision_ms")) {
            if (root.has(k)) sb.append(" $k=${root.get(k)}")
        }
        sb.append(" gates=$gates detail=\"${detail.replace('\n', ' ').take(160)}\"")
        return sb.toString()
    }
}

/** One case from a canonical `npu_suite/v1` file (QHexRT2/testing/gen/build_suites.py). */
class SuiteCase(private val o: JSONObject) {
    private val input = o.optJSONObject("input") ?: JSONObject()
    val id: String get() = o.optString("id")
    val text: String? get() = input.optString("text").ifBlank { null }
    val wavAsset: String? get() = input.optString("wav_asset").ifBlank { null }
    val imageAsset: String? get() = input.optString("image_asset").ifBlank { null }
    val goldText: String get() = o.optString("gold_text")
    val goldWav: String? get() = o.optString("gold_wav").ifBlank { null }
    val expectedRate: Int get() = o.optInt("expected_sample_rate", 0)
    val keywords: List<String> get() = o.optJSONArray("expect_keywords")
        ?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
    val goldTokens: List<Int>? get() = o.optJSONArray("gold_tokens")
        ?.let { a -> (0 until a.length()).map { a.getInt(it) } }?.takeIf { it.isNotEmpty() }
}

/**
 * A canonical per-model device-test suite — the SAME cases + gold + thresholds forge/goal_npu validates
 * against (`QHexRT2/testing/suites/<modelId>.json`, synced into `androidTest/assets/npu_suites/`). When a
 * suite is shipped for a model, the harness runs THESE cases with the forge metric (greedy_tol / wer /
 * audio) so "device-validated" means the same thing on both planes. Absent → the harness falls back to its
 * built-in heuristic cases.
 */
class NpuSuite(private val o: JSONObject) {
    val modality: String get() = o.optString("modality")
    private val gate: JSONObject get() = o.optJSONObject("gate") ?: JSONObject()
    val metric: String get() = gate.optString("metric")
    val editTol: Double get() = gate.optDouble("edit_tol", NpuRubric.EDIT_TOL)
    val werMax: Double get() = gate.optDouble("wer_max", NpuRubric.WER_MAX)
    val passFrac: Double get() = gate.optDouble("suite_pass_frac", 0.60)
    val cases: List<SuiteCase> get() = o.optJSONArray("cases")
        ?.let { a -> (0 until a.length()).map { SuiteCase(a.getJSONObject(it)) } } ?: emptyList()

    companion object {
        /** Load `assets/npu_suites/<modelId>.json` from the TEST apk; null if none shipped for this model. */
        fun load(assets: android.content.res.AssetManager, modelId: String): NpuSuite? = try {
            assets.open("npu_suites/$modelId.json").use {
                NpuSuite(JSONObject(String(it.readBytes(), Charsets.UTF_8)))
            }
        } catch (e: Exception) { null }
    }
}
