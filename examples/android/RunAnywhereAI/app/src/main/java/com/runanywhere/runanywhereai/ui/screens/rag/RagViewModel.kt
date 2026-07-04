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

    // On-device index snapshot. Persistence means chunks survive an app restart
    // (the fingerprint-guarded snapshot is reloaded instead of re-embedding).
    private val indexPath: String = getApplication<Application>().filesDir.resolve("rag_index.bin").absolutePath

    val hasDocuments: Boolean get() = documents.isNotEmpty()

    fun addDocument(uri: Uri, embeddingId: String, llmId: String) {
        if (isIngesting) return
        error = null
        isIngesting = true
        viewModelScope.launch {
            try {
                val doc = withContext(Dispatchers.IO) { DocumentExtractor.extract(getApplication(), uri) }
                ensurePipeline(embeddingId, llmId)
                RunAnywhere.ragIngest(doc.text, doc.metadataJSON)
                documents += doc.name
                chunkCount = runCatching { RunAnywhere.ragGetStatistics().indexed_chunks.toInt() }
                    .getOrDefault(chunkCount)
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
    // the pipeline. With persistence on, the snapshot is reloaded — the ingested
    // corpus survives the recreate without re-embedding.
    fun updateRerank(value: Boolean) {
        if (rerankEnabled == value) return
        rerankEnabled = value
        val key = pipelineKey ?: return
        viewModelScope.launch {
            runCatching {
                RunAnywhere.ragDestroyPipeline()
                RunAnywhere.ragCreatePipeline(buildConfig(key.first, key.second))
                chunkCount = RunAnywhere.ragGetStatistics().indexed_chunks.toInt()
            }.onFailure { RACLog.e("rag rerank toggle failed", it) }
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
    }

    // Pipeline config: rerank + fingerprint-guarded persistence layered onto the
    // model defaults. index_path makes the vector index survive app restarts.
    private fun buildConfig(embeddingId: String, llmId: String): RAGConfiguration =
        RAGConfiguration.defaults(embeddingModelId = embeddingId, llmModelId = llmId).copy(
            rerank_results = rerankEnabled,
            persist_index = true,
            index_path = indexPath,
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
