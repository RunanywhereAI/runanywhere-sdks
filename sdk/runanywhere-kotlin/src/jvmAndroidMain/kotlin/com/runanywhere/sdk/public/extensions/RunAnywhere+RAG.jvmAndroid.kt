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
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private fun checkRc(rc: Int, op: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$op failed with rc=$rc")
    }
}

actual suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc = RunAnywhereBridge.racRagCreatePipeline(config.encode())
        checkRc(rc, "rac_rag_create_pipeline")
    }
}

actual suspend fun RunAnywhere.ragDestroyPipeline() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc = RunAnywhereBridge.racRagDestroyPipeline()
        checkRc(rc, "rac_rag_destroy_pipeline")
    }
}

actual suspend fun RunAnywhere.ragIngest(text: String, metadataJson: String?) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc = RunAnywhereBridge.racRagIngest(text, metadataJson)
        checkRc(rc, "rac_rag_ingest")
    }
}

actual suspend fun RunAnywhere.ragClearDocuments() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc = RunAnywhereBridge.racRagClearDocuments()
        checkRc(rc, "rac_rag_clear_documents")
    }
}

actual suspend fun RunAnywhere.ragGetDocumentCount(): Int =
    withContext(Dispatchers.IO) {
        RunAnywhereBridge.racRagGetDocumentCount()
    }

actual suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions?,
): RAGResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        val optBytes = options?.encode()
        val resultBytes =
            RunAnywhereBridge.racRagQuery(question, optBytes)
                ?: throw SDKException.operation("rac_rag_query returned null")
        RAGResult.ADAPTER.decode(resultBytes)
    }
}

actual suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RAGDocument>) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        // Serialize the documents into a JSON array. Each document is encoded
        // with the fields the C++ pipeline expects (text + metadata_json).
        val arr =
            JsonArray(
                documents.map { doc ->
                    JsonObject(
                        mapOf(
                            "id" to JsonPrimitive(doc.id),
                            "text" to JsonPrimitive(doc.text),
                            "metadata_json" to JsonPrimitive(doc.metadataJson),
                        ),
                    )
                },
            )
        val rc = RunAnywhereBridge.racRagAddDocumentsBatch(Json.encodeToString(JsonArray.serializer(), arr))
        checkRc(rc, "rac_rag_add_documents_batch")
    }
}

actual suspend fun RunAnywhere.ragGetStatistics(): RAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        val bytes =
            RunAnywhereBridge.racRagGetStatistics()
                ?: throw SDKException.operation("rac_rag_get_statistics returned null")
        RAGStatistics.ADAPTER.decode(bytes)
    }
}
