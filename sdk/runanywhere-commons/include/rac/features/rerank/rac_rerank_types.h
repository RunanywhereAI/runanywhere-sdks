/** @file rac_rerank_types.h @brief Backend-facing cross-encoder reranking types. */

#ifndef RAC_FEATURES_RERANK_RAC_RERANK_TYPES_H
#define RAC_FEATURES_RERANK_RAC_RERANK_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * One candidate document/passage handed to the reranker. Both pointers are
 * caller-owned and only borrowed for the duration of the `rerank` call; the id
 * is echoed back on the corresponding scored item.
 */
typedef struct rac_rerank_candidate {
    const char* id;
    const char* text;
} rac_rerank_candidate_t;

typedef struct rac_rerank_options {
    /** When > 0, return only the top_n highest-scoring items (all candidates are
     * still scored). 0 = return every candidate, ranked. */
    uint32_t top_n;
} rac_rerank_options_t;

static const rac_rerank_options_t RAC_RERANK_OPTIONS_DEFAULT = {
    .top_n = 0,
};

typedef struct rac_rerank_scored_item {
    /** malloc-owned copy of the source candidate id (may be NULL if the source
     * candidate had no id). */
    char* id;
    /** Raw relevance score (higher = more relevant). Comparable only within one
     * result set. */
    float score;
    /** Index of this candidate in the original request candidate list. */
    uint32_t original_index;
    /** 0-based rank after sorting by score descending (0 = most relevant). */
    uint32_t rank;
} rac_rerank_scored_item_t;

typedef struct rac_rerank_result {
    /** Sorted by score descending; truncated to top_n when requested. */
    rac_rerank_scored_item_t* items;
    size_t item_count;
    int64_t processing_time_ms;
    char* model_id;
} rac_rerank_result_t;

/** Free every malloc-owned result field and zero the struct. */
RAC_API void rac_rerank_result_free(rac_rerank_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_RERANK_RAC_RERANK_TYPES_H */
