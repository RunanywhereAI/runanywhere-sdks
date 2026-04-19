/**
 * @file flutter_rag_bridge.h
 * @brief Flutter RAG Bridge - C API for Dart FFI
 *
 * Thin C wrapper over the rac_rag_pipeline C API, exposing JSON-based
 * functions callable from Dart FFI. Mirrors React Native's RAGBridge.cpp
 * pattern but with plain C function exports instead of JSI/Nitrogen.
 *
 * All functions use JSON strings for complex data exchange, eliminating
 * the need for FFI struct marshalling in Dart.
 */

#ifndef FLUTTER_RAG_BRIDGE_H
#define FLUTTER_RAG_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Create a RAG pipeline from a JSON configuration string.
 * Auto-registers the RAG module if not already registered.
 *
 * JSON keys: embeddingModelPath, llmModelPath, embeddingDimension,
 * topK, similarityThreshold, maxContextTokens, chunkSize, chunkOverlap,
 * promptTemplate, embeddingConfigJSON, llmConfigJSON
 *
 * Includes model path resolution:
 * - LLM directories are scanned for .gguf files
 * - Embedding vocab.txt is auto-discovered
 *
 * @param config_json JSON string with pipeline configuration
 * @return 0 on success, negative error code on failure
 */
int32_t flutter_rag_create_pipeline_json(const char* config_json);

/**
 * Destroy the current RAG pipeline and release resources.
 * @return 0 on success, -1 if no pipeline exists
 */
int32_t flutter_rag_destroy_pipeline(void);

/**
 * Add a single document to the pipeline.
 *
 * @param text Document text content
 * @param metadata_json Optional JSON metadata (can be NULL)
 * @return 0 on success, negative error code on failure
 */
int32_t flutter_rag_add_document(const char* text, const char* metadata_json);

/**
 * Add multiple documents in batch from a JSON array.
 *
 * JSON format: [{"text": "...", "metadataJson": "..."}, ...]
 *
 * @param documents_json JSON array of document objects
 * @return 0 on success, negative error code on failure
 */
int32_t flutter_rag_add_documents_batch_json(const char* documents_json);

/**
 * Query the RAG pipeline with JSON parameters.
 * Returns a JSON result string that the caller must free with flutter_rag_free_string.
 *
 * Query JSON keys: question, systemPrompt, maxTokens, temperature, topP, topK
 *
 * Result JSON keys: answer, contextUsed, retrievalTimeMs, generationTimeMs,
 * totalTimeMs, retrievedChunks (array of {chunkId, text, similarityScore, metadataJson})
 *
 * @param query_json JSON string with query parameters
 * @return JSON result string (caller must free with flutter_rag_free_string), or NULL on failure
 */
const char* flutter_rag_query_json(const char* query_json);

/**
 * Clear all documents from the pipeline.
 * @return 0 on success, negative error code on failure
 */
int32_t flutter_rag_clear_documents(void);

/**
 * Get the number of indexed document chunks.
 * @return Document count, or 0 if no pipeline exists
 */
int32_t flutter_rag_get_document_count(void);

/**
 * Get pipeline statistics as a JSON string.
 * Caller must free the returned string with flutter_rag_free_string.
 *
 * @return JSON statistics string, or "{}" if unavailable
 */
const char* flutter_rag_get_statistics_json(void);

/**
 * Free a string returned by flutter_rag_query_json or flutter_rag_get_statistics_json.
 * @param str String to free (can be NULL)
 */
void flutter_rag_free_string(const char* str);

/**
 * Get the last error detail from pipeline creation or other operations.
 * Caller must free the returned string with flutter_rag_free_string.
 *
 * @return Error detail string, or NULL if no error
 */
const char* flutter_rag_get_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* FLUTTER_RAG_BRIDGE_H */
