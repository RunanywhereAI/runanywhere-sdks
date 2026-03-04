/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for Retrieval-Augmented Generation.
 * These are thin data class wrappers — no C bridge methods (those go in jvmAndroidMain actual).
 *
 * Mirrors Swift RAGTypes.swift exactly (field names and defaults).
 */

package com.runanywhere.sdk.public.extensions.RAG

// MARK: - RAG Configuration

/**
 * Configuration for a RAG pipeline.
 * Mirrors Swift RAGConfiguration exactly.
 */
data class RAGConfiguration(
    /** Path to the embedding model (ONNX) */
    val embeddingModelPath: String,

    /** Path to the LLM model (GGUF) */
    val llmModelPath: String,

    /** Embedding vector dimension (default: 384 for all-MiniLM-L6-v2) */
    val embeddingDimension: Int = 384,

    /** Number of top chunks to retrieve per query (default: 3) */
    val topK: Int = 3,

    /** Minimum cosine similarity threshold 0.0–1.0 (default: 0.15) */
    val similarityThreshold: Float = 0.15f,

    /** Maximum tokens to use for context sent to the LLM (default: 2048) */
    val maxContextTokens: Int = 2048,

    /** Tokens per chunk when splitting documents (default: 512) */
    val chunkSize: Int = 512,

    /** Overlap tokens between consecutive chunks (default: 50) */
    val chunkOverlap: Int = 50,

    /** Prompt template with `{context}` and `{query}` placeholders. Null uses the C default. */
    val promptTemplate: String? = null,

    /** Optional configuration JSON for the embedding model */
    val embeddingConfigJson: String? = null,

    /** Optional configuration JSON for the LLM model */
    val llmConfigJson: String? = null,
)

// MARK: - RAG Query Options

/**
 * Options for querying the RAG pipeline.
 * Mirrors Swift RAGQueryOptions exactly.
 */
data class RAGQueryOptions(
    /** The user question to answer */
    val question: String,

    /** Optional system prompt override. Null uses the pipeline default. */
    val systemPrompt: String? = null,

    /** Maximum tokens to generate in the answer (default: 512) */
    val maxTokens: Int = 512,

    /** Sampling temperature (default: 0.7) */
    val temperature: Float = 0.7f,

    /** Nucleus sampling parameter (default: 0.9) */
    val topP: Float = 0.9f,

    /** Top-k sampling (default: 40) */
    val topK: Int = 40,
)

// MARK: - RAG Search Result

/**
 * A single retrieved document chunk with similarity score.
 * Mirrors Swift RAGSearchResult exactly.
 */
data class RAGSearchResult(
    /** Unique identifier of the chunk */
    val chunkId: String,

    /** Text content of the chunk */
    val text: String,

    /** Cosine similarity score (0.0–1.0) */
    val similarityScore: Float,

    /** Optional metadata JSON associated with the chunk */
    val metadataJson: String? = null,
)

// MARK: - RAG Result

/**
 * The result of a RAG query — includes the generated answer and retrieved chunks.
 * Mirrors Swift RAGResult exactly.
 */
data class RAGResult(
    /** The LLM-generated answer grounded in the retrieved context */
    val answer: String,

    /** Document chunks retrieved during vector search */
    val retrievedChunks: List<RAGSearchResult>,

    /** Full context string passed to the LLM (may be null for short contexts) */
    val contextUsed: String? = null,

    /** Time spent in the retrieval phase (milliseconds) */
    val retrievalTimeMs: Double,

    /** Time spent in the LLM generation phase (milliseconds) */
    val generationTimeMs: Double,

    /** Total end-to-end query time (milliseconds) */
    val totalTimeMs: Double,
)
