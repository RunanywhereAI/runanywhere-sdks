package com.runanywhere.runanywhereai.ui.screens.rag

internal fun formatDocumentChunkSummary(documentCount: Int, chunkCount: Int): String {
    val documentLabel = if (documentCount == 1) "document" else "documents"
    val chunkLabel = if (chunkCount == 1) "chunk" else "chunks"
    return "$documentCount $documentLabel · $chunkCount $chunkLabel"
}
