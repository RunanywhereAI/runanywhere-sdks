package com.runanywhere.runanywhereai.ui.screens.rag

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
import com.runanywhere.sdk.public.api.ModelRef
import com.runanywhere.sdk.public.api.RagConfig
import com.runanywhere.sdk.public.api.RagDocument
import com.runanywhere.sdk.public.api.RagEvent
import com.runanywhere.sdk.public.api.RagSession
import com.runanywhere.sdk.public.api.rag
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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

    // Retrieval options exposed as UI toggles. Both live on the RAG session, so
    // flipping either re-opens it and re-indexes the loaded documents.
    var rerankEnabled by mutableStateOf(false)
        private set
    var multiQueryEnabled by mutableStateOf(false)
        private set

    private var session: RagSession? = null
    private var sessionKey: SessionKey? = null
    private var job: Job? = null
    private var ingestJob: Job? = null
    private var rerankJob: Job? = null
    private var corpusGeneration = 0L
    private var queryGeneration = 0L
    private var isRerankRebuildInFlight = false

    // Cached so a session rebuild (rerank toggle) can re-index the corpus.
    private val loadedDocs = mutableListOf<ExtractedDocument>()

    val hasDocuments: Boolean get() = documents.isNotEmpty()
    val isCorpusBusy: Boolean get() = isIngesting || isQuerying || isRerankRebuildInFlight

    fun addDocument(uri: Uri, embeddingId: String, llmId: String) {
        if (isCorpusBusy) return
        error = null
        isIngesting = true
        val generation = corpusGeneration
        ingestJob = viewModelScope.launch {
            try {
                val doc = withContext(Dispatchers.IO) { DocumentExtractor.extract(getApplication(), uri) }
                val active = openSession(embeddingId, llmId)
                active.ingest(RagDocument(text = doc.text, metadata = doc.metadata))
                val indexedChunks = runCatching { active.stats().chunkCount.toInt() }.getOrDefault(0)
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
                if (generation == corpusGeneration) isIngesting = false
            }
        }
    }

    fun updateMultiQuery(value: Boolean) {
        if (multiQueryEnabled == value || isCorpusBusy) return
        multiQueryEnabled = value
        rebuildSession { multiQueryEnabled = !value }
    }

    // Rerank is a session setting, so flipping it rebuilds the session and
    // re-indexes the documents already loaded.
    fun updateRerank(value: Boolean) {
        if (rerankEnabled == value || isCorpusBusy) return
        val previous = rerankEnabled
        if (sessionKey == null) {
            rerankEnabled = value
            return
        }
        rerankEnabled = value
        rebuildSession { rerankEnabled = previous }
    }

    /** Retrieval settings live on the session, so changing one re-opens it and re-indexes. */
    private fun rebuildSession(rollback: () -> Unit) {
        val key = sessionKey ?: return
        isRerankRebuildInFlight = true
        val generation = corpusGeneration
        rerankJob = viewModelScope.launch {
            try {
                closeSession()
                val active = openSession(key.embeddingId, key.llmId)
                loadedDocs.toList().forEach {
                    active.ingest(RagDocument(text = it.text, metadata = it.metadata))
                }
                chunkCount = active.stats().chunkCount.toInt()
            } catch (e: CancellationException) {
                if (generation == corpusGeneration) rollback()
                throw e
            } catch (e: Exception) {
                if (generation != corpusGeneration) return@launch
                RACLog.e("rag session rebuild failed", e)
                rollback()
                documents.clear()
                loadedDocs.clear()
                chunkCount = 0
                error = e.message ?: "Could not apply the retrieval change."
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
            // Live-updating answer slot; tokens stream in, then the completed
            // event replaces it with the final answer and cited sources.
            val answerIndex = messages.size
            messages += RagMessage("", isUser = false)
            val streamed = StringBuilder()
            var finalized = false
            try {
                val active = session ?: error("Choose document models and add a document first.")
                val startedAt = System.currentTimeMillis()
                val options = RagGenerationPolicy.options()
                active.queryStream(q, options).collect { event ->
                    currentCoroutineContext().ensureActive()
                    if (!requestVersion.isCurrent(queryGeneration, corpusGeneration)) {
                        return@collect
                    }
                    when (event) {
                        is RagEvent.Token -> {
                            streamed.append(event.text)
                            messages[answerIndex] = RagMessage(
                                text = RagAnswerNormalizer.visibleAnswer(streamed.toString()),
                                isUser = false,
                            )
                        }
                        is RagEvent.Completed -> {
                            messages[answerIndex] = buildRagAnswerMessage(
                                rawAnswer = event.result.answer,
                                sources = event.result.sources.map {
                                    RagSource(
                                        text = it.text.trim(),
                                        score = it.score,
                                        document = it.metadata["source"].orEmpty(),
                                    )
                                },
                                elapsedMs = System.currentTimeMillis() - startedAt,
                            )
                            finalized = true
                        }
                        is RagEvent.Retrieved -> Unit
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("rag query failed", e)
                if (requestVersion.isCurrent(queryGeneration, corpusGeneration)) {
                    error = e.message ?: "The query failed."
                }
            } finally {
                // Drop the placeholder if nothing streamed and no final answer
                // landed (error/cancel), so no empty bubble lingers.
                if (!finalized && streamed.isBlank() &&
                    answerIndex < messages.size && !messages[answerIndex].isUser &&
                    messages[answerIndex].text.isBlank()
                ) {
                    messages.removeAt(answerIndex)
                }
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
            stoppedJob?.cancel()
            stoppedJob?.join()
            if (stoppedVersion == queryGeneration) isQuerying = false
        }
    }

    fun clearAll() {
        cancelCorpusWork()
        viewModelScope.launch { closeSession() }
        clearCorpusState(clearMessages = true)
    }

    // The vector index is tied to the embedding model; if the chosen models change,
    // the session and everything indexed under it are no longer valid.
    fun onModelsChanged(embeddingId: String?, llmId: String?) {
        val key = sessionKey ?: return
        if (embeddingId != null && llmId != null && key == SessionKey(embeddingId, llmId)) return
        cancelCorpusWork()
        viewModelScope.launch { closeSession() }
        clearCorpusState(clearMessages = true)
    }

    private suspend fun openSession(embeddingId: String, llmId: String): RagSession {
        val key = SessionKey(embeddingId, llmId)
        session?.let { existing ->
            if (sessionKey == key) return existing
            documents.clear()
            messages.clear()
            chunkCount = 0
            loadedDocs.clear()
            closeSession()
        }
        val opened = RunAnywhere.rag.open(
            embeddingModel = ModelRef(embeddingId),
            llmModel = ModelRef(llmId),
            config = RagConfig(rerank = rerankEnabled, multiQuery = multiQueryEnabled),
        )
        session = opened
        sessionKey = key
        return opened
    }

    private suspend fun closeSession() {
        val open = session ?: return
        session = null
        sessionKey = null
        runCatching { open.close() }.onFailure { RACLog.w("rag session close failed: ${it.message}") }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun onCleared() {
        cancelCorpusWork()
        val open = session
        session = null
        sessionKey = null
        if (open != null) GlobalScope.launch { runCatching { open.close() } }
    }

    private fun cancelCorpusWork() {
        corpusGeneration++
        queryGeneration++
        job?.cancel()
        job = null
        ingestJob?.cancel()
        ingestJob = null
        rerankJob?.cancel()
        rerankJob = null
        isIngesting = false
        isQuerying = false
        isRerankRebuildInFlight = false
    }

    private fun clearCorpusState(clearMessages: Boolean) {
        documents.clear()
        if (clearMessages) messages.clear()
        chunkCount = 0
        loadedDocs.clear()
        error = null
    }

    private data class SessionKey(val embeddingId: String, val llmId: String)
}
