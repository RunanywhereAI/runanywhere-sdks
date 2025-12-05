package com.runanywhere.sdk.generation

import kotlinx.serialization.Serializable

/**
 * Pattern for extracting thinking/reasoning content from model output.
 *
 * Models like DeepSeek and Hermes use special tags to denote
 * chain-of-thought reasoning that should be separated from the final response.
 */
@Serializable
data class ThinkingTagPattern(
    val openingTag: String,
    val closingTag: String
) {
    companion object {
        /**
         * Default pattern used by models like DeepSeek and Hermes
         */
        val defaultPattern = ThinkingTagPattern(
            openingTag = "<think>",
            closingTag = "</think>"
        )

        /**
         * Alternative pattern with full "thinking" word
         */
        val thinkingPattern = ThinkingTagPattern(
            openingTag = "<thinking>",
            closingTag = "</thinking>"
        )
    }
}
