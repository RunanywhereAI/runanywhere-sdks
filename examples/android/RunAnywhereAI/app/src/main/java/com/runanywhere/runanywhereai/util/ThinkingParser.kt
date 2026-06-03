package com.runanywhere.runanywhereai.util

object ThinkingParser {
    private const val OPEN = "<think>"
    private const val CLOSE = "</think>"

    data class Parsed(val text: String, val thinking: String?)

    fun parse(raw: String): Parsed {
        val open = raw.indexOf(OPEN)
        if (open < 0) return Parsed(raw.trim(), null)

        val before = raw.substring(0, open).trim()
        val close = raw.indexOf(CLOSE, open + OPEN.length)
        if (close < 0) {
            val thinking = raw.substring(open + OPEN.length).trim()
            return Parsed(before, thinking.ifEmpty { null })
        }

        val thinking = raw.substring(open + OPEN.length, close).trim()
        val after = raw.substring(close + CLOSE.length).trim()
        val text = listOf(before, after).filter { it.isNotEmpty() }.joinToString("\n\n")
        return Parsed(text, thinking.ifEmpty { null })
    }
}
