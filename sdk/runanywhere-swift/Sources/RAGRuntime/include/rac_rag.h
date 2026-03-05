/**
 * @file rac_rag.h
 * @brief RunAnywhere Commons - RAG Backend Public API
 *
 * Registration and control functions for the RAG backend.
 */

#ifndef RAC_RAG_H
#define RAC_RAG_H

#include "rac_types.h"
#include "rac_rag_pipeline.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register the RAG backend module
 *
 * Must be called before using RAG functionality.
 *
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_backend_rag_register(void);

/**
 * @brief Unregister the RAG backend module
 *
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_backend_rag_unregister(void);

#ifdef __cplusplus
}
#endif

#endif // RAC_RAG_H
