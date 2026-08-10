package com.runanywhere.runanywhereai.data.hf

import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong

/** Which Hugging Face library the search is scoped to. Only GGUF runs on Android. */
enum class HfSearchKind { GGUF, MLX }

/** One repository row from the HF model search endpoint. */
data class HfModelSummary(
    val id: String,
    val downloads: Long,
    val likes: Long,
    /**
     * Parameter count as published by the Hub in `gguf.total`, or null when the repo does
     * not expose one. Null means "render no badge" — never a zero and never a guess.
     */
    val params: Long? = null,
)

/** One downloadable GGUF file inside a repository, with a derived quant label. */
data class HfRepoFile(
    val path: String,
    val sizeBytes: Long,
    val quantLabel: String,
)

/**
 * One entry in the curated sub-1B suggestion list. Authored, not fetched: [params] is a
 * measured `gguf.total` recorded when the entry was added, so the badge on screen is
 * exactly the number the "under 1B" claim was checked against.
 */
data class HfSuggestedModel(
    val repoId: String,
    val title: String,
    val params: Long,
    val blurb: String,
)

/**
 * The sub-1B repositories the sheet offers before the user has typed anything.
 *
 * This is deliberately a hand-authored list rather than a live query. The Hub only returns
 * a parameter count under `expand[]=gguf` (there is no cheap `expand[]=gguf.total` — the API
 * rejects it), that expansion embeds the whole Jinja chat template and costs several times
 * the payload, and it still would not help: only a handful of the top-100 most-downloaded
 * GGUF text-generation repos are sub-1B, so "fetch the top N and filter" returns almost
 * nothing. Searching for size tokens like "0.6B" leaks other modalities (ASR repos) into a
 * chat-model list. A curated list is instant, deterministic, cannot render empty, and every
 * count in it has been verified.
 *
 * Ordered ascending by parameter count. Android is GGUF-only — MLX does not run here, so no
 * MLX set exists in this file even though [HfSearchKind.MLX] does.
 */
object HuggingFaceCatalog {

    val ggufUnder1B: List<HfSuggestedModel> = listOf(
        HfSuggestedModel(
            repoId = "unsloth/SmolLM2-135M-Instruct-GGUF",
            title = "SmolLM2 135M",
            params = 134_515_008L,
            blurb = "The smallest useful chat model. Downloads in seconds.",
        ),
        HfSuggestedModel(
            repoId = "unsloth/gemma-3-270m-it-GGUF",
            title = "Gemma 3 270M",
            params = 268_098_176L,
            blurb = "Google's smallest instruction model, with a 32K context.",
        ),
        HfSuggestedModel(
            repoId = "LiquidAI/LFM2-350M-GGUF",
            title = "LFM2 350M",
            params = 354_483_968L,
            blurb = "A 128K context in a tiny model — good for long documents.",
        ),
        HfSuggestedModel(
            repoId = "HuggingFaceTB/SmolLM2-360M-Instruct-GGUF",
            title = "SmolLM2 360M",
            params = 361_821_120L,
            blurb = "More capable than 135M, still quick on any device.",
        ),
        HfSuggestedModel(
            repoId = "unsloth/Qwen3-0.6B-GGUF",
            title = "Qwen3 0.6B",
            params = 596_049_920L,
            blurb = "A strong all-rounder for its size, with a 40K context.",
        ),
        HfSuggestedModel(
            repoId = "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            title = "Qwen2.5 0.5B",
            params = 630_167_424L,
            blurb = "Widely used, dependable general chat.",
        ),
        HfSuggestedModel(
            repoId = "LiquidAI/LFM2-700M-GGUF",
            title = "LFM2 700M",
            params = 742_489_344L,
            blurb = "The long-context option, with more room to reason.",
        ),
        HfSuggestedModel(
            repoId = "ggml-org/gemma-3-1b-it-GGUF",
            title = "Gemma 3 1B",
            params = 999_885_952L,
            blurb = "The most capable model still under 1B.",
        ),
    )
}

/**
 * Formats a parameter count for the badge, with the same rule on every platform.
 *
 * The `999` clamp is load-bearing, not cosmetic: Gemma 3 1B measures 999,885,952 params,
 * which rounds to 1000 — and a chip reading "1000M" directly under a header that says
 * "All under 1B parameters." is a contradiction on screen. Clamping keeps the badge both
 * accurate and consistent with the claim. Every other entry lands on the vendor's own
 * number (135M, 268M, 362M, 596M, 630M, 742M).
 */
fun formatParameterCount(params: Long): String =
    if (params >= 1_000_000_000L) {
        "%.1fB".format(params / 1_000_000_000.0)
    } else {
        "${minOf(999L, (params / 1_000_000.0).roundToLong())}M"
    }

/**
 * Thin REST client for the public Hugging Face Hub API. The RunAnywhere SDK owns
 * model resolution + download; this only supplies the *search* + *file listing*
 * the Hub API has that the SDK does not. Mirrors the iOS `HuggingFaceHubClient`.
 *
 * All calls run on [Dispatchers.IO] and attach a bearer token from
 * [SettingsRepository] when the user has configured one (for gated/private repos).
 */
