/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for RAG (Retrieval-Augmented Generation).
 *
 * Round 1 KOTLIN (G-A4): all eight RAG public methods now call the
 * canonical `racRag*` JNI thunks declared in RunAnywhereBridge. The
 * `notImplemented` stubs have been DELETED — if the underlying C++
 * symbol is missing, callers see UnsatisfiedLinkError at runtime
 * (that's the C++ track's problem, not the Kotlin track's).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAGProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAGProto.create(config)
    }
}

actual suspend fun RunAnywhere.ragDestroyPipeline() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAGProto.destroy()
    }
}

actual suspend fun RunAnywhere.ragIngest(text: String, metadataJson: String?) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAGProto.ingest(RAGDocument(text = text, metadata_json = metadataJson))
    }
}

actual suspend fun RunAnywhere.ragClearDocuments() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAGProto.clear()
    }
}

actual suspend fun RunAnywhere.ragGetDocumentCount(): Int =
    withContext(Dispatchers.IO) {
        CppBridgeRAGProto.stats().indexed_chunks.toInt()
    }

actual suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions?,
): RAGResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAGProto.query((options ?: RAGQueryOptions()).copy(question = question))
    }
}

actual suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RAGDocument>) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        documents.forEach(CppBridgeRAGProto::ingest)
    }
}

actual suspend fun RunAnywhere.ragGetStatistics(): RAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAGProto.stats()
    }
}
