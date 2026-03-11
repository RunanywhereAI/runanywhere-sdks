package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

// -- UI State --

@Immutable
sealed interface RAGUiState {

    /** Ready state -- the screen starts here (no spinner). */
    @Immutable
    data class Ready(
        /** Currently loaded documents. */
        val documents: ImmutableList<DocumentInfo> = persistentListOf(),
        /** Q&A conversation history. */
        val messages: ImmutableList<RAGMessage> = persistentListOf(),
        /** True while a document is being processed (extracted + ingested). */
        val isProcessingDocument: Boolean = false,
        /** 0f..1f progress for document processing (indeterminate when null). */
        val processingProgress: Float? = null,
        /** Status text shown during document processing. */
        val processingStatus: String? = null,
        /** True while a query is running. */
        val isQuerying: Boolean = false,
        /** Whether embedding model is selected. */
        val hasEmbeddingModel: Boolean = false,
        /** Whether LLM model is selected. */
        val hasLLMModel: Boolean = false,
        /** Display name of selected embedding model. */
        val embeddingModelName: String? = null,
        /** Display name of selected LLM model. */
        val llmModelName: String? = null,
        /** Last error, if any. */
        val error: String? = null,
    ) : RAGUiState {

        val areModelsReady: Boolean
            get() = hasEmbeddingModel && hasLLMModel

        val hasDocuments: Boolean
            get() = documents.isNotEmpty()

        val canAskQuestion: Boolean
            get() = hasDocuments && !isQuerying && !isProcessingDocument

        val totalChunks: Int
            get() = documents.sumOf { it.chunkCount }
    }
}

// -- Document Info --

@Immutable
data class DocumentInfo(
    val name: String,
    val type: DocumentType,
    val characterCount: Int,
    /** Approximate chunk count (characters / 512). */
    val chunkCount: Int,
)

enum class DocumentType(val displayName: String) {
    PDF("PDF"),
    JSON("JSON"),
    ;

    companion object {
        fun from(fileName: String): DocumentType? {
            return when (fileName.substringAfterLast('.', "").lowercase()) {
                "pdf" -> PDF
                "json" -> JSON
                else -> null
            }
        }
    }
}

// -- Messages --

@Immutable
data class RAGMessage(
    val id: String = java.util.UUID.randomUUID().toString(),
    val question: String,
    val answer: String,
    /** Whether the answer is still being generated. */
    val isStreaming: Boolean = false,
    /** Generation time in milliseconds. */
    val generationTimeMs: Long? = null,
    /** Source context chunks used for the answer. */
    val sourceChunks: ImmutableList<String> = persistentListOf(),
)

// -- Events --

sealed interface RAGEvent {
    data object ScrollToBottom : RAGEvent
    data class ShowSnackbar(val message: String) : RAGEvent
}
