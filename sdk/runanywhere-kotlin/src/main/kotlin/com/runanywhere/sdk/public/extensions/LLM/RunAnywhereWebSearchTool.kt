/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDK-facing web search tool helper for tool-calling clients.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../RunAnywhere+WebSearchTool.swift 1:1:
 * a built-in `search_web` tool backed by DuckDuckGo (lite HTML results with an
 * Instant Answer API fallback), registered through the existing
 * `registerTool` / `ToolExecutor` surface. OkHttp is the platform transport
 * (URLSession on Swift).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ToolDefinition
import ai.runanywhere.proto.v1.ToolParameter
import ai.runanywhere.proto.v1.ToolParameterType
import ai.runanywhere.proto.v1.ToolValue
import ai.runanywhere.proto.v1.ToolValueArray
import ai.runanywhere.proto.v1.ToolValueObject
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLDecoder
import java.util.concurrent.TimeUnit

/** Definition for the built-in web search tool helper. */
val RunAnywhere.webSearchToolDefinition: ToolDefinition
    get() = WebSearchTool.definition

/** Register the built-in web search tool helper. */
suspend fun RunAnywhere.registerWebSearchTool() {
    registerTool(WebSearchTool.definition, WebSearchTool.executor)
}

private object WebSearchTool {
    private object Tool {
        const val NAME = "search_web"
        const val DESCRIPTION =
            "Searches the web for current information using DuckDuckGo Instant Answer API"
        const val CATEGORY = "Web"
    }

    private object Parameter {
        const val QUERY = "query"
        const val QUERY_DESCRIPTION =
            "Search query (e.g., 'latest Kotlin coroutine updates')"
    }

    private object PayloadKey {
        const val ERROR = "error"
        const val QUERY = "query"
        const val HEADING = "heading"
        const val SUMMARY = "summary"
        const val SOURCE_URL = "source_url"
        const val SEARCH_URL = "search_url"
        const val RELATED_RESULTS = "related_results"
        const val TITLE = "title"
        const val TEXT = "text"
        const val URL = "url"
    }

    private const val USER_AGENT_HEADER = "User-Agent"
    private const val USER_AGENT = "Mozilla/5.0"
    private const val TIMEOUT_SECONDS = 15L
    private const val MAX_RESULTS = 5
    private const val SNIPPET_TAIL_CHARS = 1_500

    private val client =
        OkHttpClient.Builder()
            .callTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()

    private val json = Json { ignoreUnknownKeys = true }

    val definition =
        ToolDefinition(
            name = Tool.NAME,
            description = Tool.DESCRIPTION,
            parameters =
                listOf(
                    ToolParameter(
                        name = Parameter.QUERY,
                        type = ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
                        description = Parameter.QUERY_DESCRIPTION,
                    ),
                ),
            category = Tool.CATEGORY,
        )

    val executor: ToolExecutor = { args ->
        search(args[Parameter.QUERY]?.string_value ?: "")
    }

    private suspend fun search(rawQuery: String): Map<String, ToolValue> {
        val query = rawQuery.trim()
        if (query.isEmpty()) {
            return mapOf(PayloadKey.ERROR to str("Missing search query"))
        }
        val liteUrl =
            makeLiteSearchURL(query)
                ?: return mapOf(PayloadKey.ERROR to str("Invalid search query"))

        val html = httpGet(liteUrl)
        val results = parseLiteResults(html).take(MAX_RESULTS)
        val first = results.firstOrNull()
        if (first != null) {
            return resultPayload(query, first, results.drop(1))
        }
        return instantAnswerFallback(query)
    }

    private suspend fun instantAnswerFallback(query: String): Map<String, ToolValue> {
        val url =
            makeInstantAnswerURL(query)
                ?: return mapOf(PayloadKey.ERROR to str("Invalid search query"))

        val body = httpGet(url)
        val root =
            runCatching { json.parseToJsonElement(body) as? JsonObject }.getOrNull()
                ?: return mapOf(PayloadKey.ERROR to str("Could not parse search response"))

        val abstractText = root.stringField("AbstractText")
        val answer = root.stringField("Answer")
        val heading = root.stringField("Heading")
        val abstractURL = root.stringField("AbstractURL")
        val related = collectRelatedTopics(root["RelatedTopics"]).take(MAX_RESULTS)

        val result = linkedMapOf<String, ToolValue>(PayloadKey.QUERY to str(query))

        if (heading.isNotEmpty()) {
            result[PayloadKey.HEADING] = str(heading)
        }

        result[PayloadKey.SUMMARY] =
            str(
                when {
                    abstractText.isNotEmpty() -> abstractText
                    answer.isNotEmpty() -> answer
                    related.isNotEmpty() -> related.first().text
                    else ->
                        "No direct answer was available. Open the search results for current sources."
                },
            )

        if (abstractURL.isNotEmpty()) {
            result[PayloadKey.SOURCE_URL] = str(abstractURL)
        } else {
            makeSearchResultsURL(query)?.toString()?.let { searchURL ->
                result[PayloadKey.SOURCE_URL] = str(searchURL)
                result[PayloadKey.SEARCH_URL] = str(searchURL)
            }
        }

        if (related.isNotEmpty()) {
            result[PayloadKey.RELATED_RESULTS] =
                arr(
                    related.map { topic ->
                        obj(
                            mapOf(
                                PayloadKey.TITLE to str(topic.title),
                                PayloadKey.TEXT to str(topic.text),
                                PayloadKey.URL to str(topic.url),
                            ),
                        )
                    },
                )
        }

        return result
    }

