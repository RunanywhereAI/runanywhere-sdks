package com.runanywhere.runanywhereai.tools

import ai.runanywhere.proto.v1.ToolParameter
import ai.runanywhere.proto.v1.ToolParameterType
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentPolicy
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RAToolValue
import com.runanywhere.sdk.public.extensions.LLM.array
import com.runanywhere.sdk.public.extensions.LLM.`object`
import com.runanywhere.sdk.public.extensions.LLM.string
import com.runanywhere.sdk.public.types.RAToolDefinition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayOutputStream
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** Web search through a configured proxy or the keyless DuckDuckGo fallback. */
internal object WebSearchTool {
    private const val MAX_RESULTS = 5
    private const val MAX_RESPONSE_BYTES = 1_000_000
    private const val MAX_QUERY_CHARS = 400
    private const val MAX_QUERY_WORDS = 50
    private val reportableDiagnosticCodes = setOf(
        "web_search_invalid_device_identity",
        "web_search_lite_fetch_failed",
        "web_search_lite_parser_no_results",
    )
    private val reportedDiagnosticCodes = ConcurrentHashMap.newKeySet<String>()
    private val userAgent = "Mozilla/5.0 RunAnywhere/${BuildConfig.VERSION_NAME}"
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        // Search queries may only be sent to the two fixed HTTPS origins below.
        .followRedirects(false)
        .followSslRedirects(false)
        .build()

    val definition = RAToolDefinition(
        name = "search_web",
        description = "Searches the web for current information and returns source links.",
        parameters = listOf(
            ToolParameter(
                name = "query",
                type = ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
                description = "A concise web search query.",
                required = true,
            ),
        ),
        category = "Web",
    )

    suspend fun execute(args: Map<String, RAToolValue>): Map<String, RAToolValue> {
        val settings = SettingsRepository.settings
        val route = WebSearchConsentPolicy.routeFor(BuildConfig.WEB_SEARCH_URL)
        if (
            !WebSearchConsentPolicy.permitsTransfer(
                WebSearchConsentState(
                    toolsEnabled = settings.toolCallingEnabled,
                    acceptedScope = settings.webSearchConsentScope,
                    currentScope = route?.scope,
                ),
            )
        ) {
            return errorPayload("Web search requires affirmative permission")
        }
        return search(args["query"]?.string.orEmpty())
    }

    internal suspend fun search(
        query: String,
        backendUrl: String = BuildConfig.WEB_SEARCH_URL,
        backendFetcher: suspend (String, String) -> String = { endpoint, value ->
            fetchBackend(endpoint, value)
        },
        publicFetcher: suspend (String) -> String = { fetch(it) },
    ): Map<String, RAToolValue> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return errorPayload("Missing search query")
        val wordCount = trimmed.split(Regex("\\s+")).size
        if (
            trimmed.length > MAX_QUERY_CHARS ||
            wordCount > MAX_QUERY_WORDS ||
            trimmed.any { Character.getType(it) == Character.CONTROL.toInt() }
        ) {
            return errorPayload("Search query is too long or contains unsupported characters")
        }

        if (backendUrl.isNotBlank()) {
            return runCatching {
                val endpoint = parseWebSearchEndpoint(backendUrl)
                val results = parseBackendResults(backendFetcher(endpoint, trimmed)).take(MAX_RESULTS)
                check(results.isNotEmpty()) { "Search service returned no results" }
                resultPayload(trimmed, results)
            }.getOrElse { failure ->
                if (failure is InvalidWebSearchDeviceIdentityException) {
                    // This fixed code is safe for both local logs and the allowlisted telemetry mapper.
                    reportDiagnostic("web_search_invalid_device_identity")
                }
                errorPayload("Web search is temporarily unavailable")
            }
        }

        // Builds without a configured proxy use a keyless public endpoint, so no
        // confidential search-provider credential is embedded in the APK.
        val liteAttempt = runCatching {
            parseLiteResults(publicFetcher(buildLiteSearchUrl(trimmed))).take(MAX_RESULTS)
        }.onFailure {
            reportDiagnostic("web_search_lite_fetch_failed")
        }
        val liteResults = liteAttempt.getOrDefault(emptyList())
        if (liteResults.isNotEmpty()) return resultPayload(trimmed, liteResults)
        if (liteAttempt.isSuccess) {
            // Do not include the query or response body: this is only a bounded markup-drift signal.
            reportDiagnostic("web_search_lite_parser_no_results")
        }

