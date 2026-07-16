package com.runanywhere.runanywhereai.data.hf

import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Which Hugging Face library the search is scoped to. Only GGUF runs on Android. */
enum class HfSearchKind { GGUF, MLX }

/** One repository row from the HF model search endpoint. */
data class HfModelSummary(
    val id: String,
    val downloads: Long,
    val likes: Long,
)

/** One downloadable GGUF file inside a repository, with a derived quant label. */
data class HfRepoFile(
    val path: String,
    val sizeBytes: Long,
    val quantLabel: String,
)

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
            .map { HfModelSummary(id = it.id, downloads = it.downloads, likes = it.likes) }
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
            HfSearchKind.GGUF -> builder.addQueryParameter("filter", "gguf")
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
    )

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
