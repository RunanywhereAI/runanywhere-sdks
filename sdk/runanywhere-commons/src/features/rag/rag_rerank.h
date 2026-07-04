/**
 * @file rag_rerank.h
 * @brief LLM-pointwise reranking of fused RAG candidates.
 *
 * The generation LLM scores each candidate 1-5 for relevance to the query in a
 * single call; candidates are then reordered by score (fused position breaks
 * ties). No cross-encoder — the `rerank_ops` vtable slot was removed in plugin
 * ABI v4. Any failure (LLM error, unparseable output) leaves the input order
 * untouched. Parsing and reordering are split out so they can be unit-tested
 * without a live model.
 */

#ifndef RUNANYWHERE_RAG_RERANK_H
#define RUNANYWHERE_RAG_RERANK_H

#include "vector_store_usearch.h"

#include <string>
#include <vector>

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"

namespace runanywhere {
namespace rag {

/**
 * @brief Parse LLM scorer output into per-candidate scores.
 *
 * Accepts lines of the form "<index>: <score>" (tolerant of '.', '-', ')' and
 * surrounding whitespace/prose). `index` is 1-based and must be in [1, n];
 * `score` is clamped to [1, 5]. `scores` is resized to `n` and zero-filled;
 * unmatched entries stay 0.
 *
 * @return number of distinct candidates that received a score.
 */
size_t parse_rerank_scores(const std::string& text, size_t n, std::vector<int>& scores);

/**
 * @brief Stable-reorder `results` by descending score (ties keep input order).
 *
 * `scores` must be the same length as `results`. No-op if lengths differ.
 */
void reorder_by_scores(std::vector<SearchResult>& results, const std::vector<int>& scores);

/**
 * @brief Score `results` with the LLM and reorder in place.
 *
 * No-op when `llm_handle` is null or `results.size() < 2`. On any failure the
 * fused order is preserved.
 */
void rerank_llm_pointwise(rac_handle_t llm_handle, const std::string& question,
                          const rac_llm_options_t& base_options,
                          std::vector<SearchResult>& results);

}  // namespace rag
}  // namespace runanywhere

#endif  // RUNANYWHERE_RAG_RERANK_H
