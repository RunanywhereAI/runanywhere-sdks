package com.runanywhere.sdk.features.llm.structuredoutput

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Accumulates tokens during streaming for later parsing
 * Matches iOS StreamAccumulator actor
 *
 * Thread-safe implementation using Mutex (equivalent to Swift actor)
 */
class StreamAccumulator {
    private val mutex = Mutex()
    private val textBuilder = StringBuilder()
    private var isComplete = false
    private val completionSignal = CompletableDeferred<Unit>()

    /**
     * Append a token to the accumulated text
     */
    suspend fun append(token: String) {
        mutex.withLock {
            textBuilder.append(token)
        }
    }

    /**
     * Get the full accumulated text
     */
    suspend fun getFullText(): String =
        mutex.withLock {
            textBuilder.toString()
        }

    /**
     * Get the full text without suspension (for read-only access after completion)
     */
    val fullText: String
        get() = textBuilder.toString()

    /**
     * Mark the accumulation as complete
     */
    suspend fun markComplete() {
        mutex.withLock {
            if (!isComplete) {
                isComplete = true
                completionSignal.complete(Unit)
            }
        }
    }

    /**
     * Wait for accumulation to complete
     */
    suspend fun waitForCompletion() {
        if (isComplete) return
        completionSignal.await()
    }

    /**
     * Check if accumulation is complete
     */
    suspend fun isCompleted(): Boolean =
        mutex.withLock {
            isComplete
        }

    /**
     * Get the current token count (approximate, based on spaces)
     */
    suspend fun getTokenCount(): Int =
        mutex.withLock {
            textBuilder.toString().split("\\s+".toRegex()).size
        }

    /**
     * Clear accumulated text and reset state
     */
    suspend fun reset() {
        mutex.withLock {
            textBuilder.clear()
            isComplete = false
        }
    }
}
