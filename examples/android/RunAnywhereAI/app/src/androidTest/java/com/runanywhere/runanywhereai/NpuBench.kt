package com.runanywhere.runanywhereai

import android.os.Debug
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import kotlin.math.sqrt

/**
 * Rubric thresholds, metric math, and the shareable report record for
 * [NpuModelE2ETest]. Pure host-side logic (no SDK / QNN types) so it mirrors the
 * conversion parity rubric independently of the runtime it is checking. androidTest only - NOT product code.
 *
 * Shared default bars used only when a canonical field permits a default. Production reports still
 * enumerate and reapply every field declared by the per-model suite.
 */
object NpuRubric {
    const val WER_MAX = 0.05            // ASR word-error-rate ceiling      (forge WER_MAX)
    const val REPEAT_MAX = 0.50        // coherence: immediate-repeat ratio (forge W8_SWEEP_REPEAT)
    const val TTS_RMS_MIN = 0.005      // TTS output must not be silence
    const val TTS_MIN_SECONDS = 0.30   // TTS must produce real audio
    const val TTS_INTELLIGIBILITY_WER_MAX = 0.15
    const val INPAINT_FULL_COSINE_MIN = 0.999
    const val INPAINT_HOLE_COSINE_MIN = 0.99
    const val INPAINT_HOLE_RELATIVE_L2_MAX = 0.15
    const val INPAINT_FULL_PSNR_MIN = 30.0
    const val INPAINT_HOLE_PSNR_MIN = 30.0
    const val INPAINT_SEAM_PSNR_MIN = 35.0
    const val INPAINT_UNMASKED_MAE_MAX = 0.10       // RGB8 levels
    const val INPAINT_UNMASKED_P99_MAX = 1.0       // RGB8 levels
    const val INPAINT_UNMASKED_WITHIN_1_MIN = 0.999
    const val INPAINT_HOLE_CHANGED_MIN = 0.05

}

/** Metric functions that reproduce forge's parity math, token-for-token. */
object NpuMetrics {
    private val WORD = Regex("[\\p{L}\\p{N}]+(?:'[\\p{L}\\p{N}]+)*")
    private val ASR_ALIASES = mapOf("mr" to "mister", "neuro" to "neural")
    private val DIGIT_WORDS = mapOf(
        '0' to "zero", '1' to "one", '2' to "two", '3' to "three", '4' to "four",
        '5' to "five", '6' to "six", '7' to "seven", '8' to "eight", '9' to "nine"
    )

    /** Unicode word runs (intra-word apostrophes kept), lowercased — forge text.normalize_text. */
    fun words(s: String): List<String> {
        val out = mutableListOf<String>()
        for (m in WORD.findAll(s.lowercase())) {
            val w = ASR_ALIASES[m.value] ?: m.value
            if (w.all { it.isDigit() }) {
                w.forEach { out.add(DIGIT_WORDS[it] ?: it.toString()) }
            } else {
                out.add(w)
            }
        }
        return out
    }

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

    data class InpaintMetrics(
        val fullCosine: Double,
        val holeCosine: Double,
        val holeRelativeL2: Double,
        val fullPsnrDb: Double,
        val holePsnrDb: Double,
        val seamPsnrDb: Double,
        val unmaskedMeanAbsoluteError: Double,
        val unmaskedP99AbsoluteError: Double,
        val unmaskedWithinOneLsbFraction: Double,
        val holeChangedFraction: Double,
        val holePixels: Int,
        val seamPixels: Int,
    )

