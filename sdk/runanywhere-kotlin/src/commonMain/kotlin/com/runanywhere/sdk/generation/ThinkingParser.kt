package com.runanywhere.sdk.generation

/**
 * Token type for streaming - indicates whether token is reasoning or response content
 */
enum class TokenType {
    /** Token is part of model's thinking/reasoning */
    THINKING,

    /** Token is part of the actual response */
    CONTENT
}

/**
 * Parser for extracting thinking/reasoning content from model output.
 *
 * Many reasoning models (DeepSeek, Hermes) wrap their chain-of-thought
 * reasoning in special tags. This parser extracts and separates
 * the thinking content from the final response.
 */
object ThinkingParser {

    /**
     * Result of parsing thinking content
     */
    data class ParseResult(
        /** Content without thinking tags */
        val content: String,
        /** Extracted thinking content, null if no thinking tags found */
        val thinkingContent: String?
    )

    /**
     * Result of parsing a streaming token
     */
    data class StreamingParseResult(
        /** Type of the token */
        val tokenType: TokenType,
        /** Cleaned token content, null if nothing to emit yet */
        val cleanToken: String?
    )

    /**
     * Parse and extract thinking content from text.
     *
     * @param text The full text to parse
     * @param pattern The tag pattern to use for extraction
     * @return ParseResult containing separated content and thinking
     */
    fun parse(text: String, pattern: ThinkingTagPattern): ParseResult {
        // Find the first occurrence of the opening tag
        val openIndex = text.indexOf(pattern.openingTag)
        if (openIndex == -1) {
            // No thinking tags found
            return ParseResult(content = text, thinkingContent = null)
        }

        // Find the corresponding closing tag
        val closeIndex = text.indexOf(
            pattern.closingTag,
            startIndex = openIndex + pattern.openingTag.length
        )
        if (closeIndex == -1) {
            // Opening tag found but no closing tag
            return ParseResult(content = text, thinkingContent = null)
        }

        // Extract thinking content
        val thinkingContent = text.substring(
            openIndex + pattern.openingTag.length,
            closeIndex
        )

        // Remove thinking section from content
        val beforeThinking = text.substring(0, openIndex)
        val afterThinking = text.substring(closeIndex + pattern.closingTag.length)
        val content = (beforeThinking + afterThinking).trim()

        return ParseResult(
            content = content,
            thinkingContent = thinkingContent.trim()
        )
    }

    /**
     * Parse streaming tokens and detect thinking sections.
     *
     * This method maintains state across token boundaries using the provided
     * mutable parameters. It handles cases where tags may be split across
     * multiple tokens.
     *
     * @param token The incoming token
     * @param pattern The tag pattern to use
     * @param buffer Mutable buffer for accumulating partial content
     * @param inThinkingSection Mutable flag tracking if we're inside thinking tags
     * @return StreamingParseResult with token type and cleaned content
     */
    fun parseStreamingToken(
        token: String,
        pattern: ThinkingTagPattern,
        buffer: StringBuilder,
        inThinkingSection: BooleanArray
    ): StreamingParseResult {
        // Add token to buffer
        buffer.append(token)
        val bufferStr = buffer.toString()

        // Check if we're entering a thinking section
        if (!inThinkingSection[0] && bufferStr.contains(pattern.openingTag)) {
            // Found opening tag
            val openIndex = bufferStr.indexOf(pattern.openingTag)

            // Extract any content before the thinking tag
            val beforeThinking = bufferStr.substring(0, openIndex)

            // Update buffer to start after opening tag
            buffer.clear()
            buffer.append(bufferStr.substring(openIndex + pattern.openingTag.length))
            inThinkingSection[0] = true

            // Return any content before thinking as regular content
            return if (beforeThinking.isNotEmpty()) {
                StreamingParseResult(TokenType.CONTENT, beforeThinking)
            } else {
                StreamingParseResult(TokenType.THINKING, null)
            }
        }

        // Check if we're exiting a thinking section
        if (inThinkingSection[0] && bufferStr.contains(pattern.closingTag)) {
            // Found closing tag
            val closeIndex = bufferStr.indexOf(pattern.closingTag)

            // Extract thinking content
            val thinkingContent = bufferStr.substring(0, closeIndex)

            // Update buffer to start after closing tag
            val afterClose = bufferStr.substring(closeIndex + pattern.closingTag.length)
            buffer.clear()
            buffer.append(afterClose)
            inThinkingSection[0] = false

            // Return the thinking content
            if (thinkingContent.isNotEmpty()) {
                return StreamingParseResult(TokenType.THINKING, thinkingContent)
            }

            // Check if there's content after the closing tag
            if (afterClose.isNotEmpty()) {
                buffer.clear()
                return StreamingParseResult(TokenType.CONTENT, afterClose)
            }

            return StreamingParseResult(TokenType.CONTENT, null)
        }

        // If we're in a thinking section, accumulate tokens
        if (inThinkingSection[0]) {
            // Don't emit anything yet, just accumulate
            return StreamingParseResult(TokenType.THINKING, null)
        }

        // Regular content token
        val content = buffer.toString()
        buffer.clear()
        return StreamingParseResult(
            TokenType.CONTENT,
            content.ifEmpty { null }
        )
    }

    /**
     * Kotlin-idiomatic version of parseStreamingToken using a data class for state.
     *
     * @param token The incoming token
     * @param pattern The tag pattern to use
     * @param state Current parsing state
     * @return Pair of updated state and parse result
     */
    fun parseStreamingTokenStateless(
        token: String,
        pattern: ThinkingTagPattern,
        state: StreamingParserState
    ): Pair<StreamingParserState, StreamingParseResult> {
        val buffer = StringBuilder(state.buffer)
        val inThinking = booleanArrayOf(state.inThinkingSection)

        val result = parseStreamingToken(token, pattern, buffer, inThinking)
        val newState = StreamingParserState(
            buffer = buffer.toString(),
            inThinkingSection = inThinking[0]
        )

        return newState to result
    }
}

/**
 * Immutable state for stateless streaming parsing
 */
data class StreamingParserState(
    val buffer: String = "",
    val inThinkingSection: Boolean = false
)
