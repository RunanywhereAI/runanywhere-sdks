package com.runanywhere.sdk.features.llm

import kotlinx.serialization.Serializable

/**
 * Pattern for extracting thinking/reasoning content from model output
 * Matches iOS ThinkingTagPattern
 *
 * Used with reasoning models like DeepSeek-R1 and Hermes that emit
 * structured reasoning within special tags.
 */
@Serializable
data class ThinkingTagPattern(
    /** Opening tag for thinking content (e.g., "<think>") */
    val openingTag: String,
    /** Closing tag for thinking content (e.g., "</think>") */
    val closingTag: String,
) {
    /**
     * Extract thinking content and response from model output
     *
     * @param text The full model output
     * @return ExtractionResult containing separated thinking and response content
     */
    fun extract(text: String): ExtractionResult {
        val openIndex = text.indexOf(openingTag)
        val closeIndex = text.indexOf(closingTag)

        // No thinking tags found
        if (openIndex == -1 || closeIndex == -1 || closeIndex <= openIndex) {
            return ExtractionResult(
                thinkingContent = null,
                responseContent = text.trim(),
                thinkingTokens = 0,
                responseTokens = estimateTokens(text),
            )
        }

        // Extract thinking content (between tags)
        val thinkingStart = openIndex + openingTag.length
        val thinkingContent = text.substring(thinkingStart, closeIndex).trim()

        // Extract response (everything after closing tag)
        val responseStart = closeIndex + closingTag.length
        val responseContent = text.substring(responseStart).trim()

        // Also check for content before the thinking tags
        val preThinkingContent = text.substring(0, openIndex).trim()
        val fullResponse =
            if (preThinkingContent.isNotEmpty()) {
                "$preThinkingContent\n$responseContent"
            } else {
                responseContent
            }

        return ExtractionResult(
            thinkingContent = thinkingContent.ifEmpty { null },
            responseContent = fullResponse,
            thinkingTokens = estimateTokens(thinkingContent),
            responseTokens = estimateTokens(fullResponse),
        )
    }

    /**
     * Check if the text contains thinking tags
     */
    fun containsThinkingTags(text: String): Boolean = text.contains(openingTag) && text.contains(closingTag)

    /**
     * Estimate token count (rough approximation: ~4 chars per token)
     */
    private fun estimateTokens(text: String): Int = maxOf(1, text.length / 4)

    /**
     * Result of extracting thinking content from model output
     */
    data class ExtractionResult(
        /** The extracted thinking/reasoning content, or null if none found */
        val thinkingContent: String?,
        /** The main response content with thinking tags removed */
        val responseContent: String,
        /** Estimated tokens used for thinking */
        val thinkingTokens: Int,
        /** Estimated tokens in the response */
        val responseTokens: Int,
    )

    companion object {
        /**
         * Default pattern used by models like DeepSeek-R1 and Hermes
         */
        val DEFAULT =
            ThinkingTagPattern(
                openingTag = "<think>",
                closingTag = "</think>",
            )

        /**
         * Alternative pattern with full "thinking" word
         */
        val THINKING =
            ThinkingTagPattern(
                openingTag = "<thinking>",
                closingTag = "</thinking>",
            )

        /**
         * Pattern for models using "reasoning" tags
         */
        val REASONING =
            ThinkingTagPattern(
                openingTag = "<reasoning>",
                closingTag = "</reasoning>",
            )

        /**
         * Pattern for models using "reflection" tags
         */
        val REFLECTION =
            ThinkingTagPattern(
                openingTag = "<reflection>",
                closingTag = "</reflection>",
            )

        /**
         * Create a custom pattern for models that use different tags
         */
        fun custom(
            opening: String,
            closing: String,
        ): ThinkingTagPattern =
            ThinkingTagPattern(
                openingTag = opening,
                closingTag = closing,
            )

        /**
         * Common patterns to try when auto-detecting
         */
        val COMMON_PATTERNS = listOf(DEFAULT, THINKING, REASONING, REFLECTION)

        /**
         * Auto-detect and extract thinking content by trying common patterns
         *
         * @param text The model output to analyze
         * @return ExtractionResult from the first matching pattern, or a result with no thinking content
         */
        fun autoExtract(text: String): ExtractionResult {
            for (pattern in COMMON_PATTERNS) {
                if (pattern.containsThinkingTags(text)) {
                    return pattern.extract(text)
                }
            }

            // No patterns matched, return text as-is
            return ExtractionResult(
                thinkingContent = null,
                responseContent = text.trim(),
                thinkingTokens = 0,
                responseTokens = maxOf(1, text.length / 4),
            )
        }
    }
}
