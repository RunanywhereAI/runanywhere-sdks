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

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RARAGConfiguration
import com.runanywhere.sdk.public.types.RARAGDocument
import com.runanywhere.sdk.public.types.RARAGStatistics

// MARK: - Pipeline Lifecycle

/**
 * Build a generated RAG configuration from registry models by delegating
 * artifact resolution to commons (model-id → path) — Swift parity for
 * `RunAnywhere.ragResolvedConfiguration(embeddingModel:llmModel:baseConfiguration:)`.
 */
expect suspend fun RunAnywhere.ragResolvedConfiguration(
    embeddingModel: RAModelInfo,
    llmModel: RAModelInfo,
    baseConfiguration: RARAGConfiguration = RAGConfiguration.defaults(),
): RARAGConfiguration

/**
 * Create the RAG pipeline with the given configuration.
 *
 * Must be called before ingesting documents or running queries.
 *
 * @param config RAG pipeline configuration (model paths, tuning parameters)
 * @throws IllegalStateException if pipeline creation fails
 */
expect suspend fun RunAnywhere.ragCreatePipeline(config: RARAGConfiguration)

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
 * @param metadataJSON Optional JSON string attached to all chunks from this document.
 *                     Acronym-preserving spelling matches the Swift signature
 *                     `RunAnywhere.ragIngest(text:metadataJSON:)`.
 * @throws IllegalStateException if the pipeline is not created or ingestion fails
 */
expect suspend fun RunAnywhere.ragIngest(text: String, metadataJSON: String? = null)

/**
 * Ingest a generated-proto document through the C++ RAG ABI.
 *
 * Mirrors Swift `ragIngest(_ document: RARAGDocument)`.
 */
expect suspend fun RunAnywhere.ragIngest(document: RARAGDocument): RARAGStatistics

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

/**
 * Ingest a batch of documents into the RAG pipeline.
 *
 * Returns the latest [RAGStatistics] reported by the C++ pipeline after
 * the final document has been ingested. Mirrors Swift
 * `ragAddDocumentsBatch(documents:)`.
 *
 * @throws IllegalStateException if the pipeline is not created or ingestion fails.
 */
expect suspend fun RunAnywhere.ragAddDocumentsBatch(documents: List<RARAGDocument>): RARAGStatistics

/**
 * Get statistics for the current RAG pipeline.
 *
 * Mirrors Swift `ragGetStatistics()`.
 *
 * @return RAGStatistics with chunk count, last query timing, etc.
 * @throws IllegalStateException if the pipeline is not created
 */
expect suspend fun RunAnywhere.ragGetStatistics(): RARAGStatistics

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

// D-6: resolveRAGConfiguration deleted.  Commons now owns model-id ->
// path resolution, so the Kotlin SDK no longer re-implements lookup +
// descriptor-resolved primary path computation + embeddingConfigJson
// assembly.
