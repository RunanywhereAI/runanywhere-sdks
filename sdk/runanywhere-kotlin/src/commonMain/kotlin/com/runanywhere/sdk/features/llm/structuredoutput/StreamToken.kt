package com.runanywhere.sdk.features.llm.structuredoutput

import com.runanywhere.sdk.models.Generatable
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow

/**
 * Token emitted during streaming
 * Matches iOS StreamToken
 */
data class StreamToken(
    /** The token text */
    val text: String,
    /** Timestamp when the token was received (epoch millis) */
    val timestamp: Long,
    /** Index of this token in the stream */
    val tokenIndex: Int,
) {
    companion object {
        /**
         * Create a StreamToken with the current timestamp
         */
        fun create(
            text: String,
            tokenIndex: Int,
        ): StreamToken =
            StreamToken(
                text = text,
                timestamp = currentTimeMillis(),
                tokenIndex = tokenIndex,
            )
    }
}

/**
 * Result containing both the token stream and final parsed result
 * Matches iOS StructuredOutputStreamResult
 */
data class StructuredOutputStreamResult<T : Generatable>(
    /** Flow of tokens as they're generated */
    val tokenStream: Flow<StreamToken>,
    /** Deferred final parsed result (available after stream completes) */
    val result: Deferred<T>,
)

/**
 * Get current time in milliseconds
 */
internal expect fun currentTimeMillis(): Long