    /** Forge-equivalent RGB8 full/hole/seam and unmasked preservation metrics. */
    fun inpaintMetrics(
        inputRgb: ByteArray,
        mask: BooleanArray,
        referenceRgb: ByteArray,
        candidateRgb: ByteArray,
        width: Int,
        height: Int,
        seamRadius: Int = 4,
    ): InpaintMetrics {
        val pixels = width * height
        require(width > 0 && height > 0)
        require(mask.size == pixels)
        require(inputRgb.size == pixels * 3)
        require(referenceRgb.size == pixels * 3)
        require(candidateRgb.size == pixels * 3)
        require(mask.any { it } && mask.any { !it })

        val dilated = dilateMask(mask, width, height, seamRadius)
        val eroded = erodeMask(mask, width, height, seamRadius)
        val seam = BooleanArray(pixels) { dilated[it] != eroded[it] }
        val full = BooleanArray(pixels) { true }
        val unmaskedErrors = ArrayList<Int>((pixels - mask.count { it }) * 3)
        var withinOne = 0L
        var changedHole = 0
        var holePixels = 0
        for (p in 0 until pixels) {
            if (mask[p]) {
                holePixels++
                val base = p * 3
                if ((0..2).any {
                        kotlin.math.abs(
                            (candidateRgb[base + it].toInt() and 0xff) -
                                (inputRgb[base + it].toInt() and 0xff),
                        ) > 1
                    }
                ) {
                    changedHole++
                }
            } else {
                val base = p * 3
                for (c in 0..2) {
                    val error =
                        kotlin.math.abs(
                            (candidateRgb[base + c].toInt() and 0xff) -
                                (referenceRgb[base + c].toInt() and 0xff),
                        )
                    unmaskedErrors.add(error)
                    if (error <= 1) withinOne++
                }
            }
        }
        unmaskedErrors.sort()
        val p99Index =
            (kotlin.math.ceil(unmaskedErrors.size * 0.99).toInt() - 1)
                .coerceIn(0, unmaskedErrors.lastIndex)
        return InpaintMetrics(
            fullCosine = regionCosine(referenceRgb, candidateRgb, full),
            holeCosine = regionCosine(referenceRgb, candidateRgb, mask),
            holeRelativeL2 = regionRelativeL2(referenceRgb, candidateRgb, mask),
            fullPsnrDb = regionPsnr(referenceRgb, candidateRgb, full),
            holePsnrDb = regionPsnr(referenceRgb, candidateRgb, mask),
            seamPsnrDb = regionPsnr(referenceRgb, candidateRgb, seam),
            unmaskedMeanAbsoluteError = unmaskedErrors.average(),
            unmaskedP99AbsoluteError = unmaskedErrors[p99Index].toDouble(),
            unmaskedWithinOneLsbFraction = withinOne.toDouble() / unmaskedErrors.size,
            holeChangedFraction = changedHole.toDouble() / holePixels,
            holePixels = holePixels,
            seamPixels = seam.count { it },
        )
    }

    private fun regionCosine(
        referenceRgb: ByteArray,
        candidateRgb: ByteArray,
        selectedPixels: BooleanArray,
    ): Double {
        var dot = 0.0
        var referenceSquared = 0.0
        var candidateSquared = 0.0
        for (p in selectedPixels.indices) {
            if (!selectedPixels[p]) continue
            val base = p * 3
            for (c in 0..2) {
                val reference = (referenceRgb[base + c].toInt() and 0xff).toDouble()
                val candidate = (candidateRgb[base + c].toInt() and 0xff).toDouble()
                dot += reference * candidate
                referenceSquared += reference * reference
                candidateSquared += candidate * candidate
            }
        }
        val denominator = sqrt(referenceSquared * candidateSquared)
        return dot / maxOf(denominator, 1e-12)
    }

    private fun regionRelativeL2(
        referenceRgb: ByteArray,
        candidateRgb: ByteArray,
        selectedPixels: BooleanArray,
    ): Double {
        var errorSquared = 0.0
        var referenceSquared = 0.0
        for (p in selectedPixels.indices) {
            if (!selectedPixels[p]) continue
            val base = p * 3
            for (c in 0..2) {
                val reference = (referenceRgb[base + c].toInt() and 0xff).toDouble()
                val candidate = (candidateRgb[base + c].toInt() and 0xff).toDouble()
                val delta = candidate - reference
                errorSquared += delta * delta
                referenceSquared += reference * reference
            }
        }
        return sqrt(errorSquared) / maxOf(sqrt(referenceSquared), 1e-12)
    }

    private fun regionPsnr(
        referenceRgb: ByteArray,
        candidateRgb: ByteArray,
        selectedPixels: BooleanArray,
    ): Double {
        var squaredError = 0.0
        var count = 0L
        for (p in selectedPixels.indices) {
            if (!selectedPixels[p]) continue
            val base = p * 3
            for (c in 0..2) {
                val delta =
                    (candidateRgb[base + c].toInt() and 0xff) -
                        (referenceRgb[base + c].toInt() and 0xff)
                squaredError += delta.toDouble() * delta
                count++
            }
        }
        require(count > 0)
        val mse = squaredError / count
        return if (mse == 0.0) 99.0 else 10.0 * kotlin.math.log10(255.0 * 255.0 / mse)
    }

