package com.runanywhere.runanywhereai.util

import android.util.Log
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RACLogTelemetryReporterTest {
    private var originalEnabled = false
    private var originalReporter: ((Int, String, String, Throwable?) -> Unit)? = null

    @Before
    fun setUp() {
        originalEnabled = RACLog.enabled
        originalReporter = RACLog.errorReporter
        RACLog.enabled = false
        RACLog.errorReporter = null
    }

    @After
    fun tearDown() {
        RACLog.enabled = originalEnabled
        RACLog.errorReporter = originalReporter
    }

    @Test
    fun `RACLog routes warnings and errors but not debug or info`() {
        val published = mutableListOf<SDKFailureDiagnostic>()
        val reporter = reporter(published)
        RACLog.errorReporter = reporter::report
        reporter.markSDKInitialized()

        RACLog.d("debug")
        RACLog.i("info")
        RACLog.w("warning")
        RACLog.e("error")

        assertEquals(2, published.size)
        assertEquals("raclog.warning", published[0].operation)
        assertTrue(published[0].recoverable)
        assertEquals("raclog.error", published[1].operation)
        assertFalse(published[1].recoverable)
    }

    @Test
    fun `pre-initialization diagnostics drain in order without delay`() {
        val published = mutableListOf<SDKFailureDiagnostic>()
        val reporter = reporter(published)

        reporter.report(Log.WARN, "Startup", "first", null)
        reporter.report(Log.ERROR, "Startup", "second", IllegalStateException("broken"))
        assertTrue(published.isEmpty())

        reporter.markSDKInitialized()

        assertEquals(2, published.size)
        assertEquals("source=app;event=operation_failed;kind=none", published[0].message)
        assertEquals("source=app;event=operation_failed;kind=invalid_state", published[1].message)
    }

    @Test
    fun `bounded startup queue retains the newest diagnostics`() {
        val published = mutableListOf<SDKFailureDiagnostic>()
        val reporter = reporter(published, maxPendingEvents = 2)

        reporter.report(Log.WARN, "Startup", "one", null)
        reporter.report(Log.WARN, "Startup", "two", null)
        reporter.report(Log.WARN, "Startup", "three", null)
        reporter.markSDKInitialized()

        assertEquals(
            listOf(
                "source=app;event=operation_failed;kind=none",
                "source=app;event=operation_failed;kind=none",
            ),
            published.map { it.message },
        )
    }

    @Test
    fun `publisher failures never escape and later diagnostics still publish`() {
        val published = mutableListOf<SDKFailureDiagnostic>()
        var attempts = 0
        val reporter =
            RACLogTelemetryReporter(
                publisher =
                    SDKFailurePublisher { event ->
                        attempts += 1
                        if (attempts == 1) error("publisher unavailable")
                        published += event
                        true
                    },
            )
        reporter.markSDKInitialized()

        reporter.report(Log.ERROR, "Runtime", "first", null)
        reporter.report(Log.ERROR, "Runtime", "second", null)

        assertEquals(3, attempts)
        assertEquals(2, published.size)
    }

    @Test
    fun `publisher rejection is retained for the next event-driven retry`() {
        val published = mutableListOf<SDKFailureDiagnostic>()
        var attempts = 0
        val reporter =
            RACLogTelemetryReporter(
                publisher =
                    SDKFailurePublisher { event ->
                        attempts += 1
                        if (attempts == 1) return@SDKFailurePublisher false
                        published += event
                        true
                    },
            )
        reporter.markSDKInitialized()

        reporter.report(Log.WARN, "Runtime", "first", null)
        assertTrue(published.isEmpty())
        reporter.report(Log.ERROR, "Runtime", "second", null)

        assertEquals(3, attempts)
        assertEquals(2, published.size)
    }

    @Test
    fun `publisher re-entry does not recursively publish`() {
        var attempts = 0
        lateinit var reporter: RACLogTelemetryReporter
        reporter =
            RACLogTelemetryReporter(
                publisher =
                    SDKFailurePublisher {
                        attempts += 1
                        reporter.report(Log.ERROR, "Reporter", "nested", null)
                        true
                    },
            )
        reporter.markSDKInitialized()

        reporter.report(Log.ERROR, "Runtime", "outer", null)

        assertEquals(1, attempts)
    }

    @Test
    fun `remote diagnostics discard raw content paths URLs secrets and stack messages`() {
        val published = mutableListOf<SDKFailureDiagnostic>()
        val reporter = reporter(published)
        reporter.markSDKInitialized()
        val raw = "prompt=private words token=hf_secret https://example.test /data/user/0/private"

        reporter.report(
            Log.ERROR,
            "UntrustedTag-$raw",
            raw,
            IllegalStateException("provider response: $raw"),
        )

        val diagnostic = published.single().message
        assertEquals("source=app;event=operation_failed;kind=invalid_state", diagnostic)
        assertFalse(diagnostic.contains("private"))
        assertFalse(diagnostic.contains("hf_"))
        assertFalse(diagnostic.contains("http"))
        assertFalse(diagnostic.contains("/data"))
        assertTrue(diagnostic.length <= TelemetryDiagnosticPolicy.MAX_MESSAGE_CHARS)
    }

    @Test
    fun `only explicitly allowlisted structured event codes are transmitted`() {
        assertEquals(
            "source=web_search;event=web_search_invalid_device_identity;kind=none",
            TelemetryDiagnosticPolicy.format(
                "WebSearchTool",
                "web_search_invalid_device_identity",
                null,
            ),
        )
        assertEquals(
            "source=web_search;event=operation_failed;kind=none",
            TelemetryDiagnosticPolicy.format("WebSearchTool", "query=private", null),
        )
    }

    private fun reporter(
        published: MutableList<SDKFailureDiagnostic>,
        maxPendingEvents: Int = 64,
    ): RACLogTelemetryReporter =
        RACLogTelemetryReporter(
            publisher =
                SDKFailurePublisher { event ->
                    published += event
                    true
                },
            maxPendingEvents = maxPendingEvents,
        )
}
