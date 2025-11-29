package com.runanywhere.sdk.generation

import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Service for counting tokens in text with improved accuracy.
 * Matches iOS TokenCounter.swift exactly.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Services/TokenCounter.swift
 */
object TokenCounter {

    /**
     * Count tokens with improved estimation (more accurate than simple word count).
     * This is a heuristic approach until we integrate actual tokenizers.
     *
     * @param text The text to count tokens for
     * @return Estimated number of tokens
     */
    fun estimateTokenCount(text: String): Int {
        if (text.isEmpty()) return 0

        // Improved heuristic based on GPT tokenization patterns:
        // - Average ~4 characters per token for English text
        // - Punctuation often creates separate tokens
        // - Whitespace handling
        // - Special characters

        val characterCount = text.length
        val wordCount = text.split(" ").filter { it.isNotEmpty() }.size

        // Count punctuation marks (often separate tokens)
        val punctuationChars = ".,!?;:()[]{}\"'"
        val punctuationCount = text.count { punctuationChars.contains(it) }

        // Count newlines and special whitespace (often separate tokens)
        val newlineCount = text.count { it == '\n' || it == '\r' }

        // Heuristic formula:
        // Base estimate: characters / 4 (GPT average)
        // Add extra tokens for punctuation (most become separate tokens)
        // Add tokens for newlines
        // Ensure we're at least counting words (minimum tokens)

        val baseEstimate = characterCount.toDouble() / 4.0
        val punctuationTokens = punctuationCount.toDouble() * 0.7 // Most punctuation becomes tokens
        val newlineTokens = newlineCount.toDouble()

        val estimatedTokens = ceil(baseEstimate + punctuationTokens + newlineTokens).toInt()

        // Sanity check: token count should be between word count and character count
        return max(wordCount, min(estimatedTokens, characterCount))
    }

    /**
     * Estimate tokens per second based on token count and elapsed time.
     *
     * @param tokenCount Number of tokens generated
     * @param elapsedSeconds Time elapsed in seconds
     * @return Tokens per second
     */
    fun calculateTokensPerSecond(tokenCount: Int, elapsedSeconds: Double): Double {
        if (elapsedSeconds <= 0) return 0.0
        return tokenCount.toDouble() / elapsedSeconds
    }

    /**
     * Split token count between thinking and response content.
     *
     * @param fullText The full generated text
     * @param thinkingContent Optional thinking/reasoning content
     * @param responseContent The response content
     * @return Triple of (thinkingTokens, responseTokens, totalTokens)
     */
    fun splitTokenCounts(
        fullText: String,
        thinkingContent: String?,
        responseContent: String
    ): Triple<Int?, Int, Int> {
        val responseTokens = estimateTokenCount(responseContent)

        return if (!thinkingContent.isNullOrEmpty()) {
            val thinkingTokens = estimateTokenCount(thinkingContent)
            val totalTokens = thinkingTokens + responseTokens
            Triple(thinkingTokens, responseTokens, totalTokens)
        } else {
            Triple(null, responseTokens, responseTokens)
        }
    }
}
