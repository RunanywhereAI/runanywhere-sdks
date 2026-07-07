package com.runanywhere.runanywhereai.ui.screens.rag

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGQueryOptions
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
import com.runanywhere.sdk.public.extensions.defaults
import com.runanywhere.sdk.public.extensions.ragClearDocuments
import com.runanywhere.sdk.public.extensions.ragCreatePipeline
import com.runanywhere.sdk.public.extensions.ragDestroyPipeline
import com.runanywhere.sdk.public.extensions.ragGetStatistics
import com.runanywhere.sdk.public.extensions.ragIngest
import com.runanywhere.sdk.public.extensions.ragQuery
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

data class RagSource(val text: String, val score: Float, val document: String)

data class RagMessage(
    val text: String,
    val isUser: Boolean,
    val sources: List<RagSource> = emptyList(),
    val elapsedMs: Long = 0,
)

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
    private var job: Job? = null
    private var isRerankRebuildInFlight = false

    // The currently loaded document, cached so a pipeline recreate (rerank toggle)
    // can re-ingest it — without persistence the recreated index starts empty.
    private var loadedDoc: ExtractedDocument? = null

    val hasDocuments: Boolean get() = documents.isNotEmpty()

    fun addDocument(uri: Uri, embeddingId: String, llmId: String) {
        if (isIngesting) return
        error = null
        isIngesting = true
        viewModelScope.launch {
            try {
                val doc = withContext(Dispatchers.IO) { DocumentExtractor.extract(getApplication(), uri) }
                ensurePipeline(embeddingId, llmId)
                // Each document is queried in isolation: replace the previous
                // corpus instead of accumulating, which would blend unrelated
                // documents in retrieval.
                RunAnywhere.ragClearDocuments()
                documents.clear()
                RunAnywhere.ragIngest(doc.text, doc.metadataJSON)
                loadedDoc = doc
                documents += doc.name
                chunkCount = runCatching { RunAnywhere.ragGetStatistics().indexed_chunks.toInt() }
                    .getOrDefault(0)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("rag ingest failed", e)
                error = e.message ?: "Could not add the document."
            } finally {
                isIngesting = false
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
        if (rerankEnabled == value || isRerankRebuildInFlight) return
        val previous = rerankEnabled
        val key = pipelineKey
        if (key == null) {
            rerankEnabled = value
            return
        }
        rerankEnabled = value
        isRerankRebuildInFlight = true
        viewModelScope.launch {
            try {
                RunAnywhere.ragDestroyPipeline()
                RunAnywhere.ragCreatePipeline(buildConfig(key.first, key.second))
                loadedDoc?.let { RunAnywhere.ragIngest(it.text, it.metadataJSON) }
                chunkCount = RunAnywhere.ragGetStatistics().indexed_chunks.toInt()
            } catch (e: CancellationException) {
                rerankEnabled = previous
                throw e
            } catch (e: Exception) {
                RACLog.e("rag rerank toggle failed", e)
                // The old pipeline is already torn down; roll the toggle back and
                // drop the (now gone) corpus so the UI reflects the real state.
                rerankEnabled = previous
                documents.clear()
                loadedDoc = null
                chunkCount = 0
                error = e.message ?: "Could not apply the rerank change."
            } finally {
                isRerankRebuildInFlight = false
            }
        }
    }

    fun ask(question: String) {
        val q = question.trim()
        if (q.isBlank() || isQuerying || !hasDocuments) return
        error = null
        messages += RagMessage(q, isUser = true)
        isQuerying = true
        job = viewModelScope.launch {
            try {
                val options = RAGQueryOptions.defaults(question = q).copy(enable_multi_query = multiQueryEnabled)
                val result = RunAnywhere.ragQuery(q, options)
                val sources = result.retrieved_chunks.map {
                    RagSource(text = it.text.trim(), score = it.similarity_score, document = it.source_document.orEmpty())
                }
                messages += RagMessage(
                    text = result.answer.ifBlank { "I couldn't find an answer in your documents." },
                    isUser = false,
                    sources = sources,
                    elapsedMs = result.total_time_ms,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("rag query failed", e)
                error = e.message ?: "The query failed."
            } finally {
                isQuerying = false
            }
        }
    }

    fun clearAll() {
        job?.cancel()
        viewModelScope.launch { runCatching { RunAnywhere.ragClearDocuments() } }
        documents.clear()
        messages.clear()
        chunkCount = 0
        loadedDoc = null
        error = null
    }

    // The vector index is tied to the embedding model; if the chosen models change, the pipeline
    // and everything ingested under it are no longer valid, so tear them down and start fresh.
    fun onModelsChanged(embeddingId: String?, llmId: String?) {
        val key = pipelineKey ?: return
        if (embeddingId != null && llmId != null && key == (embeddingId to llmId)) return
        viewModelScope.launch { runCatching { RunAnywhere.ragDestroyPipeline() } }
        pipelineKey = null
        documents.clear()
        messages.clear()
        chunkCount = 0
        loadedDoc = null
    }

    // Pipeline config: rerank layered onto the model defaults.
    private fun buildConfig(embeddingId: String, llmId: String): RAGConfiguration =
        RAGConfiguration.defaults(embeddingModelId = embeddingId, llmModelId = llmId).copy(
            rerank_results = rerankEnabled,
        )

    private suspend fun ensurePipeline(embeddingId: String, llmId: String) {
        val key = embeddingId to llmId
        if (pipelineKey == key) return
        if (pipelineKey != null) runCatching { RunAnywhere.ragDestroyPipeline() }
        documents.clear()
        messages.clear()
        chunkCount = 0
        RunAnywhere.ragCreatePipeline(buildConfig(embeddingId, llmId))
        pipelineKey = key
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun onCleared() {
        job?.cancel()
        if (pipelineKey != null) GlobalScope.launch { runCatching { RunAnywhere.ragDestroyPipeline() } }
    }
}
