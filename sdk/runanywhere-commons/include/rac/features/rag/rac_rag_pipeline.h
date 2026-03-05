/**
 * @file rac_rag_pipeline.h
 * @brief RunAnywhere Commons - RAG Pipeline Public API
 *
 * Retrieval-Augmented Generation pipeline combining:
 * - Document chunking and embedding
 * - Vector search with USearch
 * - LLM generation with context
 */

#ifndef RAC_RAG_PIPELINE_H
#define RAC_RAG_PIPELINE_H

#include "rac/core/rac_types.h"
#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

typedef struct rac_rag_pipeline rac_rag_pipeline_t;

// =============================================================================
// DOCUMENT TYPES
// =============================================================================

/**
 * @brief Document chunk with metadata
 */
typedef struct rac_document_chunk {
    const char* id;              /**< Unique chunk ID */
    const char* text;            /**< Chunk text content */
    const char* metadata_json;   /**< JSON metadata (optional) */
} rac_document_chunk_t;

/**
 * @brief Search result from vector retrieval
 */
typedef struct rac_search_result {
    char* chunk_id;              /**< Chunk ID (caller must free) */
    char* text;                  /**< Chunk text (caller must free) */
    float similarity_score;      /**< Cosine similarity (0.0-1.0) */
    char* metadata_json;         /**< Metadata JSON (caller must free) */
} rac_search_result_t;

// =============================================================================
// RAG CONFIGURATION
// =============================================================================

/**
 * @brief RAG pipeline configuration
 */
typedef struct rac_rag_config {
    /** Path to embedding model (ONNX) */
    const char* embedding_model_path;
    
    /** Path to LLM model (GGUF) */
    const char* llm_model_path;
    
    /** Embedding dimension (default 384 for all-MiniLM-L6-v2) */
    size_t embedding_dimension;
    
    /** Number of top chunks to retrieve (default 3) */
    size_t top_k;
    
    /** Minimum similarity threshold 0.0-1.0 (default 0.7) */
    float similarity_threshold;
    
    /** Maximum tokens for context (default 2048) */
    size_t max_context_tokens;
    
    /** Tokens per chunk when splitting documents (default 512) */
    size_t chunk_size;
    
    /** Overlap tokens between chunks (default 50) */
    size_t chunk_overlap;
    
    /** Prompt template with {context} and {query} placeholders */
    const char* prompt_template;
    
    /** Configuration JSON for embedding model (optional) */
    const char* embedding_config_json;
    
    /** Configuration JSON for LLM model (optional) */
    const char* llm_config_json;
} rac_rag_config_t;

/**
 * @brief Get default RAG configuration
 *
 * Uses an inline function instead of a designated-initializer constant
 * for C++17 compatibility (designated initializers are C99/C++20).
 */
static inline rac_rag_config_t rac_rag_config_default(void) {
    rac_rag_config_t cfg;
    cfg.embedding_model_path = NULL;
    cfg.llm_model_path = NULL;
    cfg.embedding_dimension = 384;
    cfg.top_k = 3;
    cfg.similarity_threshold = 0.15f;
    cfg.max_context_tokens = 2048;
    cfg.chunk_size = 512;
    cfg.chunk_overlap = 50;
    cfg.prompt_template = "Context:\n{context}\n\nQuestion: {query}\n\nAnswer:";
    cfg.embedding_config_json = NULL;
    cfg.llm_config_json = NULL;
    return cfg;
}

// =============================================================================
// RAG QUERY
// =============================================================================

/**
 * @brief RAG query parameters
 */
typedef struct rac_rag_query {
    const char* question;        /**< User question */
    const char* system_prompt;   /**< Optional system prompt override */
    int max_tokens;              /**< Max tokens to generate (default 512) */
    float temperature;           /**< Sampling temperature (default 0.7) */
    float top_p;                 /**< Nucleus sampling (default 0.9) */
    int top_k;                   /**< Top-k sampling (default 40) */
} rac_rag_query_t;

/**
 * @brief RAG result with answer and context
 */
typedef struct rac_rag_result {
    char* answer;                        /**< Generated answer (caller must free) */
    rac_search_result_t* retrieved_chunks;  /**< Retrieved chunks (caller must free) */
    size_t num_chunks;                   /**< Number of chunks retrieved */
    char* context_used;                  /**< Full context sent to LLM (caller must free) */
    double retrieval_time_ms;            /**< Time for retrieval phase */
    double generation_time_ms;           /**< Time for LLM generation */
    double total_time_ms;                /**< Total query time */
} rac_rag_result_t;

// =============================================================================
// PUBLIC API
// =============================================================================

/**
 * @brief Create a RAG pipeline
 *
 * @param config Pipeline configuration
 * @param out_pipeline Pointer to receive pipeline handle
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_rag_pipeline_create(
    const rac_rag_config_t* config,
    rac_rag_pipeline_t** out_pipeline
);

/**
 * @brief Add a document to the RAG pipeline
 *
 * Document will be split into chunks, embedded, and indexed.
 *
 * @param pipeline RAG pipeline handle
 * @param document_text Document text content
 * @param metadata_json Optional JSON metadata
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_rag_add_document(
    rac_rag_pipeline_t* pipeline,
    const char* document_text,
    const char* metadata_json
);

/**
 * @brief Add multiple documents in batch
 *
 * More efficient than calling rac_rag_add_document multiple times.
 *
 * @param pipeline RAG pipeline handle
 * @param documents Array of document texts
 * @param metadata_array Array of metadata JSONs (can be NULL)
 * @param count Number of documents
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_rag_add_documents_batch(
    rac_rag_pipeline_t* pipeline,
    const char** documents,
    const char** metadata_array,
    size_t count
);

/**
 * @brief Query the RAG pipeline
 *
 * Retrieves relevant chunks and generates answer.
 *
 * @param pipeline RAG pipeline handle
 * @param query Query parameters
 * @param out_result Pointer to receive result (caller must free with rac_rag_result_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_rag_query(
    rac_rag_pipeline_t* pipeline,
    const rac_rag_query_t* query,
    rac_rag_result_t* out_result
);

/**
 * @brief Clear all documents from the pipeline
 *
 * @param pipeline RAG pipeline handle
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_rag_clear_documents(rac_rag_pipeline_t* pipeline);

/**
 * @brief Get number of indexed documents
 *
 * @param pipeline RAG pipeline handle
 * @return Number of documents (chunks) in the index
 */
RAC_API size_t rac_rag_get_document_count(rac_rag_pipeline_t* pipeline);

/**
 * @brief Get pipeline statistics
 *
 * @param pipeline RAG pipeline handle
 * @param out_stats_json Pointer to receive JSON stats string (caller must free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_rag_get_statistics(
    rac_rag_pipeline_t* pipeline,
    char** out_stats_json
);

/**
 * @brief Free RAG result resources
 *
 * @param result Result to free
 */
RAC_API void rac_rag_result_free(rac_rag_result_t* result);

/**
 * @brief Destroy RAG pipeline
 *
 * @param pipeline Pipeline handle to destroy
 */
RAC_API void rac_rag_pipeline_destroy(rac_rag_pipeline_t* pipeline);

#ifdef __cplusplus
}
#endif

#endif // RAC_RAG_PIPELINE_H
