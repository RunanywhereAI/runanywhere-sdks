/**
 * @file rac_rag.h
 * @brief RunAnywhere Commons - RAG Pipeline Public API
 *
 * Registration and control functions for the RAG pipeline module.
 */

#ifndef RAC_RAG_H
#define RAC_RAG_H

#include "rac/core/rac_types.h"
#include "rac/features/rag/rac_rag_pipeline.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register the RAG pipeline module
 *
 * Must be called before using RAG functionality.
 * Also registers the ONNX embeddings service provider if available.
 *
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_backend_rag_register(void);

/**
 * @brief Unregister the RAG pipeline module
 *
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_backend_rag_unregister(void);

#ifdef __cplusplus
}
#endif

#endif // RAC_RAG_H
