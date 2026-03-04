/**
 * @file rac_embeddings_component.h
 * @brief RunAnywhere Commons - Embeddings Capability Component
 *
 * Actor-based embeddings capability that owns model lifecycle
 * and embedding generation. Uses lifecycle manager for unified
 * lifecycle + analytics handling.
 */

#ifndef RAC_EMBEDDINGS_COMPONENT_H
#define RAC_EMBEDDINGS_COMPONENT_H

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_error.h"
#include "rac/features/embeddings/rac_embeddings_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EMBEDDINGS COMPONENT API
// =============================================================================

/**
 * @brief Create an embeddings component
 */
RAC_API rac_result_t rac_embeddings_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the embeddings component
 */
RAC_API rac_result_t rac_embeddings_component_configure(rac_handle_t handle,
                                                         const rac_embeddings_config_t* config);

/**
 * @brief Check if model is loaded
 */
RAC_API rac_bool_t rac_embeddings_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 */
RAC_API const char* rac_embeddings_component_get_model_id(rac_handle_t handle);

/**
 * @brief Load an embedding model
 */
RAC_API rac_result_t rac_embeddings_component_load_model(rac_handle_t handle,
                                                          const char* model_path,
                                                          const char* model_id,
                                                          const char* model_name);

/**
 * @brief Unload the current model
 */
RAC_API rac_result_t rac_embeddings_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 */
RAC_API rac_result_t rac_embeddings_component_cleanup(rac_handle_t handle);

/**
 * @brief Generate embedding for a single text
 */
RAC_API rac_result_t rac_embeddings_component_embed(rac_handle_t handle,
                                                     const char* text,
                                                     const rac_embeddings_options_t* options,
                                                     rac_embeddings_result_t* out_result);

/**
 * @brief Generate embeddings for a batch of texts
 */
RAC_API rac_result_t rac_embeddings_component_embed_batch(rac_handle_t handle,
                                                           const char* const* texts,
                                                           size_t num_texts,
                                                           const rac_embeddings_options_t* options,
                                                           rac_embeddings_result_t* out_result);

/**
 * @brief Get lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_embeddings_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 */
RAC_API rac_result_t rac_embeddings_component_get_metrics(rac_handle_t handle,
                                                           rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the embeddings component
 */
RAC_API void rac_embeddings_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_EMBEDDINGS_COMPONENT_H */
