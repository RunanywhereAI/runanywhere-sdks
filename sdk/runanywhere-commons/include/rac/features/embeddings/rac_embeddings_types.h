/**
 * @file rac_embeddings_types.h
 * @brief RunAnywhere Commons - Embeddings Types and Data Structures
 *
 * Data structures for text/token embedding generation.
 * Embeddings convert text into fixed-dimensional dense vectors
 * useful for semantic search, clustering, and RAG.
 *
 * For the service interface, see rac_embeddings_service.h.
 */

#ifndef RAC_EMBEDDINGS_TYPES_H
#define RAC_EMBEDDINGS_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS
// =============================================================================

#define RAC_EMBEDDINGS_DEFAULT_BATCH_SIZE     512
#define RAC_EMBEDDINGS_MAX_BATCH_SIZE         8192
#define RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS     512

// =============================================================================
// ENUMS
// =============================================================================

/**
 * @brief Embedding normalization mode
 */
typedef enum rac_embeddings_normalize {
    RAC_EMBEDDINGS_NORMALIZE_NONE = 0,  /**< No normalization */
    RAC_EMBEDDINGS_NORMALIZE_L2 = 1,    /**< L2 normalization (unit vectors, recommended for cosine similarity) */
} rac_embeddings_normalize_t;

/**
 * @brief Embedding pooling strategy
 */
typedef enum rac_embeddings_pooling {
    RAC_EMBEDDINGS_POOLING_MEAN = 0,  /**< Mean pooling over all token embeddings */
    RAC_EMBEDDINGS_POOLING_CLS = 1,   /**< Use CLS token embedding */
    RAC_EMBEDDINGS_POOLING_LAST = 2,  /**< Use last token embedding */
} rac_embeddings_pooling_t;

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * @brief Embeddings component configuration
 */
typedef struct rac_embeddings_config {
    /** Model ID (optional) */
    const char* model_id;

    /** Preferred framework (use -1 for auto) */
    int32_t preferred_framework;

    /** Maximum tokens per input (default: 512) */
    int32_t max_tokens;

    /** Normalization mode (default: L2) */
    rac_embeddings_normalize_t normalize;

    /** Pooling strategy (default: MEAN) */
    rac_embeddings_pooling_t pooling;
} rac_embeddings_config_t;

/**
 * @brief Default embeddings configuration
 */
static const rac_embeddings_config_t RAC_EMBEDDINGS_CONFIG_DEFAULT = {
    .model_id = RAC_NULL,
    .preferred_framework = -1,
    .max_tokens = RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS,
    .normalize = RAC_EMBEDDINGS_NORMALIZE_L2,
    .pooling = RAC_EMBEDDINGS_POOLING_MEAN
};

// =============================================================================
// OPTIONS
// =============================================================================

/**
 * @brief Embedding generation options
 */
typedef struct rac_embeddings_options {
    /** Normalization override (-1 = use config default) */
    int32_t normalize;

    /** Pooling override (-1 = use config default) */
    int32_t pooling;

    /** Number of threads (0 = auto) */
    int32_t n_threads;
} rac_embeddings_options_t;

/**
 * @brief Default embedding options
 */
static const rac_embeddings_options_t RAC_EMBEDDINGS_OPTIONS_DEFAULT = {
    .normalize = -1,
    .pooling = -1,
    .n_threads = 0
};

// =============================================================================
// RESULT
// =============================================================================

/**
 * @brief Single embedding result
 */
typedef struct rac_embedding_vector {
    /** Embedding data (dense float vector, owned) */
    float* data;

    /** Embedding dimension */
    size_t dimension;
} rac_embedding_vector_t;

/**
 * @brief Embedding generation result
 */
typedef struct rac_embeddings_result {
    /** Array of embedding vectors (one per input text) */
    rac_embedding_vector_t* embeddings;

    /** Number of embeddings */
    size_t num_embeddings;

    /** Embedding dimension */
    size_t dimension;

    /** Total processing time in milliseconds */
    int64_t processing_time_ms;

    /** Total tokens processed */
    int32_t total_tokens;
} rac_embeddings_result_t;

// =============================================================================
// INFO
// =============================================================================

/**
 * @brief Embeddings service information
 */
typedef struct rac_embeddings_info {
    /** Whether the service is ready */
    rac_bool_t is_ready;

    /** Current model identifier */
    const char* current_model;

    /** Embedding dimension */
    size_t dimension;

    /** Maximum input tokens */
    int32_t max_tokens;
} rac_embeddings_info_t;

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free embeddings result resources
 *
 * @param result Result to free (can be NULL)
 */
RAC_API void rac_embeddings_result_free(rac_embeddings_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_EMBEDDINGS_TYPES_H */
