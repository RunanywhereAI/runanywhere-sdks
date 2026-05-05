/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Retrieval-Augmented Generation (RAG) operations.
 * Delegates all pipeline work to RAGBridge (JNI), publishes events to EventBus.
 *
 * Mirrors Swift RunAnywhere+RAG.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.RAGConfig
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

// MARK: - Pipeline Lifecycle

/**
 * Create the RAG pipeline with the given configuration.
 *
 * Must be called before ingesting documents or running queries.
 *
 * @param config RAG pipeline configuration (model paths, tuning parameters)
 * @throws IllegalStateException if pipeline creation fails
 */
expect suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration)

/**
 * Create the RAG pipeline from a generated solution RAG config.
 *
 * D-6: Commons now owns model-id -> path resolution. This helper simply
 * translates the solution-level [RAGConfig] fields onto [RAGConfiguration]
 * (which also carries model ids) and hands it to the native session ABI.
 */
suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfig) {
    val embeddingModelId =
        config.embed_model_id.takeIf { it.isNotBlank() }
            ?: throw SDKException.invalidConfiguration("RAGConfig.embed_model_id is required")
    val llmModelId =
        config.llm_model_id.takeIf { it.isNotBlank() }
            ?: throw SDKException.invalidConfiguration("RAGConfig.llm_model_id is required")

    ragCreatePipeline(
        RAGConfiguration(
            embedding_model_id = embeddingModelId,
            llm_model_id = llmModelId,
            reranker_model_id = config.rerank_model_id.takeIf { it.isNotBlank() },
            top_k = config.retrieve_k.takeIf { it > 0 } ?: config.rerank_top.takeIf { it > 0 } ?: 0,
            prompt_template = config.prompt_template.takeIf { it.isNotBlank() },
            index_path = config.vector_store_path.takeIf { it.isNotBlank() },
            persist_index = config.vector_store_path.isNotBlank(),
            rerank_results = config.rerank_model_id.isNotBlank(),
        ),
    )
}

/**
 * Destroy the RAG pipeline and release all resources.
 */
expect suspend fun RunAnywhere.ragDestroyPipeline()

// MARK: - Document Ingestion

/**
 * Ingest a text document into the RAG pipeline.
 *
 * The document is split into overlapping chunks, each chunk is embedded
 * and indexed for vector search.
 *
 * @param text Plain text content of the document
 * @param metadataJson Optional JSON string attached to all chunks from this document
 * @throws IllegalStateException if the pipeline is not created or ingestion fails
 */
expect suspend fun RunAnywhere.ragIngest(text: String, metadataJson: String? = null)

/**
 * Clear all previously ingested documents from the pipeline.
 *
 * @throws IllegalStateException if the pipeline is not created
 */
expect suspend fun RunAnywhere.ragClearDocuments()

/**
 * Get the current number of indexed document chunks in the pipeline.
 * Returns 0 if pipeline has not been created.
 *
 * Per §9 of CANONICAL_API.md this is a function (ragGetDocumentCount()),
 * not a property, to match the cross-SDK naming convention.
 */
expect suspend fun RunAnywhere.ragGetDocumentCount(): Int

// MARK: - Query

/**
 * Query the RAG pipeline with a natural-language question.
 *
 * Retrieves the most relevant chunks from the vector index and uses the
 * on-device LLM to generate a grounded answer.
 *
 * @param question The user's question
 * @param options Optional query parameters (temperature, max tokens, etc.).
 *                Pass null to use defaults derived from the question.
 * @return A RAGResult containing the generated answer and retrieved chunks
 * @throws IllegalStateException if the pipeline is not created or the query fails
 */
expect suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions? = null,
): RAGResult

/**
 * Ingest a batch of documents into the RAG pipeline.
 *
 * @param documents List of documents to ingest
 * @throws IllegalStateException if the pipeline is not created or ingestion fails
 */
expect suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RAGDocument>)

/**
 * Get statistics for the current RAG pipeline.
 *
 * @return RAGStatistics with chunk count, last query timing, etc.
 * @throws IllegalStateException if the pipeline is not created
 */
expect suspend fun RunAnywhere.ragGetStatistics(): RAGStatistics

// D-6: resolveRAGConfiguration deleted.  Commons now owns model-id ->
// path resolution, so the Kotlin SDK no longer re-implements lookup +
// descriptor-resolved primary path computation + embeddingConfigJson
// assembly.
