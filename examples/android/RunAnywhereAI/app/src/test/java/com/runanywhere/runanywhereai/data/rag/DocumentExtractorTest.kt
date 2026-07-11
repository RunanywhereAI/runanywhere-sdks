package com.runanywhere.runanywhereai.data.rag

import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentExtractorTest {
    @Test
    fun `text at the character boundary is accepted`() {
        val text = "a".repeat(DocumentExtractor.MAX_TEXT_CHARS)
        assertEquals(text, DocumentExtractor.enforceTextLimit(text))
    }

    @Test
    fun `text beyond the character boundary is rejected`() {
        val text = "a".repeat(DocumentExtractor.MAX_TEXT_CHARS + 1)
        assertTrue(runCatching { DocumentExtractor.enforceTextLimit(text) }.isFailure)
    }

    @Test
    fun `stream beyond the byte boundary is rejected before unbounded read`() {
        val bytes = ByteArray(DocumentExtractor.MAX_SOURCE_BYTES.toInt() + 1)
        assertTrue(
            runCatching {
                DocumentExtractor.readUtf8TextWithinLimits(ByteArrayInputStream(bytes))
            }.isFailure,
        )
    }
}
