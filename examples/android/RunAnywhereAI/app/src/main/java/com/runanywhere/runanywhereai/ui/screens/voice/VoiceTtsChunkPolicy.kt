package com.runanywhere.runanywhereai.ui.screens.voice

/**
 * Pure text→speech chunking for Talk mode. Kept out of the ViewModel so it is unit-testable (mirrors
 * the *Policy pattern used across chat/rag). It turns streamed LLM text into short, clean, speakable
 * chunks: split on sentence boundaries, strip markdown, and hard-cap each
 * chunk so an over-long phoneme run never makes an NPU TTS fail — MeloTTS on v79 rejects a sequence
 * past its 512-phoneme cap with rc=-130.
 */
internal object VoiceTtsChunkPolicy {
    // ~a couple hundred chars maps under MeloTTS's 512-phoneme cap; keep each spoken chunk well under.
    const val MAX_TTS_CHARS: Int = 160

    // Cut sentences on . ! ? followed by whitespace (so "3.14" / "U.S." don't split mid-number).
    private val sentenceSplit = Regex("(?<=[.!?])\\s+")

    /**
     * Pull complete, speakable sentences out of [buf] (mutating it). With [flush] the trailing
     * partial is returned too and the buffer is drained; otherwise the trailing partial is kept
     * in [buf] for the next call.
     */
    fun drainSentences(buf: StringBuilder, flush: Boolean): List<String> {
        // Reasoning is already channel-split upstream (THINKING events are not
        // dispatched into this buffer). Only sentence-split here.
        val speakable = buf.toString()
        val parts = sentenceSplit.split(speakable)
        val complete = if (flush) parts.size else parts.size - 1
        val out = ArrayList<String>(maxOf(complete, 0))
        for (i in 0 until complete) {
            val clean = sanitizeForTts(parts[i])
            if (clean.isNotEmpty()) out.add(clean)
        }
        buf.setLength(0)
        if (!flush) buf.append(parts.lastOrNull() ?: "")
        return out
    }

    /** Strip markdown formatting and collapse whitespace so the TTS g2p front-end sees clean prose. */
    fun sanitizeForTts(text: String): String =
        text.replace(Regex("[*_`#>~|]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

    /**
     * Hard-cap [text] into [maxChars]-char chunks, splitting on word boundaries. A single word longer
     * than the cap (a URL / run-on token) is force-split so NO chunk ever exceeds the cap — otherwise
     * that one chunk could re-trigger the MeloTTS rc=-130 this whole path exists to avoid.
     */
    fun capForTts(text: String, maxChars: Int = MAX_TTS_CHARS): List<String> {
        if (text.length <= maxChars) return listOf(text)
        val out = ArrayList<String>()
        val cur = StringBuilder()
        fun flush() { if (cur.isNotEmpty()) { out.add(cur.toString()); cur.setLength(0) } }
        for (word in text.split(" ")) {
            if (word.length > maxChars) { // a single over-long token: force-split it
                flush()
                var i = 0
                while (i < word.length) {
                    val end = minOf(i + maxChars, word.length)
                    out.add(word.substring(i, end))
                    i = end
                }
                continue
            }
            if (cur.isNotEmpty() && cur.length + 1 + word.length > maxChars) flush()
            if (cur.isNotEmpty()) cur.append(' ')
            cur.append(word)
        }
        flush()
        return out
    }
}
