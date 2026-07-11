package com.runanywhere.runanywhereai.ui.screens.rag

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Test

class RagCancellationOrderingTest {
    @Test
    fun `query job is cancelled before an explicit native cancel can wait behind it`() = runBlocking {
        val queryStarted = CompletableDeferred<Unit>()
        val queryCancelled = CompletableDeferred<Unit>()
        val queryJob = launch {
            queryStarted.complete(Unit)
            try {
                awaitCancellation()
            } finally {
                queryCancelled.complete(Unit)
            }
        }
        queryStarted.await()

        var explicitCancelObservedQueryCancellation = false
        withTimeout(1_000) {
            cancelActiveRagQuery(
                queryJob = queryJob,
                requestNativeCancellation = {
                    // Models an IO cancel queued behind the blocking JNI query:
                    // it cannot make progress until the query job is cancelled.
                    queryCancelled.await()
                    explicitCancelObservedQueryCancellation = true
                },
                onNativeCancellationFailure = { throw it },
            )
        }

        assertTrue(queryJob.isCancelled)
        assertTrue(explicitCancelObservedQueryCancellation)
    }
}
