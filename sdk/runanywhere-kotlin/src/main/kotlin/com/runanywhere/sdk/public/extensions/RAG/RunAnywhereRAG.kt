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

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
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
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

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
//
// `librac_backend_rag_jni.so` is currently not packaged for arm64-v8a in
// many builds. The ONNX engine plugin
// (`librac_backend_onnx.so`) is the canonical RAG backend and provides
// embedding_ops; the RAG flow works end-to-end without the JNI shim. The
// shim's absence is therefore demoted to DEBUG to avoid alarming users while
// still being observable for backend development. The ONNX load failure
// remains a WARNING because it really does block RAG pipeline creation.
private val ragNativeLibsLoaded = AtomicBoolean(false)

private fun ensureRagNativeLibsLoaded() {
    if (!ragNativeLibsLoaded.compareAndSet(false, true)) return
    val logger = SDKLogger.rag
    try {
        System.loadLibrary("rac_backend_rag_jni")
    } catch (e: UnsatisfiedLinkError) {
        // Optional JNI shim; ONNX engine plugin handles RAG without it.
        logger.debug("rac_backend_rag_jni not present (optional): ${e.message}")
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
    ensureServicesReady()
    ensureRagNativeLibsLoaded()
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
            framework =
                model.framework.takeUnless {
                    it == InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED ||
                        it == InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
                },
        )
    val result = sdk.loadModel(request)
    if (!result.success) {
        val message =
            result.error_message.ifBlank { "$errorLabel model lifecycle artifact resolution failed" }
        throw SDKException.model("$errorLabel model '${model.id}': $message")
    }
    return result
}

/**
 * Create the RAG pipeline from registry models. Model artifact layout is
 * resolved by commons lifecycle rather than by file-name heuristics, so callers
 * can hand in [RAModelInfo] entries from the catalogue without first building a
 * [RARAGConfiguration] by hand. Mirrors Swift `ragCreatePipeline(embeddingModel:llmModel:baseConfiguration:)`.
 */
suspend fun RunAnywhere.ragCreatePipeline(
    embeddingModel: RAModelInfo,
    llmModel: RAModelInfo,
    baseConfiguration: RARAGConfiguration = RARAGConfiguration.defaults(),
) {
    val resolved =
        ragResolvedConfiguration(
            embeddingModel = embeddingModel,
            llmModel = llmModel,
            baseConfiguration = baseConfiguration,
        )
    ragCreatePipeline(resolved)
}

suspend fun RunAnywhere.ragCreatePipeline(config: RARAGConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    ensureRagNativeLibsLoaded()
    withContext(Dispatchers.IO) {
        CppBridgeRAG.create(config)
    }
}

/** Destroy the RAG pipeline and release all resources. */
suspend fun RunAnywhere.ragDestroyPipeline() {
    withContext(Dispatchers.IO) {
        CppBridgeRAG.destroy()
    }
}

suspend fun RunAnywhere.ragIngest(text: String, metadataJSON: String? = null) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    val document = RAGDocument.create(text = text, metadataJSON = metadataJSON)
    withContext(Dispatchers.IO) {
        CppBridgeRAG.ingest(document)
    }
}

suspend fun RunAnywhere.ragIngest(document: RARAGDocument): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.ingest(document)
    }
}

suspend fun RunAnywhere.ragClearDocuments() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    withContext(Dispatchers.IO) {
        CppBridgeRAG.clear()
    }
}

/**
 * Get the number of indexed document chunks in the pipeline as a function call.
 *
 * @return Number of indexed chunks in the pipeline, or 0 if not initialized.
 */
suspend fun RunAnywhere.ragGetDocumentCount(): Int =
    withContext(Dispatchers.IO) {
        try {
            CppBridgeRAG.stats().indexed_chunks.toInt()
        } catch (_: Exception) {
            0
        }
    }

/** The current number of indexed document chunks in the pipeline. */
suspend fun RunAnywhere.ragDocumentCount(): Int = ragGetDocumentCount()

suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions? = null,
): RAGResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    val queryOptions =
        (options ?: RAGQueryOptions.defaults(question)).let {
            if (it.question.isEmpty()) it.copy(question = question) else it
        }
    return runCancellableNativeRagQuery(
        query = { CppBridgeRAG.query(queryOptions) },
        cancel = CppBridgeRAG::cancelQuery,
    )
}

suspend fun RunAnywhere.ragQuery(options: RAGQueryOptions): RAGResult =
    ragQuery(options.question, options)

/** Immediately request cancellation of the active native RAG query. */
suspend fun RunAnywhere.ragCancelQuery() {
    // Do not dispatch this lock-free ABI call to Dispatchers.IO. The blocking
    // query itself runs there, so a saturated pool could queue its own cancel
    // behind the work it needs to interrupt.
    CppBridgeRAG.cancelQuery()
}

/**
 * Makes coroutine cancellation interrupt the synchronous JNI query rather
 * than waiting for the provider to exhaust its output budget first.
 */
internal suspend fun <T> runCancellableNativeRagQuery(
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    query: () -> T,
    cancel: () -> Unit,
): T =
    runCancellableNativeUnaryRequest(
        dispatcher = dispatcher,
        request = query,
        cancel = cancel,
    )

suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RARAGDocument>) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (documents.isEmpty()) return
    ensureServicesReady()
    withContext(Dispatchers.IO) {
        documents.forEach { document ->
            CppBridgeRAG.ingest(document)
        }
    }
}

suspend fun RunAnywhere.ragGetStatistics(): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    return withContext(Dispatchers.IO) {
        CppBridgeRAG.stats()
    }
}
