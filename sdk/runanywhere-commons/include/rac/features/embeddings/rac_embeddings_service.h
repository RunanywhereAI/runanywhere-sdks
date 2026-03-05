/**
 * @file rac_embeddings_service.h
 * @brief RunAnywhere Commons - Embeddings Service Interface
 *
 * Vtable-based service interface for embedding generation.
 * Backends (llama.cpp, ONNX) implement the ops vtable and register
 * via rac_service_register_provider().
 */

#ifndef RAC_EMBEDDINGS_SERVICE_H
#define RAC_EMBEDDINGS_SERVICE_H

#include "rac/core/rac_types.h"
#include "rac/core/rac_error.h"
#include "rac/features/embeddings/rac_embeddings_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE
// =============================================================================

/**
 * @brief Embeddings service operations vtable
 *
 * Backend implementations provide these function pointers.
 */
typedef struct rac_embeddings_service_ops {
    /** Initialize the service with a model path */
    rac_result_t (*initialize)(void* impl, const char* model_path);

    /** Generate embeddings for a single text */
    rac_result_t (*embed)(void* impl, const char* text,
                          const rac_embeddings_options_t* options,
                          rac_embeddings_result_t* out_result);

    /** Generate embeddings for a batch of texts */
    rac_result_t (*embed_batch)(void* impl, const char* const* texts,
                                size_t num_texts,
                                const rac_embeddings_options_t* options,
                                rac_embeddings_result_t* out_result);

    /** Get service information */
    rac_result_t (*get_info)(void* impl, rac_embeddings_info_t* out_info);

    /** Cleanup resources */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);
} rac_embeddings_service_ops_t;

/**
 * @brief Embeddings service instance
 */
typedef struct rac_embeddings_service {
    const rac_embeddings_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_embeddings_service_t;

// =============================================================================
// PUBLIC API
// =============================================================================

/**
 * @brief Create an embeddings service
 *
 * @param model_id Model identifier
 * @param out_handle Output: Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_embeddings_create(const char* model_id, rac_handle_t* out_handle);

/**
 * @brief Initialize the service with a model
 *
 * @param handle Service handle
 * @param model_path Path to the embedding model
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_embeddings_initialize(rac_handle_t handle, const char* model_path);

/**
 * @brief Generate embedding for a single text
 *
 * @param handle Service handle
 * @param text Input text
 * @param options Embedding options (can be NULL for defaults)
 * @param out_result Output: Embedding result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_embeddings_embed(rac_handle_t handle, const char* text,
                                           const rac_embeddings_options_t* options,
                                           rac_embeddings_result_t* out_result);

/**
 * @brief Generate embeddings for a batch of texts
 *
 * @param handle Service handle
 * @param texts Array of input texts
 * @param num_texts Number of texts
 * @param options Embedding options (can be NULL for defaults)
 * @param out_result Output: Embedding results
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_embeddings_embed_batch(rac_handle_t handle, const char* const* texts,
                                                 size_t num_texts,
                                                 const rac_embeddings_options_t* options,
                                                 rac_embeddings_result_t* out_result);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service info
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_embeddings_get_info(rac_handle_t handle, rac_embeddings_info_t* out_info);

/**
 * @brief Cleanup service resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_embeddings_cleanup(rac_handle_t handle);

/**
 * @brief Destroy the embeddings service
 *
 * @param handle Service handle
 */
RAC_API void rac_embeddings_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_EMBEDDINGS_SERVICE_H */
