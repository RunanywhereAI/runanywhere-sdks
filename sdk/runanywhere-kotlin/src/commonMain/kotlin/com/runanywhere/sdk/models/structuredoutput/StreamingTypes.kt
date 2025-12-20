package com.runanywhere.sdk.models.structuredoutput

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.Instant

/**
 * Token emitted during streaming
 * Mirrors iOS StreamToken struct
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+StructuredOutput.swift (Lines 5-16)
 */
@OptIn(kotlin.time.ExperimentalTime::class)
data class StreamToken(
    val text: String,
    val timestamp: Instant,
    val tokenIndex: Int,
) {
    companion object {
        @Suppress("DEPRECATION")
        fun create(
            text: String,
            tokenIndex: Int,
        ): StreamToken =
            StreamToken(
                text = text,
                timestamp = Instant.fromEpochMilliseconds(System.currentTimeMillis()),
                tokenIndex = tokenIndex,
            )
    }
}

/**
 * Result containing both the token stream and final parsed result
 * Mirrors iOS StructuredOutputStreamResult
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+StructuredOutput.swift (Lines 18-25)
 */
data class StructuredOutputStreamResult<T>(
    /**
     * Stream of tokens as they're generated
     */
    val tokenStream: Flow<StreamToken>,
    /**
     * Final parsed result (available after stream completes)
     */
    val result: Deferred<T>,
)

/**
 * Accumulates tokens during streaming for later parsing
 * Mirrors iOS StreamAccumulator actor
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+StructuredOutput.swift (Lines 30-61)
 */
class StreamAccumulator {
    private val mutex = Mutex()
    private val textBuilder = StringBuilder()
    private var isComplete = false
    private val completionDeferred = CompletableDeferred<Unit>()

    suspend fun append(token: String) {
        mutex.withLock {
            textBuilder.append(token)
        }
    }

    suspend fun getFullText(): String =
        mutex.withLock {
            textBuilder.toString()
        }

    suspend fun markComplete() {
        mutex.withLock {
            if (!isComplete) {
                isComplete = true
                completionDeferred.complete(Unit)
            }
        }
    }

    suspend fun waitForCompletion() {
        completionDeferred.await()
    }
}
