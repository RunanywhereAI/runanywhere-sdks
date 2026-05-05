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
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAGProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

// RAG native library loading (relocated from the deleted RAGBridge.kt).
//
// `librac_backend_rag_jni.so` is loaded once on first RAG entry so its JNI
// symbols (if any remain) are resolved before `CppBridgeRAGProto` dispatches.
// The main SDK's `librunanywhere_jni.so` must already be loaded (it hosts the
// canonical `racRag*Proto` thunks). `librac_backend_onnx.so` is loaded too so
// its ELF `__attribute__((constructor))` auto-registers the ONNX engine plugin
// (which provides embedding_ops, required for RAG pipeline creation). Loads
// are try/catch-wrapped so apps without those modules aren't blocked.
private val ragNativeLibsLoaded = AtomicBoolean(false)

private fun ensureRagNativeLibsLoaded() {
    if (!ragNativeLibsLoaded.compareAndSet(false, true)) return
    val logger = SDKLogger.rag
    try {
        System.loadLibrary("rac_backend_rag_jni")
    } catch (e: UnsatisfiedLinkError) {
        logger.warning("rac_backend_rag_jni not present: ${e.message}")
    }
    try {
        System.loadLibrary("rac_backend_onnx")
        logger.info("rac_backend_onnx loaded; embedding_ops available for RAG")
    } catch (e: UnsatisfiedLinkError) {
        logger.warning("rac_backend_onnx not present: ${e.message}")
    }
}

actual suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureRagNativeLibsLoaded()
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
    // IDL-13: `metadata_json` proto field was deleted. Decode caller-supplied
    // JSON (if any) into the typed `metadata` map before ingestion.
    val parsedMetadata: Map<String, String> =
        metadataJson
            ?.takeIf { it.isNotBlank() && it.trim().startsWith("{") && it.trim().endsWith("}") }
            ?.let { json ->
                runCatching {
                    json
                        .trim()
                        .removeSurrounding("{", "}")
                        .split(",")
                        .mapNotNull { pair ->
                            val parts = pair.split(":", limit = 2)
                            if (parts.size != 2) return@mapNotNull null
                            parts[0].trim().trim('"') to parts[1].trim().trim('"')
                        }.toMap()
                }.getOrDefault(emptyMap())
            } ?: emptyMap()
    withContext(Dispatchers.IO) {
        CppBridgeRAGProto.ingest(RAGDocument(text = text, metadata = parsedMetadata))
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
