package com.runanywhere.runanywhereai.viewmodels

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.DocumentService
import com.runanywhere.runanywhereai.data.DocumentServiceError
import com.runanywhere.runanywhereai.models.DocumentInfo
import com.runanywhere.runanywhereai.models.DocumentType
import com.runanywhere.runanywhereai.models.RAGEvent
import com.runanywhere.runanywhereai.models.RAGMessage
import com.runanywhere.runanywhereai.models.RAGUiState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.RAG.RAGConfiguration
import com.runanywhere.sdk.public.extensions.ragCreatePipeline
import com.runanywhere.sdk.public.extensions.ragDestroyPipeline
import com.runanywhere.sdk.public.extensions.ragIngest
import com.runanywhere.sdk.public.extensions.ragQuery
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class RAGViewModel : ViewModel() {

    private val _uiState = MutableStateFlow<RAGUiState>(RAGUiState.Ready())
    val uiState: StateFlow<RAGUiState> = _uiState.asStateFlow()

    private val _events = Channel<RAGEvent>(Channel.BUFFERED)
    val events: Flow<RAGEvent> = _events.receiveAsFlow()

    // Selected model references (kept outside state to avoid exposing SDK types)
    private var selectedEmbeddingModel: ModelInfo? = null
    private var selectedLLMModel: ModelInfo? = null

    // -- Model Selection --

    fun onEmbeddingModelSelected(model: ModelInfo) {
        selectedEmbeddingModel = model
        updateReady {
            copy(
                hasEmbeddingModel = model.localPath != null,
                embeddingModelName = model.name,
            )
        }
    }

    fun onLLMModelSelected(model: ModelInfo) {
        selectedLLMModel = model
        updateReady {
            copy(
                hasLLMModel = model.localPath != null,
                llmModelName = model.name,
            )
        }
    }

    // -- Document Loading --

    fun loadDocument(context: Context, uri: Uri) {
        val config = buildRAGConfiguration() ?: return

        viewModelScope.launch {
            updateReady {
                copy(
                    isProcessingDocument = true,
                    processingProgress = null,
                    processingStatus = "Extracting text...",
                    error = null,
                )
            }

            try {
                val fileName = DocumentService.getFileName(context, uri) ?: "Document"
                val docType = DocumentType.from(fileName)

                Log.i(TAG, "Extracting text from: $fileName")
                updateReady { copy(processingStatus = "Extracting text from $fileName...") }

                val extractedText = withContext(Dispatchers.IO) {
                    DocumentService.extractText(context, uri)
                }

                Log.i(TAG, "Creating RAG pipeline")
                updateReady {
                    copy(
                        processingProgress = 0.3f,
                        processingStatus = "Creating RAG pipeline...",
                    )
                }
                RunAnywhere.ragCreatePipeline(config)

                Log.i(TAG, "Ingesting document (${extractedText.length} chars)")
                updateReady {
                    copy(
                        processingProgress = 0.6f,
                        processingStatus = "Indexing document...",
                    )
                }
                RunAnywhere.ragIngest(text = extractedText)

                val chunkCount = (extractedText.length / 512).coerceAtLeast(1)
                val docInfo = DocumentInfo(
                    name = fileName,
                    type = docType ?: DocumentType.PDF,
                    characterCount = extractedText.length,
                    chunkCount = chunkCount,
                )

                updateReady {
                    copy(
                        documents = (documents + docInfo).toImmutableList(),
                        processingProgress = 1f,
                        processingStatus = null,
                    )
                }
                Log.i(TAG, "Document loaded: $fileName ($chunkCount chunks)")
                _events.send(RAGEvent.ShowSnackbar("Document loaded: $fileName"))
            } catch (e: DocumentServiceError) {
                Log.e(TAG, "Document extraction failed: ${e.message}")
                updateReady { copy(error = e.message) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load document", e)
                updateReady { copy(error = e.message ?: "Failed to load document") }
            } finally {
                updateReady { copy(isProcessingDocument = false) }
            }
        }
    }

    // -- Question Answering --

    fun askQuestion(question: String) {
        val trimmed = question.trim()
        if (trimmed.isEmpty()) return

        val state = (_uiState.value as? RAGUiState.Ready) ?: return
        if (!state.canAskQuestion) return

        val message = RAGMessage(
            question = trimmed,
            answer = "",
            isStreaming = true,
        )

        viewModelScope.launch {
            updateReady {
                copy(
                    messages = (messages + message).toImmutableList(),
                    isQuerying = true,
                    error = null,
                )
            }
            _events.send(RAGEvent.ScrollToBottom)

            try {
                Log.i(TAG, "Querying: $trimmed")
                val startTime = System.currentTimeMillis()

                val result = withContext(Dispatchers.IO) {
                    RunAnywhere.ragQuery(question = trimmed)
                }

                val elapsedMs = System.currentTimeMillis() - startTime

                // Stream the answer word-by-word for a typewriter effect
                val words = result.answer.split(WORD_BOUNDARY_REGEX)
                val revealed = StringBuilder()

                for ((index, word) in words.withIndex()) {
                    revealed.append(word)
                    updateMessageAnswer(message.id, revealed.toString(), isStreaming = true)

                    // Small delay between words for streaming feel
                    if (index < words.lastIndex) {
                        delay(STREAM_WORD_DELAY_MS)
                    }
                }

                // Final update: mark as complete with timing
                updateMessageAnswer(
                    messageId = message.id,
                    answer = result.answer,
                    isStreaming = false,
                    generationTimeMs = elapsedMs,
                )

                Log.i(TAG, "Query completed in ${elapsedMs}ms")
            } catch (e: Exception) {
                Log.e(TAG, "Query failed", e)
                updateMessageAnswer(
                    messageId = message.id,
                    answer = "Error: ${e.message ?: "Query failed"}",
                    isStreaming = false,
                )
                updateReady { copy(error = e.message) }
            } finally {
                updateReady { copy(isQuerying = false) }
                _events.send(RAGEvent.ScrollToBottom)
            }
        }
    }

    private fun updateMessageAnswer(
        messageId: String,
        answer: String,
        isStreaming: Boolean,
        generationTimeMs: Long? = null,
    ) {
        updateReady {
            val updated = messages.map { msg ->
                if (msg.id == messageId) {
                    msg.copy(
                        answer = answer,
                        isStreaming = isStreaming,
                        generationTimeMs = generationTimeMs,
                    )
                } else {
                    msg
                }
            }.toImmutableList()
            copy(messages = updated)
        }
    }

    // -- Document Management --

    fun clearAllDocuments() {
        viewModelScope.launch {
            try {
                RunAnywhere.ragDestroyPipeline()
                Log.i(TAG, "Pipeline destroyed")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to destroy pipeline", e)
            } finally {
                _uiState.value = RAGUiState.Ready(
                    hasEmbeddingModel = selectedEmbeddingModel?.localPath != null,
                    hasLLMModel = selectedLLMModel?.localPath != null,
                    embeddingModelName = selectedEmbeddingModel?.name,
                    llmModelName = selectedLLMModel?.name,
                )
            }
        }
    }

    fun clearError() {
        updateReady { copy(error = null) }
    }

    // -- Private Helpers --

    private fun buildRAGConfiguration(): RAGConfiguration? {
        val embeddingLocalPath = selectedEmbeddingModel?.localPath ?: return null
        val llmLocalPath = selectedLLMModel?.localPath ?: return null

        val resolvedEmbeddingPath = resolveEmbeddingFilePath(embeddingLocalPath)
        val resolvedLLMPath = resolveLLMFilePath(llmLocalPath)
        val vocabPath = resolveVocabPath(embeddingLocalPath)

        val embeddingConfigJson = if (vocabPath != null) {
            """{"vocab_path":"$vocabPath"}"""
        } else {
            null
        }

        return RAGConfiguration(
            embeddingModelPath = resolvedEmbeddingPath,
            llmModelPath = resolvedLLMPath,
            embeddingConfigJson = embeddingConfigJson,
        )
    }

    private fun resolveEmbeddingFilePath(localPath: String): String {
        val file = File(localPath)
        if (!file.isDirectory) return localPath

        val files = file.listFiles() ?: return localPath
        val onnxFile = files.firstOrNull { it.extension.lowercase() == "onnx" }
        if (onnxFile != null) return onnxFile.absolutePath

        return "$localPath/model.onnx"
    }

    private fun resolveLLMFilePath(localPath: String): String {
        val file = File(localPath)
        if (!file.isDirectory) return localPath

        val files = file.listFiles() ?: return localPath
        val ggufFile = files.firstOrNull { it.extension.lowercase() == "gguf" }
        if (ggufFile != null) return ggufFile.absolutePath

        val largestFile = files.filter { it.isFile }.maxByOrNull { it.length() }
        return largestFile?.absolutePath ?: localPath
    }

    private fun resolveVocabPath(embeddingLocalPath: String): String? {
        val file = File(embeddingLocalPath)
        return if (file.isDirectory) {
            "$embeddingLocalPath/vocab.txt"
        } else {
            "${file.parent}/vocab.txt"
        }
    }

    private inline fun updateReady(crossinline transform: RAGUiState.Ready.() -> RAGUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is RAGUiState.Ready -> current.transform()
            }
        }
    }

    companion object {
        private const val TAG = "RAGViewModel"
        /** Delay between words during streaming reveal (ms). */
        private const val STREAM_WORD_DELAY_MS = 30L
        /** Regex to split answer into words while preserving whitespace/punctuation. */
        private val WORD_BOUNDARY_REGEX = Regex("(?<=\\s)|(?=\\s)")
    }
}
