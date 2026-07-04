/**
 * @file rag_fusion.h
 * @brief Reciprocal Rank Fusion + multi-query variant parsing for RAG.
 *
 * Split out from the pipeline graph so the pure, LLM-independent parts (RRF over
 * N ranked id lists, and parsing an LLM's rewrite output into query variants)
 * can be unit-tested without a live model.
 */

#ifndef RUNANYWHERE_RAG_FUSION_H
#define RUNANYWHERE_RAG_FUSION_H

#include "vector_store_usearch.h"

#include <string>
#include <vector>

namespace runanywhere {
namespace rag {

/**
 * @brief Reciprocal Rank Fusion over an arbitrary set of ranked id lists
 * (dense + BM25 for the original query and every multi-query variant).
 *
 * Score for an id = sum over rankings of 1/(k + rank), k=60, rank 1-based.
 * Results are sorted by score, truncated to top_k, normalized into [0,1], and
 * materialized (text + metadata) from `vector_store` when non-null.
 */
std::vector<SearchResult> fuse_rankings(const std::vector<std::vector<std::string>>& rankings,
                                        const VectorStoreUSearch* vector_store, size_t top_k);

/**
 * @brief Parse an LLM query-rewrite response into up to `count` variants.
 *
 * Accepts lines with common list markers ('-', '*', numbering, ')') and
 * surrounding whitespace. Drops blanks, entries outside [4,256] chars, and any
 * variant equal to `original`. Pure/deterministic — the LLM call lives in the
 * pipeline graph.
 */
std::vector<std::string> parse_query_variants(const std::string& llm_text,
                                              const std::string& original, size_t count);

}  // namespace rag
}  // namespace runanywhere

#endif  // RUNANYWHERE_RAG_FUSION_H