    private fun dilateMask(
        source: BooleanArray,
        width: Int,
        height: Int,
        iterations: Int,
    ): BooleanArray {
        var current = source.copyOf()
        repeat(iterations) {
            val next = current.copyOf()
            for (y in 0 until height) {
                for (x in 0 until width) {
                    if (!current[y * width + x]) continue
                    if (x > 0) next[y * width + x - 1] = true
                    if (x + 1 < width) next[y * width + x + 1] = true
                    if (y > 0) next[(y - 1) * width + x] = true
                    if (y + 1 < height) next[(y + 1) * width + x] = true
                }
            }
            current = next
        }
        return current
    }

    private fun erodeMask(
        source: BooleanArray,
        width: Int,
        height: Int,
        iterations: Int,
    ): BooleanArray {
        var current = source.copyOf()
        repeat(iterations) {
            val next = BooleanArray(current.size)
            for (y in 1 until height - 1) {
                for (x in 1 until width - 1) {
                    val p = y * width + x
                    next[p] =
                        current[p] && current[p - 1] && current[p + 1] &&
                        current[p - width] && current[p + width]
                }
            }
            current = next
        }
        return current
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
                "sample_rate", "peak_rss_mb", "vision_ms", "inpaint_ms",
                "full_psnr_db", "hole_psnr_db", "seam_psnr_db", "embed_inputs",
                "embed_ms_avg", "embedding_dim", "retrieval_min_margin")) {
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
    val query: String? get() = input.optString("query").ifBlank { null }
    val positive: String? get() = input.optString("positive").ifBlank { null }
    val negative: String? get() = input.optString("negative").ifBlank { null }
    val wavAsset: String? get() = input.optString("wav_asset").ifBlank { null }
    val imageAsset: String? get() = input.optString("image_asset").ifBlank { null }
    val maskAsset: String? get() = input.optString("mask_asset").ifBlank { null }
    val metricImageAsset: String? get() = o.optString("metric_image_asset").ifBlank { null }
    val metricMaskAsset: String? get() = o.optString("metric_mask_asset").ifBlank { null }
    val referenceImageAsset: String? get() = o.optString("reference_image_asset").ifBlank { null }
    val expectedWidth: Int get() = o.optInt("expected_width", 0)
    val expectedHeight: Int get() = o.optInt("expected_height", 0)
    val goldText: String get() = o.optString("gold_text")
    val goldWav: String? get() = o.optString("gold_wav").ifBlank { null }
    val expectedRate: Int get() = o.optInt("expected_sample_rate", 0)
    val keywords: List<String> get() = o.optJSONArray("expect_keywords")
        ?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
    val goldTokens: List<Int>? get() = o.optJSONArray("gold_tokens")
        ?.let { a -> (0 until a.length()).map { a.getInt(it) } }?.takeIf { it.isNotEmpty() }
    val maxNew: Int get() = o.optInt("max_new", 0)
}

/**
 * A canonical per-model device-test suite — the SAME cases + gold + thresholds forge/goal_npu validates
 * against (`QHexRT2/testing/suites/<modelId>.json`, synced into `androidTest/assets/npu_suites/`). When a
 * suite is shipped for a model, the harness runs THESE cases with its declared Android-executable metric.
 * The host aggregator rejects unknown or unapplied gate fields.
 */
