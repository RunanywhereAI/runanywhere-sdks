/**
 * @file rac_embeddings_onnx.h
 * @brief RunAnywhere Commons - ONNX Embeddings Backend Public API
 *
 * Registration for the ONNX-based embedding provider (sentence-transformer models).
 * Registers with RAC_CAPABILITY_EMBEDDINGS via the service registry.
 */

#ifndef RAC_EMBEDDINGS_ONNX_H
#define RAC_EMBEDDINGS_ONNX_H

#include "rac/core/rac_types.h"
#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register the ONNX embeddings backend
 *
 * Registers a service provider for RAC_CAPABILITY_EMBEDDINGS.
 * Handles .onnx model files with sentence-transformer architecture.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_backend_onnx_embeddings_register(void);

/**
 * @brief Unregister the ONNX embeddings backend
 *
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_backend_onnx_embeddings_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_EMBEDDINGS_ONNX_H */
