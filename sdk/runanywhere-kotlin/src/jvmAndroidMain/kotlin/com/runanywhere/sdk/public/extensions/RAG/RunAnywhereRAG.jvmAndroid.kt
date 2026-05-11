/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for RAG (Retrieval-Augmented Generation).
 *
 * All public RAG methods route through the canonical `racRag*` JNI thunks
 * declared in RunAnywhereBridge via [CppBridgeRAG]. If the underlying C++
 * symbol is missing, callers see UnsatisfiedLinkError at runtime.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGSearchResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAG
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult
import com.runanywhere.sdk.public.types.RARAGConfiguration
import com.runanywhere.sdk.public.types.RARAGDocument
import com.runanywhere.sdk.public.types.RARAGStatistics
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// RAG native library loading (relocated from the deleted RAGBridge.kt).
//
// `librac_backend_rag_jni.so` is loaded once on first RAG entry so its JNI
// symbols (if any remain) are resolved before `CppBridgeRAG` dispatches.
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

actual suspend fun RunAnywhere.ragResolvedConfiguration(
    embeddingModel: RAModelInfo,
    llmModel: RAModelInfo,
    baseConfiguration: RARAGConfiguration,
): RARAGConfiguration {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val embedding =
        loadRagArtifactModel(
            this,
            embeddingModel,
            ModelCategory.MODEL_CATEGORY_EMBEDDING,
            "Embedding",
        )
    val llm =
        loadRagArtifactModel(
            this,
            llmModel,
            ModelCategory.MODEL_CATEGORY_LANGUAGE,
            "LLM",
        )
    return baseConfiguration.resolvingLifecycleArtifacts(embedding = embedding, llm = llm)
}

private suspend fun loadRagArtifactModel(
    sdk: RunAnywhere,
    model: RAModelInfo,
    fallbackCategory: ModelCategory,
    errorLabel: String,
): RAModelLoadResult {
    val request =
        RAModelLoadRequest(
            model_id = model.id,
            category =
                if (model.category == ModelCategory.MODEL_CATEGORY_UNSPECIFIED) {
                    fallbackCategory
                } else {
                    model.category
                },
            framework = model.framework,
        )
    val result = sdk.loadModel(request)
    if (!result.success) {
        val message =
            result.error_message.ifBlank { "$errorLabel model lifecycle artifact resolution failed" }
        throw SDKException.model("$errorLabel model '${model.id}': $message")
    }
    return result
}

actual suspend fun RunAnywhere.ragCreatePipeline(config: RARAGConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureRagNativeLibsLoaded()
    withContext(Dispatchers.IO) {
        CppBridgeRAG.create(config)
    }
}

actual suspend fun RunAnywhere.ragDestroyPipeline() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAG.destroy()
    }
}

actual suspend fun RunAnywhere.ragIngest(text: String, metadataJSON: String?) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val document = RAGDocument.create(text = text, metadataJSON = metadataJSON)
    withContext(Dispatchers.IO) {
        CppBridgeRAG.ingest(document)
    }
}

actual suspend fun RunAnywhere.ragIngest(document: RARAGDocument): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.ingest(document)
    }
}

actual suspend fun RunAnywhere.ragClearDocuments() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAG.clear()
    }
}

actual suspend fun RunAnywhere.ragGetDocumentCount(): Int =
    withContext(Dispatchers.IO) {
        CppBridgeRAG.stats().indexed_chunks.toInt()
    }

actual suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions?,
): RAGResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.query((options ?: RAGQueryOptions.defaults(question)).copy(question = question))
    }
}

actual suspend fun RunAnywhere.ragQueryWithContext(
    query: String,
    systemPrompt: String?,
    options: RAGQueryOptions,
): RAGResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val merged = options.copy(question = query, system_prompt = systemPrompt ?: options.system_prompt)
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.query(merged)
    }
}

actual suspend fun RunAnywhere.ragSearch(
    query: String,
    topK: Int,
    threshold: Float,
): List<RAGSearchResult> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val searchOptions =
        RAGQueryOptions.defaults(query).copy(
            question = query,
            top_k = topK,
            similarity_threshold = threshold,
            // Suppress LLM generation by zeroing max_tokens; the C++ ABI still
            // populates retrieved_chunks from vector retrieval before stopping.
            max_tokens = 0,
        )
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.query(searchOptions).retrieved_chunks
    }
}

actual suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RARAGDocument>): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (documents.isEmpty()) return ragGetStatistics()
    return withContext(Dispatchers.IO) {
        var lastStats = CppBridgeRAG.stats()
        documents.forEach { document ->
            lastStats = CppBridgeRAG.ingest(document)
        }
        lastStats
    }
}

actual suspend fun RunAnywhere.ragGetStatistics(): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.stats()
    }
}
