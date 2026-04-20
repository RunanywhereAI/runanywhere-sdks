// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — RAG (Retrieval-Augmented Generation) C ABI.
//
// Public surface matching legacy `rac_rag.h` / `rac_rag_pipeline.h`:
//   - Chunker: split text into overlapping chunks
//   - Embedding provider: wraps `ra_embed_*`
//   - Vector store: brute-force in-memory + optional usearch backend
//   - Pipeline: index + query
//
// The core provides the ABI + a pure-C++ brute-force implementation.
// Higher-fidelity vector-store backends (usearch, FAISS) plug in via
// `ra_rag_register_vector_backend` — same pattern as engines.

#ifndef RA_RAG_H
#define RA_RAG_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Chunking
// ---------------------------------------------------------------------------

typedef struct ra_rag_chunk_s {
    char*   text;           // UTF-8, heap-allocated
    int32_t start_offset;   // Source-text char offset
    int32_t end_offset;
    int32_t chunk_index;    // 0-based within the source document
} ra_rag_chunk_t;

// Split `text` into overlapping chunks of at most `max_chunk_chars` chars
// with `overlap_chars` between consecutive chunks. Heap-allocates the
// chunks array; free with `ra_rag_chunks_free`.
ra_status_t ra_rag_chunk_text(const char*       text,
                                int32_t           max_chunk_chars,
                                int32_t           overlap_chars,
                                ra_rag_chunk_t**  out_chunks,
                                int32_t*          out_count);

void ra_rag_chunks_free(ra_rag_chunk_t* chunks, int32_t count);

// ---------------------------------------------------------------------------
// Vector store (in-memory brute-force cosine similarity)
// ---------------------------------------------------------------------------

typedef struct ra_rag_vector_store_s ra_rag_vector_store_t;

ra_status_t ra_rag_store_create(int32_t embedding_dim,
                                 ra_rag_vector_store_t** out_store);

void ra_rag_store_destroy(ra_rag_vector_store_t* store);

// Add a row: (id, metadata_json, embedding[dim]). `id` and `metadata_json`
// are duplicated internally. Returns RA_OK on success.
ra_status_t ra_rag_store_add(ra_rag_vector_store_t* store,
                              const char*           row_id,
                              const char*           metadata_json,
                              const float*          embedding,
                              int32_t               dim);

ra_status_t ra_rag_store_remove(ra_rag_vector_store_t* store,
                                 const char*           row_id);

ra_status_t ra_rag_store_clear(ra_rag_vector_store_t* store);

int32_t     ra_rag_store_size(ra_rag_vector_store_t* store);

// Top-k cosine similarity search. `out_ids` and `out_metadata_jsons` are
// arrays of heap-allocated strings; free with `ra_rag_strings_free`.
// `out_scores` is a single buffer of `out_count` floats; free with
// `ra_rag_floats_free`.
ra_status_t ra_rag_store_search(ra_rag_vector_store_t* store,
                                  const float*          query_embedding,
                                  int32_t               dim,
                                  int32_t               top_k,
                                  char***               out_ids,
                                  char***               out_metadata_jsons,
                                  float**               out_scores,
                                  int32_t*              out_count);

// ---------------------------------------------------------------------------
// Pipeline helpers
// ---------------------------------------------------------------------------

// Formats retrieved chunks into an LLM context block. Each chunk is
// appended as "[#i] <metadata_summary>\n<text>\n\n". Heap-allocated;
// free with `ra_rag_string_free`.
ra_status_t ra_rag_format_context(const char* const* chunk_texts,
                                    const char* const* chunk_metadata_jsons,
                                    int32_t            chunk_count,
                                    char**             out_context);

// ---------------------------------------------------------------------------
// Memory ownership
// ---------------------------------------------------------------------------
void ra_rag_string_free(char* str);
void ra_rag_strings_free(char** strs, int32_t count);
void ra_rag_floats_free(float* floats);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_RAG_H
