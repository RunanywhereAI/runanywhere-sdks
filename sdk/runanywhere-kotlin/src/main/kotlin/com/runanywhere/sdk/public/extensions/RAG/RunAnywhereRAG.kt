/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Retrieval-Augmented Generation (RAG) operations.
 * Delegates all pipeline work to RAGBridge (JNI), publishes events to EventBus.
 *
 * Mirrors Swift RunAnywhere+RAG.swift exactly. Acronym-preserving names
 * (`metadataJSON`) are used to match the Swift surface; the Wire-generated
 * proto continues to expose the snake_case `metadata` map under the hood.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAG
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
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

// MARK: - Pipeline Lifecycle




// MARK: - Document Ingestion







// MARK: - Query


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

suspend fun RunAnywhere.ragResolvedConfiguration(
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

suspend fun RunAnywhere.ragCreatePipeline(config: RARAGConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureRagNativeLibsLoaded()
    withContext(Dispatchers.IO) {
        CppBridgeRAG.create(config)
    }
}

suspend fun RunAnywhere.ragDestroyPipeline() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAG.destroy()
    }
}

suspend fun RunAnywhere.ragIngest(text: String, metadataJSON: String?) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val document = RAGDocument.create(text = text, metadataJSON = metadataJSON)
    withContext(Dispatchers.IO) {
        CppBridgeRAG.ingest(document)
    }
}

suspend fun RunAnywhere.ragIngest(document: RARAGDocument): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.ingest(document)
    }
}

suspend fun RunAnywhere.ragClearDocuments() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeRAG.clear()
    }
}

suspend fun RunAnywhere.ragGetDocumentCount(): Int =
    withContext(Dispatchers.IO) {
        CppBridgeRAG.stats().indexed_chunks.toInt()
    }

suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions?,
): RAGResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.query((options ?: RAGQueryOptions.defaults(question)).copy(question = question))
    }
}

suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RARAGDocument>): RARAGStatistics {
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

suspend fun RunAnywhere.ragGetStatistics(): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.stats()
    }
}
