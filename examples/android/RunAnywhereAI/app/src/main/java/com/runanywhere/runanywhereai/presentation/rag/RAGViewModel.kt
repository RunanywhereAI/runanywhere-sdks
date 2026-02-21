package com.runanywhere.runanywhereai.presentation.rag

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.services.DocumentService
import com.runanywhere.runanywhereai.domain.services.DocumentServiceError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.RAG.RAGConfiguration
import com.runanywhere.sdk.public.extensions.ragCreatePipeline
import com.runanywhere.sdk.public.extensions.ragDestroyPipeline
import com.runanywhere.sdk.public.extensions.ragIngest
import com.runanywhere.sdk.public.extensions.ragQuery
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// MARK: - Message Role

/**
 * Role of a RAG conversation message.
 *
 * Scoped to the RAG feature to avoid polluting shared AppTypes.
 * Mirrors iOS MessageRole enum exactly.
 */
enum class RAGMessageRole {
    USER,
    ASSISTANT,
    SYSTEM,
}

// MARK: - RAG Message

/**
 * A single message in the RAG conversation.
 *
 * Uses a structured data class instead of a tuple (iOS uses anonymous tuples).
 * Mirrors iOS `(role: MessageRole, text: String)` pattern with a named type.
 */
data class RAGMessage(
    val role: RAGMessageRole,
    val text: String,
)

// MARK: - RAG UI State

/**
 * Immutable UI state for the RAG screen.
 *
 * Mirrors iOS RAGViewModel published properties as a single consolidated state.
 */
data class RAGUiState(
    /** Display name of the loaded document (last path component). */
    val documentName: String? = null,

    /** Whether a document has been fully ingested into the pipeline. */
    val isDocumentLoaded: Boolean = false,

    /** Whether the document extraction + pipeline creation is in progress. */
    val isLoadingDocument: Boolean = false,

    /** All conversation messages (user questions and assistant answers). */
    val messages: List<RAGMessage> = emptyList(),

    /** Whether a query is currently running. */
    val isQuerying: Boolean = false,

    /** Last error message, if any. */
    val error: String? = null,

    /** Current text entered by the user in the question field. */
    val currentQuestion: String = "",
) {
    /**
     * Whether the user can submit a question.
     * Mirrors iOS `canAskQuestion` computed property.
     */
    val canAskQuestion: Boolean
        get() = isDocumentLoaded && !isQuerying && currentQuestion.isNotBlank()
}

// MARK: - RAG ViewModel

/**
 * ViewModel for the RAG feature.
 *
 * Orchestrates document loading (text extraction, pipeline creation, ingestion),
 * query flow (vector search + LLM generation), and pipeline teardown.
 *
 * Mirrors iOS RAGViewModel exactly, adapted for Android ViewModel + StateFlow + viewModelScope.
 */
class RAGViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(RAGUiState())
    val uiState: StateFlow<RAGUiState> = _uiState.asStateFlow()

    // MARK: - Input

    /**
     * Update the current question text typed by the user.
     * Call this from the Compose TextField's onValueChange callback.
     */
    fun updateQuestion(text: String) {
        _uiState.update { it.copy(currentQuestion = text) }
    }

    // MARK: - Pipeline Lifecycle

    /**
     * Load a document: extract text, create RAG pipeline, ingest text.
     *
     * Mirrors iOS `RAGViewModel.loadDocument(url:config:)`.
     *
     * @param context Android context for ContentResolver access
     * @param uri Content URI of the document (PDF or JSON)
     * @param config RAG pipeline configuration with model paths and tuning parameters
     */
    fun loadDocument(context: Context, uri: Uri, config: RAGConfiguration) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingDocument = true, error = null) }

            try {
                val fileName = DocumentService.getFileName(context, uri) ?: "Document"
                Log.i(TAG, "Extracting text from document: $fileName")
                val extractedText = DocumentService.extractText(context, uri)

                Log.i(TAG, "Creating RAG pipeline")
                RunAnywhere.ragCreatePipeline(config)

                Log.i(TAG, "Ingesting document text (${extractedText.length} chars)")
                RunAnywhere.ragIngest(text = extractedText)

                _uiState.update {
                    it.copy(
                        documentName = fileName,
                        isDocumentLoaded = true,
                    )
                }
                Log.i(TAG, "Document loaded successfully: $fileName")
            } catch (e: DocumentServiceError) {
                Log.e(TAG, "Document extraction failed: ${e.message}")
                _uiState.update { it.copy(error = e.message) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load document: ${e.message}", e)
                _uiState.update { it.copy(error = e.message ?: "Failed to load document") }
            } finally {
                _uiState.update { it.copy(isLoadingDocument = false) }
            }
        }
    }

    /**
     * Query the loaded document with the current question.
     *
     * Appends the user question and the assistant answer (with timing) to messages.
     * Guards against empty questions and unloaded documents.
     *
     * Mirrors iOS `RAGViewModel.askQuestion()`.
     */
    fun askQuestion() {
        val question = _uiState.value.currentQuestion.trim()
        if (question.isEmpty() || !_uiState.value.isDocumentLoaded) return

        viewModelScope.launch {
            // Append user message, clear input, mark querying
            _uiState.update {
                it.copy(
                    messages = it.messages + RAGMessage(role = RAGMessageRole.USER, text = question),
                    currentQuestion = "",
                    isQuerying = true,
                    error = null,
                )
            }

            try {
                Log.i(TAG, "Querying RAG pipeline: $question")
                val result = RunAnywhere.ragQuery(question = question)

                val answerWithTiming = "${result.answer}\n\nAnswer generated in ${
                    String.format("%.1f", result.totalTimeMs / 1000.0)
                }s"

                _uiState.update {
                    it.copy(
                        messages = it.messages + RAGMessage(
                            role = RAGMessageRole.ASSISTANT,
                            text = answerWithTiming,
                        ),
                    )
                }
                Log.i(TAG, "Query complete (${result.totalTimeMs}ms)")
            } catch (e: Exception) {
                Log.e(TAG, "Query failed: ${e.message}", e)
                val errorText = "Error: ${e.message ?: "Query failed"}"
                _uiState.update {
                    it.copy(
                        messages = it.messages + RAGMessage(
                            role = RAGMessageRole.ASSISTANT,
                            text = errorText,
                        ),
                        error = e.message,
                    )
                }
            } finally {
                _uiState.update { it.copy(isQuerying = false) }
            }
        }
    }

    /**
     * Clear the loaded document and destroy the RAG pipeline.
     *
     * Resets all document and conversation state.
     * Mirrors iOS `RAGViewModel.clearDocument()`.
     */
    fun clearDocument() {
        viewModelScope.launch {
            try {
                RunAnywhere.ragDestroyPipeline()
                Log.i(TAG, "Document cleared and pipeline destroyed")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to destroy pipeline: ${e.message}", e)
            } finally {
                _uiState.update {
                    RAGUiState() // Reset to initial state
                }
            }
        }
    }

    companion object {
        private const val TAG = "RAGViewModel"
    }
}