class NpuSuite(
    private val o: JSONObject,
    val suiteId: String,
    val sha256: String,
) {
    val modality: String get() = o.optString("modality")
    private val selectedProfile: JSONObject get() = o.optJSONObject("selected_profile") ?: JSONObject()
    private val gate: JSONObject get() = o.optJSONObject("gate") ?: JSONObject()
    val policySha256: String get() = selectedProfile.optString("policy_sha256")
    val manifestSha256: String get() = selectedProfile.optString("manifest_sha256")
    val contextSha256: String get() = selectedProfile.optString("context_sha256")
    val contextSha256s: List<String>
        get() = selectedProfile.optJSONArray("context_sha256s")
            ?.let { a -> (0 until a.length()).map { a.getString(it) } }
            ?.takeIf { it.isNotEmpty() }
            ?: listOfNotNull(contextSha256.takeIf { it.isNotBlank() })
    val artifactSha256s: Map<String, String>
        get() {
            val values = selectedProfile.optJSONObject("artifact_sha256s") ?: return emptyMap()
            val result = linkedMapOf<String, String>()
            val keys = values.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                result[key] = values.getString(key)
            }
            return result
        }
    val metric: String get() = gate.optString("metric")
    val werMax: Double get() = gate.optDouble("wer_max", NpuRubric.WER_MAX)
    val passFrac: Double get() = gate.optDouble("suite_pass_frac", 0.60)
    val minInputs: Int get() = gate.optInt("min_inputs", 1)
    val minDecodeToks: Double get() = gate.optDouble("min_decode_toks", 0.0)
    val minTriples: Int get() = gate.optInt("min_triples", 1)
    val expectedDimension: Int get() = gate.optInt("expected_dimension", 0)
    val minimumPairwiseMargin: Double get() = gate.optDouble("minimum_pairwise_margin", 0.0)
    val l2NormMin: Double get() = gate.optDouble("l2_norm_min", 0.99)
    val l2NormMax: Double get() = gate.optDouble("l2_norm_max", 1.01)
    val queryPrefix: String get() = gate.optString("query_prefix")
    val documentPrefix: String get() = gate.optString("document_prefix")
    val maxNew: Int get() = gate.optInt("max_new", 0)
    val expectedSampleRate: Int get() = gate.optInt("expected_sample_rate", 0)
    val intelligibilityWerMax: Double get() =
        gate.optDouble("intelligibility_wer_max", NpuRubric.TTS_INTELLIGIBILITY_WER_MAX)
    val rmsMin: Double get() = gate.optDouble("rms_min", NpuRubric.TTS_RMS_MIN)
    val minSeconds: Double get() = gate.optDouble("min_seconds", NpuRubric.TTS_MIN_SECONDS)
    val gateKeys: List<String>
        get() {
            val keys = mutableListOf<String>()
            val iterator = gate.keys()
            while (iterator.hasNext()) keys += iterator.next()
            return keys.sorted()
        }
    val fullCosineMin: Double get() = gate.optDouble(
        "minimum_full_cosine",
        NpuRubric.INPAINT_FULL_COSINE_MIN,
    )
    val holeCosineMin: Double get() = gate.optDouble(
        "minimum_hole_cosine",
        NpuRubric.INPAINT_HOLE_COSINE_MIN,
    )
    val holeRelativeL2Max: Double get() = gate.optDouble(
        "maximum_hole_relative_l2",
        NpuRubric.INPAINT_HOLE_RELATIVE_L2_MAX,
    )
    val fullPsnrMin: Double get() = gate.optDouble("minimum_full_psnr_db", NpuRubric.INPAINT_FULL_PSNR_MIN)
    val holePsnrMin: Double get() = gate.optDouble("minimum_hole_psnr_db", NpuRubric.INPAINT_HOLE_PSNR_MIN)
    val seamPsnrMin: Double get() = gate.optDouble("minimum_seam_psnr_db", NpuRubric.INPAINT_SEAM_PSNR_MIN)
    val unmaskedMaeMax: Double get() = gate.optDouble(
        "maximum_unmasked_mean_absolute_error_rgb8",
        NpuRubric.INPAINT_UNMASKED_MAE_MAX,
    )
    val unmaskedP99Max: Double get() = gate.optDouble(
        "maximum_unmasked_p99_absolute_error_rgb8",
        NpuRubric.INPAINT_UNMASKED_P99_MAX,
    )
    val unmaskedWithinOneMin: Double get() = gate.optDouble(
        "minimum_unmasked_rgb8_within_one_lsb_fraction",
        NpuRubric.INPAINT_UNMASKED_WITHIN_1_MIN,
    )
    val holeChangedMin: Double get() = gate.optDouble(
        "minimum_hole_changed_fraction",
        NpuRubric.INPAINT_HOLE_CHANGED_MIN,
    )
    val cases: List<SuiteCase> get() = o.optJSONArray("cases")
        ?.let { a -> (0 until a.length()).map { SuiteCase(a.getJSONObject(it)) } } ?: emptyList()

    companion object {
        /** Load `assets/npu_suites/<modelId>.json` from the TEST apk; null if none shipped for this model. */
        fun load(assets: android.content.res.AssetManager, modelId: String): NpuSuite? = try {
            val raw = assets.open("npu_suites/$modelId.json").use { it.readBytes() }
            val payload = JSONObject(String(raw, Charsets.UTF_8))
            require(payload.optString("schema") == "npu_suite/v1")
            require(payload.optString("model_id") == modelId)
            require((payload.optJSONArray("cases")?.length() ?: 0) > 0)
            require(payload.optJSONObject("gate") != null)
            NpuSuite(
                o = payload,
                suiteId = modelId,
                sha256 = MessageDigest.getInstance("SHA-256").digest(raw)
                    .joinToString("") { "%02x".format(it.toInt() and 0xff) },
            )
        } catch (e: Exception) { null }
    }
}
