package com.runanywhere.runanywhereai.ui.screens.rag

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import com.runanywhere.runanywhereai.data.rag.ExtractedDocument
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.public.extensions.ragCancelQuery
import com.runanywhere.sdk.public.extensions.ragCreatePipeline
import com.runanywhere.sdk.public.extensions.ragGetStatistics
import com.runanywhere.sdk.public.extensions.ragIngest
import com.runanywhere.sdk.public.extensions.ragQuery
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

data class RagSource(val text: String, val score: Float, val document: String)

data class RagMessage(
    val text: String,
    val isUser: Boolean,
    val sources: List<RagSource> = emptyList(),
    val elapsedMs: Long = 0,
)

internal fun buildRagAnswerMessage(
    rawAnswer: String,
    sources: List<RagSource>,
    elapsedMs: Long,
): RagMessage =
    RagMessage(
        text = RagAnswerNormalizer.visibleAnswer(rawAnswer)
            .ifBlank { "I couldn't produce a concise answer. Try asking more specifically." },
        isUser = false,
        sources = sources,
        elapsedMs = elapsedMs,
    )

/**
 * Stops the query coroutine before dispatching the explicit native cancel.
 *
 * The query itself owns a cancellation hook that calls the native cancel ABI
 * from its awaiting coroutine. Cancelling it first guarantees that hook can run
 * even when [requestNativeCancellation] is queued on the same saturated IO
 * dispatcher as the blocking JNI query.
 */
internal suspend fun cancelActiveRagQuery(
    queryJob: Job?,
    requestNativeCancellation: suspend () -> Unit,
    onNativeCancellationFailure: (Throwable) -> Unit,
) {
    queryJob?.cancel()
    runCatching { requestNativeCancellation() }
        .onFailure(onNativeCancellationFailure)
    queryJob?.join()
}

class RagViewModel(application: Application) : AndroidViewModel(application) {

    val documents = mutableStateListOf<String>()
    val messages = mutableStateListOf<RagMessage>()

    var chunkCount by mutableStateOf(0)
        private set
    var isIngesting by mutableStateOf(false)
        private set
    var isQuerying by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    // RAG retrieval options exposed as UI toggles. Rerank is a pipeline-level
    // setting (RAGConfiguration); multi-query is a per-query option.
    var rerankEnabled by mutableStateOf(false)
        private set
    var multiQueryEnabled by mutableStateOf(false)
        private set

    private var pipelineKey: Pair<String, String>? = null
    private var ingestKey: Pair<String, String>? = null
    private val pipelineOwner = "documents-${UUID.randomUUID()}"
    private var job: Job? = null
    private var ingestJob: Job? = null
    private var rerankJob: Job? = null
    private var corpusGeneration = 0L
    private var queryGeneration = 0L
    private var isRerankRebuildInFlight = false

    // Cached so a pipeline recreate (rerank toggle) can rebuild the full corpus.
    private val loadedDocs = mutableListOf<ExtractedDocument>()

    val hasDocuments: Boolean get() = documents.isNotEmpty()
    val isCorpusBusy: Boolean get() = isIngesting || isQuerying || isRerankRebuildInFlight

    fun addDocument(uri: Uri, embeddingId: String, llmId: String) {
        if (isCorpusBusy) return
        error = null
        isIngesting = true
        val generation = corpusGeneration
        ingestKey = embeddingId to llmId
        ingestJob = viewModelScope.launch {
            try {
                val doc = withContext(Dispatchers.IO) { DocumentExtractor.extract(getApplication(), uri) }
                val indexedChunks = withPipeline(embeddingId, llmId) {
                    RunAnywhere.ragIngest(
                        RAGDocument(text = doc.text, metadata = doc.metadata),
                    )
                    runCatching { RunAnywhere.ragGetStatistics().indexed_chunks.toInt() }
                        .getOrDefault(0)
                }
                currentCoroutineContext().ensureActive()
                if (generation != corpusGeneration) return@launch
                loadedDocs += doc
                documents += doc.name
                chunkCount = indexedChunks
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("rag ingest failed", e)
                if (generation == corpusGeneration) {
                    error = e.message ?: "Could not add the document."
                }
            } finally {
                if (generation == corpusGeneration) {
                    ingestKey = null
                    isIngesting = false
                }
            }
        }
    }

    fun updateMultiQuery(value: Boolean) {
        multiQueryEnabled = value
    }

    // Rerank is set on the pipeline (RAGConfiguration), so flipping it recreates
    // the pipeline. The recreated index starts empty, so re-ingest the loaded
    // document to keep it queryable after the change.
    fun updateRerank(value: Boolean) {
        if (rerankEnabled == value || isCorpusBusy) return
        val previous = rerankEnabled
        val key = pipelineKey
        if (key == null) {
            rerankEnabled = value
            return
        }
        rerankEnabled = value
        isRerankRebuildInFlight = true
        val generation = corpusGeneration
        rerankJob = viewModelScope.launch {
            try {
                withPipeline(key.first, key.second) {
                    chunkCount = RunAnywhere.ragGetStatistics().indexed_chunks.toInt()
                }
            } catch (e: CancellationException) {
                if (generation == corpusGeneration) rerankEnabled = previous
                throw e
            } catch (e: Exception) {
                if (generation != corpusGeneration) return@launch
                RACLog.e("rag rerank toggle failed", e)
                // The old pipeline is already torn down; roll the toggle back and
                // drop the (now gone) corpus so the UI reflects the real state.
                rerankEnabled = previous
                documents.clear()
                loadedDocs.clear()
                chunkCount = 0
                error = e.message ?: "Could not apply the rerank change."
            } finally {
                if (generation == corpusGeneration) isRerankRebuildInFlight = false
            }
        }
    }

