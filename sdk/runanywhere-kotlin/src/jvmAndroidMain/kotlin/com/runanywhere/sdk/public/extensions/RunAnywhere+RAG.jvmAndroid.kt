/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Retrieval-Augmented Generation (RAG) operations.
 * Dispatches to RAG JNI (librac_backend_rag_jni) which calls the C++ rac_rag_* backend.
 *
 * Mirrors Swift RunAnywhere+RAG.swift + CppBridge.RAG exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.rag.RAGBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.RAGEvent
import com.runanywhere.sdk.public.extensions.RAG.RAGConfiguration
import com.runanywhere.sdk.public.extensions.RAG.RAGQueryOptions
import com.runanywhere.sdk.public.extensions.RAG.RAGResult
import com.runanywhere.sdk.public.extensions.RAG.RAGSearchResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// MARK: - File-level pipeline handle (mirrors Swift CppBridge.RAG actor's pipeline pointer)

@Volatile
private var pipelineHandle: Long = 0L

// MARK: - Internal deserialization types (JSON from C++ nativeQuery)

@Serializable
private data class RawRAGSearchResult(
    val chunk_id: String = "",
    val text: String = "",
    val similarity_score: Float = 0f,
    val metadata_json: String? = null,
)

@Serializable
private data class RawRAGResult(
    val answer: String = "",
    val retrieved_chunks: List<RawRAGSearchResult> = emptyList(),
    val context_used: String? = null,
    val retrieval_time_ms: Double = 0.0,
    val generation_time_ms: Double = 0.0,
    val total_time_ms: Double = 0.0,
)

private val ragJson = Json { ignoreUnknownKeys = true }

// MARK: - Pipeline Lifecycle

actual suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration) {
    val handle = withContext(Dispatchers.IO) {
        // 1. Ensure the library is loaded
        if (!RAGBridge.ensureNativeLibraryLoaded()) {
            throw IllegalStateException("Failed to load RAG native libraries.")
        }

        // 2. Ensure the backend is registered with the C++ service locator
        if (!RAGBridge.nativeIsRegistered()) {
            val regResult = RAGBridge.nativeRegister()
            if (regResult != 0) { // 0 is RAC_SUCCESS
                throw IllegalStateException("Failed to register RAG backend. Error code: $regResult")
            }
        }

        // 3. Create the pipeline
        RAGBridge.nativeCreatePipeline(
            embeddingModelPath = config.embeddingModelPath,
            llmModelPath = config.llmModelPath,
            embeddingDimension = config.embeddingDimension,
            topK = config.topK,
            similarityThreshold = config.similarityThreshold,
            maxContextTokens = config.maxContextTokens,
            chunkSize = config.chunkSize,
            chunkOverlap = config.chunkOverlap,
            promptTemplate = config.promptTemplate,
            embeddingConfigJson = config.embeddingConfigJson,
            llmConfigJson = config.llmConfigJson,
        )
    }

    if (handle == 0L) {
        throw IllegalStateException("RAG pipeline creation failed")
    }

    pipelineHandle = handle
    EventBus.publish(RAGEvent.pipelineCreated())
}

actual suspend fun RunAnywhere.ragDestroyPipeline() {
    val handle = pipelineHandle
    if (handle != 0L) {
        withContext(Dispatchers.IO) {
            RAGBridge.nativeDestroyPipeline(handle)
        }
        pipelineHandle = 0L
    }
    EventBus.publish(RAGEvent.pipelineDestroyed())
}

// MARK: - Document Ingestion

actual suspend fun RunAnywhere.ragIngest(text: String, metadataJson: String?) {
    val handle = pipelineHandle
    if (handle == 0L) {
        throw IllegalStateException("RAG pipeline not created — call ragCreatePipeline first")
    }

    EventBus.publish(RAGEvent.ingestionStarted(text.length))
    val startMs = System.currentTimeMillis()

    val (result, chunkCount) = withContext(Dispatchers.IO) {
        val res = RAGBridge.nativeAddDocument(handle, text, metadataJson)
        val count = if (res == 0) RAGBridge.nativeGetDocumentCount(handle) else 0
        res to count
    }

    if (result != 0) {
        throw IllegalStateException("RAG document ingestion failed with error code: $result")
    }

    val durationMs = (System.currentTimeMillis() - startMs).toDouble()
    EventBus.publish(RAGEvent.ingestionComplete(chunkCount, durationMs))
}

actual suspend fun RunAnywhere.ragClearDocuments() {
    val handle = pipelineHandle
    if (handle == 0L) {
        throw IllegalStateException("RAG pipeline not created — call ragCreatePipeline first")
    }
    withContext(Dispatchers.IO) {
        RAGBridge.nativeClearDocuments(handle)
    }
}

// MARK: - Document Count

actual val RunAnywhere.ragDocumentCount: Int
    get() {
        val handle = pipelineHandle
        return if (handle != 0L) RAGBridge.nativeGetDocumentCount(handle) else 0
    }

// MARK: - Query

actual suspend fun RunAnywhere.ragQuery(question: String, options: RAGQueryOptions?): RAGResult {
    val handle = pipelineHandle
    if (handle == 0L) {
        throw IllegalStateException("RAG pipeline not created — call ragCreatePipeline first")
    }

    val queryOptions = options ?: RAGQueryOptions(question = question)
    EventBus.publish(RAGEvent.queryStarted(question))

    val raw = withContext(Dispatchers.IO) {
        val jsonString = RAGBridge.nativeQuery(
            pipelineHandle = handle,
            question = queryOptions.question,
            systemPrompt = queryOptions.systemPrompt,
            maxTokens = queryOptions.maxTokens,
            temperature = queryOptions.temperature,
            topP = queryOptions.topP,
            topK = queryOptions.topK,
        )

        if (jsonString.isBlank()) {
            throw IllegalStateException("RAG query failed — empty response from native backend")
        }

        ragJson.decodeFromString<RawRAGResult>(jsonString)
    }

    val result = RAGResult(
        answer = raw.answer,
        retrievedChunks = raw.retrieved_chunks.map { chunk ->
            RAGSearchResult(
                chunkId = chunk.chunk_id,
                text = chunk.text,
                similarityScore = chunk.similarity_score,
                metadataJson = chunk.metadata_json,
            )
        },
        contextUsed = raw.context_used,
        retrievalTimeMs = raw.retrieval_time_ms,
        generationTimeMs = raw.generation_time_ms,
        totalTimeMs = raw.total_time_ms,
    )

    EventBus.publish(RAGEvent.queryComplete(result))
    return result
}
