/**
 * @file rac_rag.h
 * @brief RunAnywhere Commons - RAG Pipeline Public API
 *
 * Registration and proto-byte session APIs for the RAG pipeline module.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - `rac_backend_rag_register` / `rac_backend_rag_unregister`: `internal`.
 *     The register/unregister entry points wire the RAG plugin into the
 *     registry; SDK callers do not invoke them directly.
 *   - `rac_rag_session_create_proto` / `rac_rag_session_destroy_proto` /
 *     `rac_rag_ingest_proto` / `rac_rag_query_proto` / `rac_rag_clear_proto` /
 *     `rac_rag_stats_proto`: `SDK-facing default` over
 *     runanywhere.v1.RAGConfiguration / RAGDocument / RAGQueryOptions /
 *     RAGResult / RAGStatistics bytes. The session handle is carried as
 *     `rac_handle_t` for uniform frontend FFI.
 */

#ifndef RAC_RAG_H
#define RAC_RAG_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MODULE REGISTRATION
// =============================================================================

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

// =============================================================================
// PROTO-BYTE SESSION API
// =============================================================================

/**
 * @brief Create a RAG session from serialized runanywhere.v1.RAGConfiguration bytes.
 *
 * The returned handle is an internal RAG pipeline carried as rac_handle_t for
 * uniform frontend FFI. Destroy it with rac_rag_session_destroy_proto().
 */
RAC_API rac_result_t rac_rag_session_create_proto(const uint8_t* config_proto_bytes,
                                                  size_t config_proto_size,
                                                  rac_handle_t* out_session);

/**
 * @brief Destroy a RAG session created by rac_rag_session_create_proto().
 */
RAC_API void rac_rag_session_destroy_proto(rac_handle_t session);

/**
 * @brief Ingest one document from serialized runanywhere.v1.RAGDocument bytes.
 *
 * RAGDocument.text is the document body. RAGDocument.id, metadata_json, and
 * metadata are persisted as ingestion metadata. out_stats receives
 * runanywhere.v1.RAGStatistics.
 */
RAC_API rac_result_t rac_rag_ingest_proto(rac_handle_t session, const uint8_t* document_proto_bytes,
                                          size_t document_proto_size,
                                          rac_proto_buffer_t* out_stats);

/**
 * @brief Query a RAG session from serialized runanywhere.v1.RAGQueryOptions bytes.
 *
 * out_result receives serialized runanywhere.v1.RAGResult bytes.
 */
RAC_API rac_result_t rac_rag_query_proto(rac_handle_t session, const uint8_t* query_proto_bytes,
                                         size_t query_proto_size, rac_proto_buffer_t* out_result);

/**
 * @brief Clear a RAG session and return serialized runanywhere.v1.RAGStatistics.
 */
RAC_API rac_result_t rac_rag_clear_proto(rac_handle_t session, rac_proto_buffer_t* out_stats);

/**
 * @brief Return serialized runanywhere.v1.RAGStatistics for a RAG session.
 */
RAC_API rac_result_t rac_rag_stats_proto(rac_handle_t session, rac_proto_buffer_t* out_stats);

// =============================================================================
// CANONICAL DEFAULTS (P2-T14)
// =============================================================================

/**
 * @brief Merge an inbound runanywhere.v1.RAGConfiguration over canonical
 *        defaults and return the resolved configuration.
 *
 * Commons-owned port of Swift's `RARAGConfiguration.defaults()`. The canonical
 * defaults are:
 *
 *   embedding_dimension   = 384
 *   top_k                 = 5
 *   similarity_threshold  = 0.7
 *   chunk_size            = 512
 *   chunk_overlap         = 64
 *
 * String-id fields (embedding_model_id / llm_model_id / reranker_model_id /
 * prompt_template / index_path / embedding_config_json / llm_config_json) and
 * the optional `persist_index` / `rerank_results` fields default to the proto
 * zero values; callers populate them via the input request bytes.
 *
 * Field-merge semantics: any non-zero / non-empty / explicitly-set field on
 * the inbound request overrides the corresponding default. Numeric fields
 * (top_k, embedding_dimension, chunk_size, similarity_threshold) treat the
 * proto zero as "use default" so callers can omit them; pass an explicit
 * non-zero value to override. Strings and bools follow the same "non-empty
 * wins, otherwise default" rule.
 *
 * Empty inbound bytes (in_request_bytes == NULL && in_size == 0) yield a
 * pure-default RAGConfiguration. out_RARAGConfiguration receives serialized
 * runanywhere.v1.RAGConfiguration bytes; caller MUST release with
 * rac_proto_buffer_free().
 *
 * @retval RAC_SUCCESS                      Defaults merged and serialized.
 * @retval RAC_ERROR_NULL_POINTER           out_RARAGConfiguration is NULL.
 * @retval RAC_ERROR_DECODING_ERROR         in_request_bytes is malformed.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE  Commons built without Protobuf.
 */
RAC_API rac_result_t rac_rag_request_with_defaults_proto(
    const uint8_t* in_request_bytes, size_t in_size, rac_proto_buffer_t* out_RARAGConfiguration);

#ifdef __cplusplus
}
#endif

#endif  // RAC_RAG_H
