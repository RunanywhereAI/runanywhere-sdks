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
 *     `rac_rag_ingest_proto` / `rac_rag_query_proto` / `rac_rag_cancel_proto` /
 *     `rac_rag_clear_proto` /
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
 * The returned handle is an opaque RAG-session token carried as rac_handle_t
 * for uniform frontend FFI. Destroy it with rac_rag_session_destroy_proto().
 */
RAC_API rac_result_t rac_rag_session_create_proto(const uint8_t* config_proto_bytes,
                                                  size_t config_proto_size,
                                                  rac_handle_t* out_session);

/**
 * @brief Destroy a RAG session created by rac_rag_session_create_proto().
 *
 * The handle stops admitting new operations before active query cancellation
 * is requested. Resources remain valid until already-admitted operations have
 * returned, so this function is safe to call concurrently with all other RAG
 * session operations.
 */
RAC_API void rac_rag_session_destroy_proto(rac_handle_t session);

/**
 * @brief Ingest one document from serialized runanywhere.v1.RAGDocument bytes.
 *
 * RAGDocument.text is the document body. RAGDocument.id and metadata are
 * persisted as ingestion metadata. out_stats receives
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
 * @brief Per-event callback for streaming RAG queries.
 *
 * Invoked synchronously on the calling thread for each serialized
 * runanywhere.v1.RAGStreamEvent (TOKEN as the answer generates, then a terminal
 * COMPLETED carrying the full RAGResult, or ERROR). The bytes are owned by the
 * SDK and valid only for the duration of the call — copy if retained.
 *
 * Return RAC_TRUE to keep generating, RAC_FALSE to stop early (backpressure):
 * a false return on a TOKEN event halts generation and the run ends with a
 * terminal COMPLETED carrying the partial answer.
 */
typedef rac_bool_t (*rac_rag_stream_proto_callback_t)(const uint8_t* event_bytes,
                                                      size_t event_size, void* user_data);

/**
 * @brief Streaming variant of rac_rag_query_proto.
 *
 * Runs the same pipeline but forwards each generated token as a RAGStreamEvent
 * to `callback` (no unary wait), then a terminal COMPLETED/ERROR event. Returns
 * the pipeline status. Cancellation is via rac_rag_cancel_proto() (same as the
 * unary path) — a cancelled run ends with an ERROR event carrying
 * RAC_ERROR_CANCELLED.
 */
RAC_API rac_result_t rac_rag_query_stream_proto(rac_handle_t session,
                                                const uint8_t* query_proto_bytes,
                                                size_t query_proto_size,
                                                rac_rag_stream_proto_callback_t callback,
                                                void* user_data);

/**
 * @brief Request cancellation of the query currently running on a RAG session.
 *
 * Safe to call from a thread other than the one blocked in
 * rac_rag_query_proto(). It forwards to the session-owned LLM and latches a
 * graph-level flag checked between retrieval and generation phases.
 */
RAC_API rac_result_t rac_rag_cancel_proto(rac_handle_t session);

/**
 * @brief Clear a RAG session and return serialized runanywhere.v1.RAGStatistics.
 */
RAC_API rac_result_t rac_rag_clear_proto(rac_handle_t session, rac_proto_buffer_t* out_stats);

/**
 * @brief Return serialized runanywhere.v1.RAGStatistics for a RAG session.
 */
RAC_API rac_result_t rac_rag_stats_proto(rac_handle_t session, rac_proto_buffer_t* out_stats);

#ifdef __cplusplus
}
#endif

#endif  // RAC_RAG_H
