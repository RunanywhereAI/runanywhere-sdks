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

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.RAG.RAGConfiguration
import com.runanywhere.sdk.public.extensions.RAG.RAGQueryOptions
import com.runanywhere.sdk.public.extensions.RAG.RAGResult

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
 * The current number of indexed document chunks in the pipeline.
 * Returns 0 if pipeline has not been created.
 */
expect val RunAnywhere.ragDocumentCount: Int

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
