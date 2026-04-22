/*
 * parity_test.kt — GAP 09 Phase 20 streaming parity test (Kotlin/JVM).
 * See tests/streaming/README.md.
 */

package com.runanywhere.sdk.tests.streaming

import com.runanywhere.sdk.adapters.VoiceAgentStreamAdapter
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Disabled
import org.junit.jupiter.api.Test

class StreamingParityTests {

    @Test
    @Disabled("GAP 09 ship: parity test scaffold; golden events land in Wave D.")
    fun voiceAgent_streamsExpectedEvents() = runBlocking {
        // val handle = RunAnywhere.voiceAgent.create(...)
        // val collected = VoiceAgentStreamAdapter(handle).stream()
        //     .take(20).toList()
        // assertEquals(expectedGoldenSequence(), collected.map(::summary))
    }

    @Test
    @Disabled("GAP 09 ship: cancellation test scaffold; lands with golden events in Wave D.")
    fun cancellation_yieldsNoStaleEvents() = runBlocking {
        // verify after job.cancel() no events arrive within 100ms.
    }
}