    private suspend fun httpGet(url: HttpUrl): String =
        withContext(Dispatchers.IO) {
            val request =
                Request.Builder()
                    .url(url)
                    .header(USER_AGENT_HEADER, USER_AGENT)
                    .build()
            runCatching {
                client.newCall(request).execute().use { response ->
                    response.body.string()
                }
            }.getOrDefault("")
        }

    private fun resultPayload(
        query: String,
        primary: SearchResult,
        related: List<SearchResult>,
    ): Map<String, ToolValue> {
        val result =
            linkedMapOf(
                PayloadKey.QUERY to str(query),
                PayloadKey.HEADING to str(primary.title),
                PayloadKey.SUMMARY to str(primary.snippet),
                PayloadKey.SOURCE_URL to str(primary.url),
            )
        if (related.isNotEmpty()) {
            result[PayloadKey.RELATED_RESULTS] =
                arr(
                    related.map { item ->
                        obj(
                            mapOf(
                                PayloadKey.TITLE to str(item.title),
                                PayloadKey.TEXT to str(item.snippet),
                                PayloadKey.URL to str(item.url),
                            ),
                        )
                    },
                )
        }
        return result
    }

    private fun parseLiteResults(html: String): List<SearchResult> =
        resultLinkRegex.findAll(html).mapNotNull { match ->
            val href = match.groupValues.getOrNull(1)?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val rawTitle = match.groupValues.getOrNull(2) ?: return@mapNotNull null
            val resolvedURL = redirectURL(decodeHTML(href))
            val cleanTitle = cleanHTML(rawTitle)
            if (cleanTitle.isEmpty() || resolvedURL.isEmpty()) return@mapNotNull null
            val snippet = snippetAfter(match.range.last + 1, html) ?: cleanTitle
            SearchResult(title = cleanTitle, url = resolvedURL, snippet = snippet)
        }.toList()

    private fun snippetAfter(startIndex: Int, html: String): String? {
        if (startIndex >= html.length) return null
        val tail = html.substring(startIndex).take(SNIPPET_TAIL_CHARS)
        val match = snippetRegex.find(tail) ?: return null
        val raw = match.groupValues.getOrNull(1) ?: return null
        return cleanHTML(raw).ifEmpty { null }
    }

    private fun redirectURL(href: String): String {
        val marker = "uddg="
        val index = href.indexOf(marker)
        if (index < 0) {
            return if (href.startsWith("//")) "https:$href" else href
        }
        val encoded = href.substring(index + marker.length).substringBefore("&")
        return runCatching { URLDecoder.decode(encoded, "UTF-8") }.getOrDefault(encoded)
    }

    private fun collectRelatedTopics(element: JsonElement?): List<RelatedTopic> {
        val array = element as? JsonArray ?: return emptyList()
        return array.flatMap { item ->
            val topic = item as? JsonObject ?: return@flatMap emptyList()
            val nested = topic["Topics"]
            if (nested is JsonArray && nested.isNotEmpty()) {
                collectRelatedTopics(nested)
            } else {
                val text = topic.stringField("Text")
                if (text.isEmpty()) {
                    emptyList()
                } else {
                    listOf(
                        RelatedTopic(
                            title = text.substringBefore(" - "),
                            text = text,
                            url = topic.stringField("FirstURL"),
                        ),
                    )
                }
            }
        }
    }

    private fun cleanHTML(value: String): String =
        decodeHTML(value.replace(htmlTagRegex, " "))
            .replace(whitespaceRegex, " ")
            .trim()

    private fun decodeHTML(value: String): String =
        value
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#x27;", "'")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&nbsp;", " ")

    private fun makeLiteSearchURL(query: String): HttpUrl? =
        runCatching {
            HttpUrl.Builder()
                .scheme("https")
                .host("lite.duckduckgo.com")
                .addPathSegment("lite")
                .addPathSegment("")
                .addQueryParameter(Parameter.QUERY, query)
                .build()
        }.getOrNull()

    private fun makeInstantAnswerURL(query: String): HttpUrl? =
        runCatching {
            HttpUrl.Builder()
                .scheme("https")
                .host("api.duckduckgo.com")
                .addQueryParameter("q", query)
                .addQueryParameter("format", "json")
                .addQueryParameter("no_redirect", "1")
                .addQueryParameter("no_html", "1")
                .addQueryParameter("skip_disambig", "1")
                .build()
        }.getOrNull()

    private fun makeSearchResultsURL(query: String): HttpUrl? =
        runCatching {
            HttpUrl.Builder()
                .scheme("https")
                .host("duckduckgo.com")
                .addPathSegment("")
                .addQueryParameter(Parameter.QUERY, query)
                .build()
        }.getOrNull()

    private fun str(value: String): ToolValue = ToolValue(string_value = value)

    private fun arr(values: List<ToolValue>): ToolValue =
        ToolValue(array_value = ToolValueArray(values = values))

    private fun obj(fields: Map<String, ToolValue>): ToolValue =
        ToolValue(object_value = ToolValueObject(fields = fields))

    private fun JsonObject.stringField(key: String): String =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim().orEmpty()

    private val resultLinkRegex =
        Regex(
            """<a(?=[^>]*class=['"][^'"]*result-link[^'"]*['"])""" +
                """(?=[^>]*href=['"]([^'"]+)['"])[^>]*>(.*?)</a>""",
        )

    private val snippetRegex =
        Regex("""<td[^>]*class=['"][^'"]*result-snippet[^'"]*['"][^>]*>\s*([\s\S]*?)\s*</td>""")

    private val htmlTagRegex = Regex("<[^>]+>")
    private val whitespaceRegex = Regex("\\s+")

    private data class SearchResult(
        val title: String,
        val url: String,
        val snippet: String,
    )

    private data class RelatedTopic(
        val title: String,
        val text: String,
        val url: String,
    )
}
