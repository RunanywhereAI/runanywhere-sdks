package com.runanywhere.runanywhereai

import com.runanywhere.runanywhereai.tools.WebSearchTool
import com.runanywhere.runanywhereai.tools.InvalidWebSearchDeviceIdentityException
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.extensions.LLM.RAToolValue
import com.runanywhere.sdk.public.extensions.LLM.array
import com.runanywhere.sdk.public.extensions.LLM.string
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import okio.Buffer

class WebSearchToolTest {
    @Test
    fun `registered web tool fails closed before consent without network access`() = runBlocking {
        val result = WebSearchTool.execute(
            mapOf("query" to RAToolValue.string("private query")),
        )

        assertEquals("Web search requires affirmative permission", result.getValue("error").string)
    }

    @Test
    fun `lite results parse titles snippets and safe source URLs`() {
        val html = """
            <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fcurrent%3Fa%3D1&amp;rut=x" class="result-link">Current &amp; useful</a>
            <td class="result-snippet">A <b>fresh</b> result.</td>
        """.trimIndent()

        val result = WebSearchTool.parseLiteResults(html).single()

        assertEquals("Current & useful", result.title)
        assertEquals("A fresh result.", result.snippet)
        assertEquals("https://example.com/current?a=1", result.url)
    }

    @Test
    fun `unsafe result schemes are rejected`() {
        val html = """<a href="javascript:alert(1)" class="result-link">Bad</a>"""
        assertTrue(WebSearchTool.parseLiteResults(html).isEmpty())
    }

    @Test
    fun `instant answer fallback returns source and related results`() {
        val payload = """{
          "Heading":"Hexagon",
          "AbstractText":"A current summary.",
          "AbstractURL":"https://example.com/hexagon",
          "RelatedTopics":[{"Text":"V81 - Details", "FirstURL":"https://example.com/v81"}]
        }"""

        val result = WebSearchTool.parseInstantAnswer("hexagon v81", payload)

        assertEquals("A current summary.", result.getValue("summary").string)
        assertEquals("https://example.com/hexagon", result.getValue("source_url").string)
        assertEquals(1, result.getValue("related_results").array?.size)
    }

    @Test
    fun `instant answer rejects unsafe abstract URLs and uses fixed search fallback`() {
        listOf(
            "javascript:alert(1)",
            "https:///missing-host",
            "https://user:secret@example.com/private",
            "https://example.com/unsafe\\u0000path",
        ).forEach { abstractUrl ->
            val payload = """{
              "Heading":"Result",
              "AbstractText":"A safe summary.",
              "AbstractURL":"$abstractUrl"
            }"""

            val result = WebSearchTool.parseInstantAnswer("private query", payload)

            assertEquals(
                "https://duckduckgo.com/?q=private%20query",
                result.getValue("source_url").string,
            )
        }
    }

    @Test
    fun `query is encoded into fixed HTTPS search origin`() {
        val url = WebSearchTool.buildLiteSearchUrl("current NPU & Android")
        assertTrue(url.startsWith("https://lite.duckduckgo.com/lite/?"))
        assertTrue(url.contains("q=current%20NPU%20%26%20Android"))
    }

    @Test
    fun `instant answer is attempted when lite search fails`() = runBlocking {
        val requestedUrls = mutableListOf<String>()
        val result = WebSearchTool.search(
            query = "hexagon v81",
            backendUrl = "",
            publicFetcher = { url ->
                requestedUrls += url
                if (url.startsWith("https://lite.duckduckgo.com/")) {
                    error("simulated lite outage")
                }
                """{
                  "Heading":"Hexagon V81",
                  "AbstractText":"Fallback response.",
                  "AbstractURL":"https://example.com/v81"
                }"""
            },
        )

        assertEquals(2, requestedUrls.size)
        assertTrue(requestedUrls[1].startsWith("https://api.duckduckgo.com/"))
        assertEquals("Fallback response.", result.getValue("summary").string)
    }

    @Test
    fun `lite parser drift emits only a fixed diagnostic before safe fallback`() = runBlocking {
        val diagnostics = mutableListOf<String>()
        val previousEnabled = RACLog.enabled
        val previousReporter = RACLog.errorReporter
        RACLog.enabled = false
        RACLog.errorReporter = { _, _, message, _ -> diagnostics += message }
        try {
            suspend fun searchWithChangedMarkup() =
                WebSearchTool.search(
                    query = "private query must not be logged",
                    backendUrl = "",
                    publicFetcher = { url ->
                        if (url.startsWith("https://lite.duckduckgo.com/")) {
                            "<html><div class='changed-result'>private response</div></html>"
                        } else {
                            """{"Heading":"Fallback","Answer":"Safe answer"}"""
                        }
                    },
                )
            val results = listOf(searchWithChangedMarkup(), searchWithChangedMarkup())

            assertTrue(results.all { it.getValue("summary").string == "Safe answer" })
            assertEquals(listOf("web_search_lite_parser_no_results"), diagnostics)
            assertTrue(diagnostics.none { it.contains("private") })
        } finally {
            RACLog.enabled = previousEnabled
            RACLog.errorReporter = previousReporter
        }
    }