    fun ask(question: String) {
        val q = question.trim()
        if (q.isBlank() || isCorpusBusy || !hasDocuments) return
        error = null
        messages += RagMessage(q, isUser = true)
        isQuerying = true
        val requestVersion = RagQueryVersion(query = ++queryGeneration, corpus = corpusGeneration)
        job = viewModelScope.launch {
            try {
                val options = RagGenerationPolicy.options(q, multiQueryEnabled)
                val key = pipelineKey ?: error("Choose document models and add a document first.")
                val result = withTimeout(RagGenerationPolicy.QUERY_TIMEOUT_MS) {
                    withPipeline(key.first, key.second) {
                        RunAnywhere.ragQuery(q, options)
                    }
                }
                currentCoroutineContext().ensureActive()
                if (!requestVersion.isCurrent(queryGeneration, corpusGeneration)) return@launch
                val sources = result.retrieved_chunks.map {
                    RagSource(text = it.text.trim(), score = it.similarity_score, document = it.source_document.orEmpty())
                }
                messages += buildRagAnswerMessage(
                    rawAnswer = result.answer,
                    sources = sources,
                    elapsedMs = result.total_time_ms,
                )
            } catch (e: TimeoutCancellationException) {
                if (requestVersion.isCurrent(queryGeneration, corpusGeneration)) {
                    error = "The query took too long and was stopped. Try a shorter question."
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("rag query failed", e)
                if (requestVersion.isCurrent(queryGeneration, corpusGeneration)) {
                    error = e.message ?: "The query failed."
                }
            } finally {
                if (requestVersion.query == queryGeneration) {
                    isQuerying = false
                    job = null
                }
            }
        }
    }

    fun stopQuery() {
        if (!isQuerying) return
        val stoppedVersion = ++queryGeneration
        val stoppedJob = job
        job = null
        viewModelScope.launch {
            cancelActiveRagQuery(
                queryJob = stoppedJob,
                requestNativeCancellation = { RunAnywhere.ragCancelQuery() },
                onNativeCancellationFailure = {
                    RACLog.w("rag query cancellation failed: ${it.message}")
                },
            )
            if (stoppedVersion == queryGeneration) isQuerying = false
        }
    }

    fun clearAll() {
        cancelCorpusWork()
        viewModelScope.launch { RagPipelineCoordinator.release(pipelineOwner) }
        pipelineKey = null
        clearCorpusState(clearMessages = true)
    }

    // The vector index is tied to the embedding model; if the chosen models change, the pipeline
    // and everything ingested under it are no longer valid, so tear them down and start fresh.
    fun onModelsChanged(embeddingId: String?, llmId: String?) {
        val key = pipelineKey ?: ingestKey ?: return
        if (embeddingId != null && llmId != null && key == (embeddingId to llmId)) return
        cancelCorpusWork()
        viewModelScope.launch { RagPipelineCoordinator.release(pipelineOwner) }
        pipelineKey = null
        ingestKey = null
        clearCorpusState(clearMessages = true)
    }

    // Pipeline config: rerank layered onto the model defaults.
    private fun buildConfig(embeddingId: String, llmId: String): RAGConfiguration =
        RAGConfiguration.defaults().copy(
            embedding_model_id = embeddingId,
            llm_model_id = llmId,
            rerank_results = rerankEnabled,
        )

    private suspend fun <T> withPipeline(
        embeddingId: String,
        llmId: String,
        block: suspend () -> T,
    ): T {
        val key = embeddingId to llmId
        if (pipelineKey != null && pipelineKey != key) {
            documents.clear()
            messages.clear()
            chunkCount = 0
            loadedDocs.clear()
        }
        val identity = RagPipelineIdentity(
            embeddingModelId = embeddingId,
            llmModelId = llmId,
            rerankEnabled = rerankEnabled,
        )
        return RagPipelineCoordinator.withPipeline(
            requestedOwner = pipelineOwner,
            requestedIdentity = identity,
            create = { RunAnywhere.ragCreatePipeline(buildConfig(embeddingId, llmId)) },
            rehydrate = {
                loadedDocs.toList().forEach {
                    RunAnywhere.ragIngest(
                        RAGDocument(text = it.text, metadata = it.metadata),
                    )
                }
            },
        ) {
            pipelineKey = key
            block()
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun onCleared() {
        cancelCorpusWork()
        if (pipelineKey != null) GlobalScope.launch { RagPipelineCoordinator.release(pipelineOwner) }
    }

    private fun cancelCorpusWork() {
        val hadActiveQuery = isQuerying
        corpusGeneration++
        queryGeneration++
        job?.cancel()
        job = null
        if (hadActiveQuery) requestNativeQueryCancellation()
        ingestJob?.cancel()
        ingestJob = null
        ingestKey = null
        rerankJob?.cancel()
        rerankJob = null
        isIngesting = false
        isQuerying = false
        isRerankRebuildInFlight = false
    }

    private fun requestNativeQueryCancellation() {
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { RunAnywhere.ragCancelQuery() }
                .onFailure { RACLog.w("rag query cancellation failed: ${it.message}") }
        }
    }

    private fun clearCorpusState(clearMessages: Boolean) {
        documents.clear()
        if (clearMessages) messages.clear()
        chunkCount = 0
        loadedDocs.clear()
        error = null
    }
}
