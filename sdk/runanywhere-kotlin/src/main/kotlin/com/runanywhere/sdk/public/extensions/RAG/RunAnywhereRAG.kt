/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Retrieval-Augmented Generation (RAG) operations.
 * Delegates all pipeline work to RAGBridge (JNI), publishes events to EventBus.
 *
 * Uses the canonical generated RAG proto types directly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStreamEvent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAG
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.convenience.defaults
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
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

// MARK: - Pipeline Lifecycle

// MARK: - Document Ingestion

// MARK: - Query

// The ONNX engine plugin provides the embedding operations required for RAG.
// Loading it triggers its native registration constructor before CppBridgeRAG
// creates the pipeline.
private val ragNativeLibsLoaded = AtomicBoolean(false)
private val ragNativeRequests = NativeUnaryRequestCoordinator()

private fun ensureRagNativeLibsLoaded() {
    if (!ragNativeLibsLoaded.compareAndSet(false, true)) return
    val logger = SDKLogger.rag
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
    // Creation replaces any existing bridge session. Enqueue the lifecycle
    // owner before cancelling the current query so no successor can capture
    // the session this operation is about to replace.
    ragNativeRequests.withExclusiveOperation(interruptActiveRequest = true) {
        CppBridgeRAG.create(config)
    }
}

/** Destroy the RAG pipeline and release all resources. */
suspend fun RunAnywhere.ragDestroyPipeline() {
    ragNativeRequests.withExclusiveOperation(interruptActiveRequest = true) {
        CppBridgeRAG.destroy()
    }
}

suspend fun RunAnywhere.ragIngest(document: RARAGDocument): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    return ragNativeRequests.withExclusiveOperation {
        CppBridgeRAG.ingest(document)
    }
}

suspend fun RunAnywhere.ragClearDocuments() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    ragNativeRequests.withExclusiveOperation {
        CppBridgeRAG.clear()
    }
}

/**
 * Get the number of indexed document chunks in the pipeline as a function call.
 *
 * @return Number of indexed chunks in the pipeline, or 0 if not initialized.
 */
suspend fun RunAnywhere.ragGetDocumentCount(): Int =
    ragNativeRequests.withExclusiveOperation {
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
    val nativeRequest = CppBridgeRAG.prepareQuery(queryOptions)
    return runCancellableNativeRagQuery(
        query = { requestId -> CppBridgeRAG.queryRequest(requestId, nativeRequest) },
        cancel = CppBridgeRAG::cancelQueryRequest,
    )
}

suspend fun RunAnywhere.ragQuery(options: RAGQueryOptions): RAGResult =
    ragQuery(options.question, options)

/**
 * Streaming RAG query. Emits a [RAGStreamEvent] per generated token
 * (kind = TOKEN) as the answer is produced, then a terminal COMPLETED event
 * carrying the full [RAGResult] (answer + retrieved chunks), or an ERROR event.
 *
 * Because tokens surface as they generate, callers render progress live and do
 * NOT need a wall-clock timeout around the call. Cancelling collection stops the
 * native query request-scoped (via racRagCancelRequestProto), so concurrent
 * collectors and unary queries serialize instead of cancelling each other.
 */
fun RunAnywhere.ragQueryStream(
    question: String,
    options: RAGQueryOptions? = null,
): Flow<RAGStreamEvent> =
    callbackFlow {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        ensureServicesReady()
        val queryOptions =
            (options ?: RAGQueryOptions.defaults(question)).let {
                if (it.question.isEmpty()) it.copy(question = question) else it
            }
        val nativeRequest = CppBridgeRAG.prepareQuery(queryOptions)
        // Run the blocking native stream through the RAG request coordinator so
        // cancellation targets this exact request (via cancelQueryRequest) rather
        // than any query on the session. trySend returning false stops the native
        // producer through backpressure; collecting cancellation cancels the worker,
        // which the coordinator turns into the request-scoped native cancel.
        val worker =
            launch {
                try {
                    runCancellableNativeRagQuery(
                        query = { requestId ->
                            CppBridgeRAG.queryStreamRequest(requestId, nativeRequest) { event ->
                                trySend(event).isSuccess
                            }
                        },
                        cancel = CppBridgeRAG::cancelQueryRequest,
                    )
                    close()
                } catch (t: Throwable) {
                    close(t)
                }
            }
        awaitClose { worker.cancel() }
    }

fun RunAnywhere.ragQueryStream(options: RAGQueryOptions): Flow<RAGStreamEvent> =
    ragQueryStream(options.question, options)

/** Immediately request cancellation of the active native RAG query. */
suspend fun RunAnywhere.ragCancelQuery() {
    // The coordinator routes the potentially blocking request-scoped JNI
    // relay through its dedicated elastic cancellation dispatcher, keeping it
    // off Main and independent of a caller-supplied inference dispatcher.
    ragNativeRequests.cancelActive()
}

/**
 * Makes coroutine cancellation interrupt the synchronous JNI query rather
 * than waiting for the provider to exhaust its output budget first.
 */
internal suspend fun <T> runCancellableNativeRagQuery(
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    coordinator: NativeUnaryRequestCoordinator = ragNativeRequests,
    query: (requestId: Long) -> T,
    cancel: (requestId: Long) -> Unit,
): T =
    runCancellableNativeUnaryRequest(
        coordinator = coordinator,
        dispatcher = dispatcher,
        request = query,
        cancel = cancel,
    )

suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RARAGDocument>) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (documents.isEmpty()) return
    ensureServicesReady()
    ragNativeRequests.withExclusiveOperation {
        documents.forEach { document ->
            CppBridgeRAG.ingest(document)
        }
    }
}

suspend fun RunAnywhere.ragGetStatistics(): RARAGStatistics {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
    return ragNativeRequests.withExclusiveOperation {
        CppBridgeRAG.stats()
    }
}
