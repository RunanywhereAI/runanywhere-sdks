package com.runanywhere.runanywhereai.ui

import org.junit.Assert.assertTrue
import org.junit.Test

class HybridBetaCopyTest {
    @Test
    fun allHybridConsumerCopyUsesBetaLabel() {
        val messages = listOf(
            HybridBetaCopy.LABEL,
            HybridBetaCopy.MODE_EXPLANATION,
            HybridBetaCopy.CLOUD_PROVIDER_REQUIRED,
            HybridBetaCopy.CLOUD_PROVIDER_PICKER_EMPTY,
            HybridBetaCopy.TRANSCRIPTION_FAILED,
            HybridBetaCopy.CLOUD_PROVIDERS_EXPLANATION,
            HybridBetaCopy.TRANSCRIPTION_ENTRY_DESCRIPTION,
            HybridBetaCopy.CLOUD_PROVIDERS_ENTRY_DESCRIPTION,
        )

        messages.forEach { message ->
            assertTrue("Missing Beta marker: $message", HybridBetaCopy.LABEL in message)
        }
    }
}
