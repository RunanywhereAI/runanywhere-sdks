/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RAG Native Bridge
 *
 * Self-contained JNI bridge for the RAG backend module.
 * This mirrors the Swift RAGBackend XCFramework architecture.
 *
 * The native library (librac_backend_rag_jni.so) contains:
 * - rac_backend_rag_register()
 * - rac_backend_rag_unregister()
 * - rac_rag_pipeline_* (pipeline operations)
 */

package com.runanywhere.sdk.rag

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Native bridge for RAG backend registration and pipeline operations.
 *
 * This object handles loading the RAG-specific JNI library and provides
 * JNI methods for backend registration with the C++ service registry,
 * as well as all RAG pipeline operations (create, query, add documents, etc.).
 *
 * Architecture:
 * - librac_backend_rag_jni.so - RAG JNI (this bridge)
 * - Links to librac_backend_rag.so - RAG C++ backend
 * - Links to librac_commons.so - Commons library with service registry
 */
object RAGBridge {
    private val logger = SDKLogger.rag

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Ensure the RAG JNI library is loaded.
     *
     * Loads librac_backend_rag_jni.so and its dependencies:
     * - librac_backend_rag.so (RAG C++ backend)
     * - librac_commons.so (commons library - must be loaded first)
     *
     * @return true if loaded successfully, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            logger.info("Loading RAG native library...")

            try {
                // The main SDK's librunanywhere_jni.so must be loaded first
                // (provides librac_commons.so with service registry).
                // The RAG JNI provides backend registration and pipeline functions.
                System.loadLibrary("rac_backend_rag_jni")
                nativeLibraryLoaded = true
                logger.info("RAG native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load RAG native library: ${e.message}", throwable = e)
                return false
            } catch (e: Exception) {
                logger.error("Unexpected error loading RAG native library: ${e.message}", throwable = e)
                return false
            }
        }
    }

    /**
     * Check if the native library is loaded.
     */
    val isLoaded: Boolean
        get() = nativeLibraryLoaded

    // ==========================================================================
    // Registration JNI Methods
    // ==========================================================================

    /**
     * Register the RAG backend with the C++ service registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeRegister(): Int

    /**
     * Unregister the RAG backend from the C++ service registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeUnregister(): Int

    /**
     * Check if the RAG backend is registered.
     *
     * @return true if registered
     */
    @JvmStatic
    external fun nativeIsRegistered(): Boolean

    /**
     * Get the RAG module version.
     *
     * @return Version string
     */
    @JvmStatic
    external fun nativeGetVersion(): String

    // ==========================================================================
    // Pipeline JNI Methods (rac_rag_pipeline.h)
    // ==========================================================================

    /**
     * Create a new RAG pipeline instance.
     *
     * @param embeddingModelPath Path to the ONNX embedding model
     * @param llmModelPath Path to the LlamaCPP LLM model
     * @param embeddingDimension Dimension of embedding vectors
     * @param topK Number of top-k documents to retrieve
     * @param similarityThreshold Minimum cosine similarity threshold
     * @param maxContextTokens Maximum tokens for context window
     * @param chunkSize Document chunk size in characters
     * @param chunkOverlap Overlap between adjacent chunks
     * @param promptTemplate Optional custom prompt template
     * @param embeddingConfigJson Optional JSON config for embedding model
     * @param llmConfigJson Optional JSON config for LLM model
     * @return Pipeline handle (pointer as Long), 0 on failure
     */
    @JvmStatic
    external fun nativeCreatePipeline(
        embeddingModelPath: String,
        llmModelPath: String?, // Nullable to match C++ signature; null enables embedding-only mode (no LLM generation)
        embeddingDimension: Int,
        topK: Int,
        similarityThreshold: Float,
        maxContextTokens: Int,
        chunkSize: Int,
        chunkOverlap: Int,
        promptTemplate: String?,
        embeddingConfigJson: String?,
        llmConfigJson: String?,
    ): Long

    /**
     * Destroy a RAG pipeline instance and free all resources.
     *
     * @param pipelineHandle Pipeline handle returned by nativeCreatePipeline
     */
    @JvmStatic
    external fun nativeDestroyPipeline(pipelineHandle: Long)

    /**
     * Add a document to the pipeline's vector store.
     *
     * @param pipelineHandle Pipeline handle
     * @param text Document text content
     * @param metadataJson Optional JSON metadata for the document
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeAddDocument(
        pipelineHandle: Long,
        text: String,
        metadataJson: String?,
    ): Int

    /**
     * Query the pipeline with a natural language question.
     *
     * @param pipelineHandle Pipeline handle
     * @param question Natural language question
     * @param systemPrompt Optional system prompt override
     * @param maxTokens Maximum tokens to generate
     * @param temperature Sampling temperature
     * @param topP Top-p sampling parameter
     * @param topK Top-k sampling parameter
     * @return JSON-serialized RAGResult, empty string on failure
     */
    @JvmStatic
    external fun nativeQuery(
        pipelineHandle: Long,
        question: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
    ): String

    /**
     * Clear all documents from the pipeline's vector store.
     *
     * @param pipelineHandle Pipeline handle
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeClearDocuments(pipelineHandle: Long): Int

    /**
     * Get the number of documents currently in the pipeline's vector store.
     *
     * @param pipelineHandle Pipeline handle
     * @return Document count, or -1 on failure
     */
    @JvmStatic
    external fun nativeGetDocumentCount(pipelineHandle: Long): Int
}
