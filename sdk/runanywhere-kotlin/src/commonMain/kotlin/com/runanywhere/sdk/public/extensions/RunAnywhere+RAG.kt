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

import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.RAGConfig
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.resolvedPrimaryModelPath
import com.runanywhere.sdk.public.extensions.Models.resolvedVocabularyPath

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
 * The generated [RAGConfig] carries model ids. The current native RAG session
 * ABI still consumes [RAGConfiguration], so this helper resolves those ids
 * through the model registry and generated model file descriptors before
 * creating the pipeline.
 */
suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfig) {
    ragCreatePipeline(resolveRAGConfiguration(config))
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

private suspend fun RunAnywhere.resolveRAGConfiguration(config: RAGConfig): RAGConfiguration {
    val embeddingModelId =
        config.embed_model_id.takeIf { it.isNotBlank() }
            ?: throw SDKException.invalidConfiguration("RAGConfig.embed_model_id is required")
    val llmModelId =
        config.llm_model_id.takeIf { it.isNotBlank() }
            ?: throw SDKException.invalidConfiguration("RAGConfig.llm_model_id is required")

    val embeddingModel =
        model(embeddingModelId)
            ?: throw SDKException.modelNotFound(embeddingModelId)
    val llmModel =
        model(llmModelId)
            ?: throw SDKException.modelNotFound(llmModelId)
    val rerankerModel =
        config.rerank_model_id
            .takeIf { it.isNotBlank() }
            ?.let { rerankerId ->
                model(rerankerId)
                    ?: throw SDKException.modelNotFound(rerankerId)
            }

    return RAGConfiguration(
        embedding_model_path =
            embeddingModel.resolvedPrimaryPathOrThrow(
                modelId = embeddingModelId,
                roleDescription = "embedding model",
            ),
        llm_model_path =
            llmModel.resolvedPrimaryPathOrThrow(
                modelId = llmModelId,
                roleDescription = "LLM model",
            ),
        top_k = config.retrieve_k.takeIf { it > 0 } ?: config.rerank_top.takeIf { it > 0 } ?: 0,
        prompt_template = config.prompt_template.takeIf { it.isNotBlank() },
        embedding_config_json = embeddingModel.ragEmbeddingConfigJson(),
        index_path = config.vector_store_path.takeIf { it.isNotBlank() },
        persist_index = config.vector_store_path.isNotBlank(),
        rerank_results = rerankerModel != null,
        reranker_model_path =
            rerankerModel?.resolvedPrimaryPathOrThrow(
                modelId = config.rerank_model_id,
                roleDescription = "reranker model",
            ),
    )
}

private fun ModelInfo.resolvedPrimaryPathOrThrow(
    modelId: String,
    roleDescription: String,
): String =
    resolvedPrimaryModelPath()
        ?: throw SDKException.model(
            "RAG $roleDescription '$modelId' is registered but has no descriptor-resolved primary model path",
        )

private fun ModelInfo.ragEmbeddingConfigJson(): String? =
    resolvedVocabularyPath()
        ?.let { vocabPath -> """{"vocab_path":${vocabPath.toJsonStringLiteral()}}""" }

private fun String.toJsonStringLiteral(): String =
    buildString(length + 2) {
        append('"')
        for (char in this@toJsonStringLiteral) {
            when (char) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> {
                    if (char.code < JSON_CONTROL_CHAR_LIMIT) {
                        append("\\u")
                        append(char.code.toString(16).padStart(JSON_HEX_DIGITS, '0'))
                    } else {
                        append(char)
                    }
                }
            }
        }
        append('"')
    }

private const val JSON_CONTROL_CHAR_LIMIT = 0x20
private const val JSON_HEX_DIGITS = 4