        return runCatching {
            parseInstantAnswer(trimmed, publicFetcher(buildInstantAnswerUrl(trimmed)))
        }.getOrElse {
            errorPayload("Web search is temporarily unavailable")
        }
    }

    internal fun parseWebSearchEndpoint(endpoint: String): String {
        val uri = runCatching { URI(endpoint.trim()) }.getOrNull()
            ?: throw IllegalArgumentException("Web search is not configured for this build")
        require(
            uri.scheme.equals("https", ignoreCase = true) &&
                !uri.host.isNullOrBlank() &&
                uri.userInfo == null,
        ) { "Web search is not configured for this build" }
        return uri.toString()
    }

    internal fun buildLiteSearchUrl(query: String): String =
        "https://lite.duckduckgo.com/lite/".toHttpUrl().newBuilder()
            .addQueryParameter("q", query)
            .build()
            .toString()

    private fun buildInstantAnswerUrl(query: String): String =
        "https://api.duckduckgo.com/".toHttpUrl().newBuilder()
            .addQueryParameter("q", query)
            .addQueryParameter("format", "json")
            .addQueryParameter("no_redirect", "1")
            .addQueryParameter("no_html", "1")
            .addQueryParameter("skip_disambig", "1")
            .build()
            .toString()

    private suspend fun fetch(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent)
            .header("Accept", "text/html,application/json")
            .get()
            .build()
        return fetch(request)
    }

    private suspend fun fetchBackend(endpoint: String, query: String): String {
        val request = buildBackendRequest(
            endpoint = endpoint,
            query = query,
            apiKey = BuildConfig.RUNANYWHERE_API_KEY,
            deviceId = RunAnywhere.deviceId,
        )
        return fetch(request)
    }

    internal fun buildBackendRequest(
        endpoint: String,
        query: String,
        apiKey: String,
        deviceId: String,
    ): Request {
        require(apiKey.isNotBlank()) { "Web search backend authentication is not configured" }
        val canonicalDeviceId = validateDeviceId(deviceId)
        val payload = buildJsonObject {
            put("query", query)
            put("count", MAX_RESULTS)
        }.toString()
        return Request.Builder()
            .url(endpoint)
            .header("User-Agent", userAgent)
            .header("Accept", "application/json")
            .header("X-RunAnywhere-Device-ID", canonicalDeviceId)
            .header("Authorization", "Bearer $apiKey")
            .post(payload.toRequestBody(jsonMediaType))
            .build()
    }

    internal fun validateDeviceId(deviceId: String): String =
        runCatching { UUID.fromString(deviceId).toString() }
            .getOrElse { throw InvalidWebSearchDeviceIdentityException() }

    private suspend fun fetch(request: Request): String = withContext(Dispatchers.IO) {
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "Search HTTP ${response.code}" }
            val body = response.body
            val declaredLength = body.contentLength()
            check(declaredLength < 0 || declaredLength <= MAX_RESPONSE_BYTES) { "Search response is too large" }
            val input = body.byteStream()
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                check(output.size() + count <= MAX_RESPONSE_BYTES) { "Search response is too large" }
                output.write(buffer, 0, count)
            }
            output.toString(StandardCharsets.UTF_8.name())
        }
    }

    internal data class SearchResult(
        val title: String,
        val url: String,
        val snippet: String,
    )

    internal fun parseLiteResults(html: String): List<SearchResult> {
        val linkPattern = Regex(
            """<a(?=[^>]*class=['\"][^'\"]*result-link[^'\"]*['\"])(?=[^>]*href=['\"]([^'\"]+)['\"])[^>]*>(.*?)</a>""",
            setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
        )
        val snippetPattern = Regex(
            """<td[^>]*class=['\"][^'\"]*result-snippet[^'\"]*['\"][^>]*>\s*([\s\S]*?)\s*</td>""",
            RegexOption.IGNORE_CASE,
        )
        return linkPattern.findAll(html).mapNotNull { match ->
            val url = resolveResultUrl(decodeHtml(match.groupValues[1]))
            val title = cleanHtml(match.groupValues[2])
            if (title.isBlank() || url.isBlank()) return@mapNotNull null
            val tailStart = match.range.last + 1
            val tail = html.substring(tailStart, minOf(html.length, tailStart + 1_500))
            val snippet = snippetPattern.find(tail)?.groupValues?.getOrNull(1)?.let(::cleanHtml)
                ?.takeIf { it.isNotBlank() }
                ?: title
            SearchResult(title = title, url = url, snippet = snippet)
        }.toList()
    }

    internal fun parseBackendResults(rawJson: String): List<SearchResult> {
        val root = json.parseToJsonElement(rawJson).jsonObject
        val results = (root["results"] as? JsonArray)
            ?: ((root["web"] as? JsonObject)?.get("results") as? JsonArray)
            ?: return emptyList()
        return results.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            val title = obj.string("title")
            val url = safeHttpUrl(obj.string("url"))
            val snippet = obj.string("snippet").ifBlank { obj.string("description") }
            if (title.isBlank() || url.isBlank()) null
            else SearchResult(title, url, snippet.ifBlank { title })
        }
    }

    internal fun parseInstantAnswer(query: String, rawJson: String): Map<String, RAToolValue> {
        val root = json.parseToJsonElement(rawJson).jsonObject
        val related = flattenRelated(root["RelatedTopics"]).take(MAX_RESULTS)
        val heading = root.string("Heading")
        val directAnswer = root.string("AbstractText")
            .ifBlank { root.string("Answer") }
        if (directAnswer.isBlank() && related.isEmpty()) {
            return errorPayload("Web search is temporarily unavailable")
        }
        val summary = directAnswer.ifBlank { related.first().snippet }
        val source = safeHttpUrl(root.string("AbstractURL")).ifBlank { buildSearchResultsUrl(query) }
        return linkedMapOf(
            "query" to RAToolValue.string(query),
            "result_count" to RAToolValue.string((related.size + if (directAnswer.isBlank()) 0 else 1).toString()),
            "heading" to RAToolValue.string(heading.ifBlank { query }),
            "summary" to RAToolValue.string(summary),
            "source_url" to RAToolValue.string(source),
        ).apply {
            if (related.isNotEmpty()) {
                put("related_results", RAToolValue.array(related.map(::toolResultValue)))
            }
        }
    }

    private fun flattenRelated(element: JsonElement?): List<SearchResult> {
        val array = element as? JsonArray ?: return emptyList()
        return array.flatMap { item ->
            val obj = item as? JsonObject ?: return@flatMap emptyList()
            val nested = obj["Topics"]
            if (nested is JsonArray) {
                flattenRelated(nested)
            } else {
                val text = obj.string("Text")
                val url = safeHttpUrl(obj.string("FirstURL"))
                if (text.isBlank() || url.isBlank()) emptyList()
                else listOf(SearchResult(text.substringBefore(" - "), url, text))
            }
        }
    }

    private fun resultPayload(query: String, results: List<SearchResult>): Map<String, RAToolValue> {
        val first = results.first()
        return linkedMapOf(
            "query" to RAToolValue.string(query),
            "result_count" to RAToolValue.string(results.size.toString()),
            "heading" to RAToolValue.string(first.title),
            "summary" to RAToolValue.string(first.snippet),
            "source_url" to RAToolValue.string(first.url),
            "related_results" to RAToolValue.array(results.drop(1).map(::toolResultValue)),
        )
    }

    private fun toolResultValue(result: SearchResult): RAToolValue = RAToolValue.`object`(
        mapOf(
            "title" to RAToolValue.string(result.title),
            "text" to RAToolValue.string(result.snippet),
            "url" to RAToolValue.string(result.url),
        ),
    )

    private fun errorPayload(message: String): Map<String, RAToolValue> =
        mapOf("error" to RAToolValue.string(message))

    private fun reportDiagnostic(code: String) {
        // Each fixed code is emitted at most once per process: useful for diagnosis without
        // turning repeated model searches into an unbounded diagnostic stream.
        if (code !in reportableDiagnosticCodes || !reportedDiagnosticCodes.add(code)) return
        // Observability must not make search fail (including plain JVM tests without android.util.Log).
        runCatching { RACLog.w(code) }
    }

    private fun buildSearchResultsUrl(query: String): String =
        "https://duckduckgo.com/".toHttpUrl().newBuilder()
            .addQueryParameter("q", query)
            .build()
            .toString()

    private fun resolveResultUrl(href: String): String {
        val marker = "uddg="
        val encoded = href.substringAfter(marker, "").substringBefore('&')
        val decoded = if (encoded.isNotBlank()) {
            runCatching { URLDecoder.decode(encoded, StandardCharsets.UTF_8.name()) }.getOrDefault(encoded)
        } else if (href.startsWith("//")) {
            "https:$href"
        } else {
            href
        }
        return safeHttpUrl(decoded)
    }

    private fun safeHttpUrl(value: String): String = runCatching {
        val uri = URI(value.trim())
        if (
            (uri.scheme.equals("https", true) || uri.scheme.equals("http", true)) &&
            !uri.host.isNullOrBlank() &&
            uri.userInfo == null
        ) {
            uri.toString()
        } else {
            ""
        }
    }.getOrDefault("")

    private fun cleanHtml(value: String): String = decodeHtml(value.replace(Regex("<[^>]+>"), " "))
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun decodeHtml(value: String): String {
        var decoded = value
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#x27;", "'")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&nbsp;", " ")
        decoded = Regex("&#x([0-9a-fA-F]+);").replace(decoded) { match ->
            match.groupValues[1].toIntOrNull(16)?.let(::codePointString) ?: match.value
        }
        return Regex("&#([0-9]+);").replace(decoded) { match ->
            match.groupValues[1].toIntOrNull()?.let(::codePointString) ?: match.value
        }
    }

    private fun codePointString(codePoint: Int): String =
        runCatching { String(Character.toChars(codePoint)) }.getOrDefault("")

    private fun JsonObject.string(key: String): String =
        this[key]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
}

internal class InvalidWebSearchDeviceIdentityException :
    IllegalArgumentException("Web search device identity is unavailable")