    @Test
    fun `invalid proxy device identity emits a fixed redacted diagnostic`() = runBlocking {
        val diagnostics = mutableListOf<String>()
        val previousEnabled = RACLog.enabled
        val previousReporter = RACLog.errorReporter
        RACLog.enabled = false
        RACLog.errorReporter = { _, _, message, _ -> diagnostics += message }
        try {
            val result = WebSearchTool.search(
                query = "private query must not be logged",
                backendUrl = "https://search.runanywhere.example/v1/search",
                backendFetcher = { _, _ -> throw InvalidWebSearchDeviceIdentityException() },
            )

            assertTrue(result.containsKey("error"))
            assertEquals(listOf("web_search_invalid_device_identity"), diagnostics)
            assertTrue(diagnostics.none { it.contains("private") || it.contains("device-id") })
        } finally {
            RACLog.enabled = previousEnabled
            RACLog.errorReporter = previousReporter
        }
    }

    @Test
    fun `configured backend results are parsed and public fallback is not contacted`() = runBlocking {
        var publicRequests = 0
        val result = WebSearchTool.search(
            query = "latest android requirements",
            backendUrl = "https://search.runanywhere.example/v1/search",
            backendFetcher = { endpoint, query ->
                assertEquals("https://search.runanywhere.example/v1/search", endpoint)
                assertEquals("latest android requirements", query)
                """{"results":[
                  {"title":"Android requirements","url":"https://developer.android.com/example","snippet":"Current guidance."},
                  {"title":"Unsafe","url":"javascript:alert(1)","snippet":"Drop me."}
                ]}"""
            },
            publicFetcher = {
                publicRequests++
                error("must not use public fallback")
            },
        )

        assertEquals(0, publicRequests)
        assertEquals("1", result.getValue("result_count").string)
        assertEquals("https://developer.android.com/example", result.getValue("source_url").string)
    }

    @Test
    fun `queries outside the proxy contract fail before network access`() = runBlocking {
        listOf(
            "x".repeat(401),
            List(51) { "word" }.joinToString(" "),
            "private\nquery",
        ).forEach { invalidQuery ->
            var requests = 0
            val result = WebSearchTool.search(
                query = invalidQuery,
                backendUrl = "https://search.runanywhere.example/api/v1/web-search",
                backendFetcher = { _, _ ->
                    requests++
                    error("must not contact backend")
                },
            )
            assertTrue(result.containsKey("error"))
            assertEquals(0, requests)
        }
    }

    @Test
    fun `backend endpoint must be credential-free HTTPS`() {
        assertEquals(
            "https://search.runanywhere.example/v1/search",
            WebSearchTool.parseWebSearchEndpoint("https://search.runanywhere.example/v1/search"),
        )
        listOf(
            "http://search.runanywhere.example/v1/search",
            "https://user:secret@search.runanywhere.example/v1/search",
            "not a URL",
        ).forEach { endpoint ->
            assertTrue(runCatching { WebSearchTool.parseWebSearchEndpoint(endpoint) }.isFailure)
        }
    }

    @Test
    fun `backend request uses bearer auth and persistent device identity only`() {
        val request = WebSearchTool.buildBackendRequest(
            endpoint = "https://search.runanywhere.example/api/v1/web-search",
            query = "Qualcomm Hexagon v81",
            apiKey = "test-api-key",
            deviceId = "123e4567-e89b-12d3-a456-426614174000",
        )

        assertEquals("Bearer test-api-key", request.header("Authorization"))
        assertEquals(
            "123e4567-e89b-12d3-a456-426614174000",
            request.header("X-RunAnywhere-Device-ID"),
        )
        assertNull(request.header("apikey"))
        assertEquals("POST", request.method)
        assertEquals("/api/v1/web-search", request.url.encodedPath)
        assertEquals("application/json; charset=utf-8", request.body?.contentType().toString())
        val body = Buffer().also { request.body?.writeTo(it) }.readUtf8()
        assertEquals("""{"query":"Qualcomm Hexagon v81","count":5}""", body)
    }

    @Test
    fun `backend request fails closed without auth or valid device identity`() {
        val endpoint = "https://search.runanywhere.example/api/v1/web-search"
        assertTrue(
            runCatching {
                WebSearchTool.buildBackendRequest(
                    endpoint,
                    "query",
                    "",
                    "123e4567-e89b-12d3-a456-426614174000",
                )
            }.isFailure,
        )
        assertTrue(
            runCatching {
                WebSearchTool.buildBackendRequest(
                    endpoint,
                    "query",
                    "test-api-key",
                    "not-a-uuid",
                )
            }.isFailure,
        )
    }

    @Test
    fun `device identity validation is canonical and testable without a network request`() {
        assertEquals(
            "123e4567-e89b-12d3-a456-426614174000",
            WebSearchTool.validateDeviceId("123e4567-e89b-12d3-a456-426614174000"),
        )
        assertTrue(runCatching { WebSearchTool.validateDeviceId("not-a-uuid") }.isFailure)
    }
}