class HuggingFaceHubClient(
    private val tokenProvider: () -> String = { SettingsRepository.settings.hfToken },
) {
    private val json = Json { ignoreUnknownKeys = true }

    private val client = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .callTimeout(CALL_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

    suspend fun searchModels(query: String, kind: HfSearchKind): List<HfModelSummary> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        val body = fetch(searchUrl(trimmed, kind))
        return json.decodeFromString<List<HfModelDto>>(body)
            .filter { it.id.isNotBlank() }
            .map {
                HfModelSummary(
                    id = it.id,
                    downloads = it.downloads,
                    likes = it.likes,
                    params = it.gguf?.paramCount,
                )
            }
    }

    suspend fun listGgufFiles(repoId: String): List<HfRepoFile> {
        val body = fetch(treeUrl(repoId))
        return json.decodeFromString<List<HfTreeEntryDto>>(body)
            .filter { it.type == "file" && it.path.endsWith(GGUF_SUFFIX, ignoreCase = true) }
            .map {
                HfRepoFile(
                    path = it.path,
                    sizeBytes = it.lfs?.size ?: it.size,
                    quantLabel = deriveQuantLabel(it.path),
                )
            }
            .sortedBy { it.sizeBytes }
    }

    private fun searchUrl(query: String, kind: HfSearchKind): String {
        val builder = "$API_BASE/models".toHttpUrl().newBuilder()
            .addQueryParameter("search", query)
            .addQueryParameter("sort", "downloads")
            .addQueryParameter("direction", "-1")
            .addQueryParameter("limit", SEARCH_LIMIT.toString())
        when (kind) {
            HfSearchKind.GGUF -> {
                builder.addQueryParameter("filter", "gguf")
                // The parameter count lives in `gguf.total` and is only returned under this
                // expansion; the Hub rejects a narrower `expand[]=gguf.total`, so the whole
                // gguf block (chat template included) is the price of showing the badge.
                // Only worth paying on GGUF: MLX repos carry no gguf block at all.
                builder.addQueryParameter("expand[]", "gguf")
            }
            HfSearchKind.MLX -> builder.addQueryParameter("library", "mlx")
        }
        return builder.build().toString()
    }

    private fun treeUrl(repoId: String): String =
        "$API_BASE/models".toHttpUrl().newBuilder()
            // addPathSegments splits + encodes each "org/repo/tree/main" segment.
            .addPathSegments("${repoId.trim('/')}/tree/main")
            .addQueryParameter("recursive", "true")
            .build()
            .toString()

    private fun buildRequest(url: String): Request {
        val builder = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .get()
        val token = tokenProvider().trim()
        if (token.isNotBlank()) builder.header("Authorization", "Bearer $token")
        return builder.build()
    }

    private suspend fun fetch(url: String): String = withContext(Dispatchers.IO) {
        client.newCall(buildRequest(url)).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("Hugging Face request failed (HTTP ${response.code})")
            }
            response.body.string()
        }
    }

    @Serializable
    private data class HfModelDto(
        val id: String = "",
        val downloads: Long = 0,
        val likes: Long = 0,
        val gguf: HfGgufDto? = null,
    )

    @Serializable
    private data class HfGgufDto(
        // Held as a raw JsonElement rather than a Long because the badge is cosmetic and the
        // search is not: if the Hub ever changes this field's type, a strict Long would abort
        // the decode of the entire result list. Read loosely so a missing or unexpected value
        // degrades to "no badge".
        val total: JsonElement? = null,
    ) {
        val paramCount: Long?
            get() = (total as? JsonPrimitive)?.longOrNull?.takeIf { it > 0 }
    }

    @Serializable
    private data class HfTreeEntryDto(
        val type: String = "",
        val path: String = "",
        val size: Long = 0,
        val lfs: HfLfsDto? = null,
    )

    @Serializable
    private data class HfLfsDto(val size: Long = 0)

    companion object {
        private const val API_BASE = "https://huggingface.co/api"
        private const val GGUF_SUFFIX = ".gguf"
        private const val SEARCH_LIMIT = 25
        private const val CONNECT_TIMEOUT_SECONDS = 10L
        private const val READ_TIMEOUT_SECONDS = 20L
        private const val CALL_TIMEOUT_SECONDS = 30L

        // GGUF quant tokens (Q4_K_M, Q8_0, IQ4_XS, F16, BF16 …). Word-bounded so a
        // parameter count like "0.6B" in the filename is never mistaken for a quant.
        private val quantRegex = Regex(
            """(?i)\b(IQ\d[A-Z0-9_]*|Q\d(_K(_[MSL])?|_[01])?|BF16|F16|F32)\b""",
        )

        /** Derives a human quant label from the filename, e.g. "Qwen3-0.6B-Q4_K_M.gguf" -> "Q4_K_M". */
        internal fun deriveQuantLabel(path: String): String {
            val name = path.substringAfterLast('/')
            return quantRegex.findAll(name).lastOrNull()?.value?.uppercase()
                ?: name.removeSuffix(GGUF_SUFFIX)
        }
    }
}
