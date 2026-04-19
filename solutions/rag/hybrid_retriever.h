// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Hybrid retriever: parallel BM25 + vector search fused with Reciprocal
// Rank Fusion. Ported from FastVoice RAG/temp/src/rag/hybrid_retriever.h.

#ifndef RA_SOLUTIONS_RAG_HYBRID_RETRIEVER_H
#define RA_SOLUTIONS_RAG_HYBRID_RETRIEVER_H

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "bm25_index.h"

namespace ra::rag {

struct VectorHit {
    std::uint32_t doc_id;
    float         score;   // 1 - cosine_distance (higher = better)
};

// Simple vector store interface. Default impl uses USearch; swap in a
// remote pgvector client by subclassing.
class VectorStore {
public:
    virtual ~VectorStore() = default;
    virtual std::vector<VectorHit> search(const float* query_vec,
                                           int          dims,
                                           std::size_t  top_k) const = 0;
    virtual void add(std::uint32_t  doc_id,
                      const float*   vec,
                      int            dims) = 0;
};

struct HybridResult {
    std::uint32_t doc_id;
    float         fused_score;
    float         bm25_score;
    float         vector_score;
};

class HybridRetriever {
public:
    HybridRetriever(const BM25Index*   bm25,
                    const VectorStore* vectors,
                    int                rrf_k = 60)
        : bm25_(bm25), vectors_(vectors), rrf_k_(rrf_k) {}

    // Returns top-K results ordered by fused score. Runs BM25 on one thread
    // and vector search on the caller thread concurrently, then joins via
    // RRF.
    std::vector<HybridResult> retrieve(std::string_view query,
                                        const float*     query_vec,
                                        int              dims,
                                        std::size_t      top_k) const;

private:
    const BM25Index*   bm25_;
    const VectorStore* vectors_;
    int                rrf_k_;
};

}  // namespace ra::rag

#endif  // RA_SOLUTIONS_RAG_HYBRID_RETRIEVER_H
