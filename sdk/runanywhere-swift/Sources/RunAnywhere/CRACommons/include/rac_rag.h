/**
 * @file rac_rag.h
 * @brief RunAnywhere Commons - RAG Pipeline Public API
 *
 * Registration and control functions for the RAG pipeline module.
 */

#ifndef RAC_RAG_H
#define RAC_RAG_H

#include "rac_proto_buffer.h"
#include "rac_types.h"

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

/**
 * @brief Merge an inbound runanywhere.v1.RAGConfiguration over canonical
 *        defaults and return the resolved configuration (P2-T14).
 *
 * Commons-owned port of Swift's `RARAGConfiguration.defaults()`. Numeric/bool
 * fields treat proto zero as "use default"; non-zero values override. Strings
 * pass through verbatim. Empty inbound bytes (NULL/0) yield pure defaults.
 *
 * out_RARAGConfiguration receives serialized runanywhere.v1.RAGConfiguration
 * bytes; caller MUST release with rac_proto_buffer_free().
 */
RAC_API rac_result_t rac_rag_request_with_defaults_proto(
    const uint8_t* in_request_bytes, size_t in_size,
    rac_proto_buffer_t* out_RARAGConfiguration);

#ifdef __cplusplus
}
#endif

#endif  // RAC_RAG_H
