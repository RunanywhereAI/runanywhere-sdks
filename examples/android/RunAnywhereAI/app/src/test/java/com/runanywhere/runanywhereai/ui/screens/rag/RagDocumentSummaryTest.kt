package com.runanywhere.runanywhereai.ui.screens.rag

import org.junit.Assert.assertEquals
import org.junit.Test

class RagDocumentSummaryTest {
    @Test
    fun `summary pluralizes document and chunk counts independently`() {
        assertEquals("1 document · 1 chunk", formatDocumentChunkSummary(1, 1))
        assertEquals("1 document · 2 chunks", formatDocumentChunkSummary(1, 2))
        assertEquals("2 documents · 1 chunk", formatDocumentChunkSummary(2, 1))
        assertEquals("0 documents · 0 chunks", formatDocumentChunkSummary(0, 0))
    }
}
