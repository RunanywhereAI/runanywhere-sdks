package com.runanywhere.runanywhereai.ui.screens.rag

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.ragDestroyPipeline
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Exact configuration of the process-wide native RAG pipeline. */
data class RagPipelineIdentity(
    val embeddingModelId: String,
    val llmModelId: String,
    val rerankEnabled: Boolean,
)

internal fun shouldRecreateRagPipeline(
    activeOwner: String?,
    activeIdentity: RagPipelineIdentity?,
    requestedOwner: String,
    requestedIdentity: RagPipelineIdentity,
): Boolean = activeOwner != requestedOwner || activeIdentity != requestedIdentity

/** Replaces, rather than appends to, the single-document corpus used by chat. */
internal suspend fun <T> replaceRagCorpus(
    clear: suspend () -> Unit,
    ingest: suspend () -> T,
): T {
    clear()
    return ingest()
}

/**
 * Serializes ownership of the SDK's single native RAG pipeline.
 *
 * Chat attachments and the Documents screen previously kept independent
 * `pipelineKey` caches. When either screen replaced the native singleton, the
 * other cache still claimed its old pipeline was active and could query the
 * wrong documents/model. A lease covers creation, any required rehydration,
 * and the inference operation so provenance always matches the pipeline that
 * actually executed.
 */
object RagPipelineCoordinator {
    private val mutex = Mutex()
    private var owner: String? = null
    private var identity: RagPipelineIdentity? = null

    suspend fun <T> withPipeline(
        requestedOwner: String,
        requestedIdentity: RagPipelineIdentity,
        create: suspend () -> Unit,
        rehydrate: suspend () -> Unit = {},
        block: suspend () -> T,
    ): T = mutex.withLock {
        val recreate = shouldRecreateRagPipeline(owner, identity, requestedOwner, requestedIdentity)
        if (recreate) {
            if (identity != null) runCatching { RunAnywhere.ragDestroyPipeline() }
            owner = null
            identity = null
            try {
                create()
                owner = requestedOwner
                identity = requestedIdentity
                rehydrate()
            } catch (t: Throwable) {
                runCatching { RunAnywhere.ragDestroyPipeline() }
                owner = null
                identity = null
                throw t
            }
        }
        block()
    }

    suspend fun ifOwned(requestedOwner: String, block: suspend () -> Unit) {
        mutex.withLock {
            if (owner == requestedOwner) block()
        }
    }

    suspend fun release(requestedOwner: String) {
        mutex.withLock {
            if (owner != requestedOwner) return@withLock
            runCatching { RunAnywhere.ragDestroyPipeline() }
            owner = null
            identity = null
        }
    }
}
