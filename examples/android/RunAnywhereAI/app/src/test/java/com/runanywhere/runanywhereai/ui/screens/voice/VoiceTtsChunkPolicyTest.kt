package com.runanywhere.runanywhereai.ui.screens.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceTtsChunkPolicyTest {

    // --- drainSentences ------------------------------------------------------

    @Test
    fun `drainSentences returns complete sentences and keeps the trailing partial in the buffer`() {
        val buf = StringBuilder("Hello world. How are you? And th")
        val out = VoiceTtsChunkPolicy.drainSentences(buf, flush = false)
        assertEquals(listOf("Hello world.", "How are you?"), out)
        assertEquals("And th", buf.toString()) // partial held for the next token
    }

    @Test
    fun `drainSentences with flush emits the trailing partial and drains the buffer`() {
        val buf = StringBuilder("One more thing")
        val out = VoiceTtsChunkPolicy.drainSentences(buf, flush = true)
        assertEquals(listOf("One more thing"), out)
        assertEquals("", buf.toString())
    }

    @Test
    fun `drainSentences does not split on a decimal point`() {
        val buf = StringBuilder("Pi is 3.14 exactly.")
        val out = VoiceTtsChunkPolicy.drainSentences(buf, flush = true)
        assertEquals(listOf("Pi is 3.14 exactly."), out) // no split on "3.14"
    }

    @Test
    fun `drainSentences strips a complete think block and never speaks it`() {
        val buf = StringBuilder("Say <think>secret reasoning</think>the answer. ")
        val out = VoiceTtsChunkPolicy.drainSentences(buf, flush = false)
        assertEquals(listOf("Say the answer."), out)
    }

    @Test
    fun `drainSentences holds an unclosed think block instead of speaking it`() {
        val buf = StringBuilder("Answer here. <think>still reasoning")
        val out = VoiceTtsChunkPolicy.drainSentences(buf, flush = false)
        assertEquals(listOf("Answer here."), out)
        assertEquals("<think>still reasoning", buf.toString()) // held, not read aloud
    }

    // --- sanitizeForTts ------------------------------------------------------

    @Test
    fun `sanitizeForTts strips markdown and collapses whitespace`() {
        assertEquals("bold italic code", VoiceTtsChunkPolicy.sanitizeForTts("**bold** _italic_ `code`"))
        assertEquals("a b c", VoiceTtsChunkPolicy.sanitizeForTts("a  b   c"))
        assertEquals("padded", VoiceTtsChunkPolicy.sanitizeForTts("  padded  "))
    }

    // --- capForTts -----------------------------------------------------------

    @Test
    fun `capForTts leaves text under the cap untouched`() {
        val text = "a short sentence well under the cap"
        assertEquals(listOf(text), VoiceTtsChunkPolicy.capForTts(text))
    }

    @Test
    fun `capForTts splits long text on word boundaries with every chunk under the cap`() {
        val text = (1..60).joinToString(" ") { "word$it" } // ~400 chars, many words
        val chunks = VoiceTtsChunkPolicy.capForTts(text)
        assertTrue("expected multiple chunks", chunks.size > 1)
        assertTrue("every chunk must respect the cap", chunks.all { it.length <= VoiceTtsChunkPolicy.MAX_TTS_CHARS })
        assertEquals(text, chunks.joinToString(" ")) // no words lost or reordered
    }

    @Test
    fun `capForTts force-splits a single word longer than the cap`() {
        val giant = "x".repeat(400) // one run-on token with no spaces — the rc=-130 edge case
        val chunks = VoiceTtsChunkPolicy.capForTts(giant)
        assertTrue("every chunk must respect the cap", chunks.all { it.length <= VoiceTtsChunkPolicy.MAX_TTS_CHARS })
        assertEquals(giant, chunks.joinToString("")) // reassembles exactly
    }
}
