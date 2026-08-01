/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.rag` and the session it opens.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGStreamEventKind
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAG
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.NativeUnaryRequestCoordinator
import com.runanywhere.sdk.public.extensions.runCancellableNativeUnaryRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

private val ragLogger = SDKLogger.rag

/** The ONNX plugin supplies the embedding ops RAG needs; load it before the first session. */
private val ragBackendLoaded = AtomicBoolean(false)

private fun ensureRagBackendLoaded() {
    if (!ragBackendLoaded.compareAndSet(false, true)) return
    try {
        System.loadLibrary("rac_backend_onnx")
    } catch (error: UnsatisfiedLinkError) {
        ragLogger.warning("rac_backend_onnx not present: ${error.message}")
    }
}

/**
 * One retrieval-augmented corpus, independent of every other open session.
 *
 * Open it with [RagNamespace.open] and [close] it when done.
 */
public class RagSession internal constructor(
    handle: Long,
    private val config: RagConfig,
    private val llmModelId: String?,
) {
    private val requests = NativeUnaryRequestCoordinator()
    private val nativeHandle = AtomicLong(handle)

    /**
     * Index [document] into this session's corpus.
     *
     * @throws SDKException when the session is closed or indexing fails.
     */
    public suspend fun ingest(document: RagDocument) {
        val live = requireHandle()
        requests.withExclusiveOperation { CppBridgeRAG.ingestOn(live, document.toProto()) }
    }

    /**
     * Index every document in [documents].
     *
     * @throws SDKException when the session is closed or indexing fails.
     */
    public suspend fun ingest(documents: List<RagDocument>) {
        if (documents.isEmpty()) return
        val live = requireHandle()
        requests.withExclusiveOperation {
            documents.forEach { CppBridgeRAG.ingestOn(live, it.toProto()) }
        }
    }

    /**
     * Retrieve the chunks most similar to [query] without generating an answer.
     *
     * Commons has no retrieval-only verb, so this opens a streaming query and
     * stops it as soon as the grounding chunks arrive — no answer tokens are
     * produced.
     *
     * @throws SDKException when the session is closed or retrieval fails.
     */
    public suspend fun search(query: String, topK: Int? = null): List<Match> {
        val live = requireHandle()
        val request =
            CppBridgeRAG.prepareQuery(ragQueryOptions(query, config, null, topK, stream = true))
        val matches = mutableListOf<Match>()
        runCancellableNativeUnaryRequest(
            coordinator = requests,
            request = { requestId ->
                CppBridgeRAG.queryStreamOn(live, requestId, request) { event ->
                    when (event.kind) {
                        RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED -> {
                            event.chunk?.let { matches += it.toMatch() }
                            true
                        }
                        RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CONTEXT_READY,
                        RAGStreamEventKind.RAG_STREAM_EVENT_KIND_TOKEN,
                        -> false
                        RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED -> {
                            if (matches.isEmpty()) {
                                event.result?.retrieved_chunks?.forEach { matches += it.toMatch() }
                            }
                            false
                        }
                        RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR ->
                            throw SDKException.operation(
                                event.error?.message?.takeIf { it.isNotBlank() } ?: "RAG search failed",
                            )
                        else -> true
                    }
                }
            },
            cancel = { requestId -> CppBridgeRAG.cancelRequestOn(live, requestId) },
        )
        return matches.take(topK ?: config.topK)
    }

    /**
     * Answer [question] from this session's corpus.
     *
     * @throws SDKException when the session is retrieval-only or generation fails.
     */
    public suspend fun query(question: String, options: LlmOptions? = null): RagResult {
        val live = requireHandle()
        requireGenerationModel()
        val request =
            CppBridgeRAG.prepareQuery(ragQueryOptions(question, config, options, null, stream = false))
        val result =
            runCancellableNativeUnaryRequest(
                coordinator = requests,
                request = { requestId -> CppBridgeRAG.queryOn(live, requestId, request) },
                cancel = { requestId -> CppBridgeRAG.cancelRequestOn(live, requestId) },
            )
        result.error?.let { throw SDKException(it) }
        return result.toRagResult(llmModelId.orEmpty())
    }

    /**
     * Stream an answer to [question], emitting the grounding chunks first.
     *
     * @throws SDKException when the session is retrieval-only or generation fails.
     */
    public fun queryStream(question: String, options: LlmOptions? = null): Flow<RagEvent> =
        callbackFlow {
            val live = requireHandle()
            requireGenerationModel()
            val request =
                CppBridgeRAG.prepareQuery(ragQueryOptions(question, config, options, null, stream = true))
            val retrieved = mutableListOf<Match>()
            val worker =
                launch {
                    try {
                        runCancellableNativeUnaryRequest(
                            coordinator = requests,
                            request = { requestId ->
                                CppBridgeRAG.queryStreamOn(live, requestId, request) { event ->
                                    dispatchRagEvent(event, retrieved) { trySend(it).isSuccess }
                                }
                            },
                            cancel = { requestId -> CppBridgeRAG.cancelRequestOn(live, requestId) },
                        )
                        close()
                    } catch (error: Throwable) {
                        close(error)
                    }
                }
            awaitClose { worker.cancel() }
        }

    /**
     * Document, chunk, and index-size counts for this session.
     *
     * @throws SDKException when the session is closed.
     */
    public suspend fun stats(): RagStats {
        val live = requireHandle()
        return requests.withExclusiveOperation { CppBridgeRAG.statsOn(live) }.toRagStats()
    }

    /**
     * Drop every indexed document, keeping the session open.
     *
     * @throws SDKException when the session is closed.
     */
    public suspend fun clear() {
        val live = requireHandle()
        requests.withExclusiveOperation { CppBridgeRAG.clearOn(live) }
    }

    /** Release this session's native resources. Safe to call twice. */
    public suspend fun close() {
        val live = nativeHandle.getAndSet(0L)
        if (live == 0L) return
        requests.withExclusiveOperation(interruptActiveRequest = true) {
            CppBridgeRAG.closeSession(live)
        }
    }

    private fun requireHandle(): Long =
        nativeHandle.get().takeIf { it != 0L }
            ?: throw SDKException.invalidState("RAG session is closed")

    private fun requireGenerationModel() {
        if (llmModelId.isNullOrBlank()) {
            throw SDKException.invalidState("This RAG session is retrieval-only; open it with an llmModel to generate")
        }
    }

    private fun dispatchRagEvent(
        event: ai.runanywhere.proto.v1.RAGStreamEvent,
        retrieved: MutableList<Match>,
        emit: (RagEvent) -> Boolean,
    ): Boolean =
        when (event.kind) {
            RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED -> {
                event.chunk?.let { retrieved += it.toMatch() }
                true
            }
            RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CONTEXT_READY ->
                emit(RagEvent.Retrieved(retrieved.toList()))
            RAGStreamEventKind.RAG_STREAM_EVENT_KIND_TOKEN ->
                if (event.token.isEmpty()) true else emit(RagEvent.Token(event.token, TokenKind.TEXT))
            RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED -> {
                val result = event.result
                if (result != null) emit(RagEvent.Completed(result.toRagResult(llmModelId.orEmpty())))
                false
            }
            RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR ->
                throw SDKException.operation(
                    event.error?.message?.takeIf { it.isNotBlank() } ?: "RAG query failed",
                )
            else -> true
        }
}

/**
 * Retrieval-augmented generation over a corpus you own.
 *
 * ```kotlin
 * val session = RunAnywhere.rag.open(ModelRef("all-minilm-l6-v2"), ModelRef("qwen3-0.6b"))
 * session.ingest(RagDocument("RunAnywhere runs models on-device."))
 * ```
 */
public class RagNamespace internal constructor() {
    /**
     * Open a session over [embeddingModel], optionally able to generate with [llmModel].
     *
     * Both models are downloaded and loaded here; pass a null [llmModel] for a
     * retrieval-only session.
     *
     * @throws SDKException when either model cannot be loaded.
     */
    public suspend fun open(
        embeddingModel: ModelRef,
        llmModel: ModelRef? = null,
        config: RagConfig? = null,
    ): RagSession {
        RunAnywhere.ensureServicesReady()
        ensureRagBackendLoaded()
        val resolved = config.orDefault()
        ensureModelLoaded(embeddingModel.id, ModelCategory.MODEL_CATEGORY_EMBEDDING)
        llmModel?.let { ensureModelLoaded(it.id, ModelCategory.MODEL_CATEGORY_LANGUAGE) }
        val handle =
            withContext(Dispatchers.IO) {
                CppBridgeRAG.openSession(
                    resolved.toProto(
                        embeddingModelId = embeddingModel.id,
                        llmModelId = llmModel?.id.orEmpty(),
                    ),
                )
            }
        return RagSession(handle, resolved, llmModel?.id)
    }
}

private fun RagDocument.toProto(): RAGDocument =
    RAGDocument(
        text = text,
        metadata = metadata,
        source_uri = sourceUri,
    )
