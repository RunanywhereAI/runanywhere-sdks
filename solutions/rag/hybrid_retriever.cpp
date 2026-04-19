// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "hybrid_retriever.h"

#include <algorithm>
#include <future>
#include <unordered_map>
#include <vector>

namespace ra::rag {

std::vector<HybridResult> HybridRetriever::retrieve(
        std::string_view query,
        const float*     query_vec,
        int              dims,
        std::size_t      top_k) const {

    // Kick off BM25 on a worker thread; run vector search on the caller.
    std::future<std::vector<BM25Hit>> bm25_future;
    if (bm25_) {
        bm25_future = std::async(std::launch::async, [this, query, top_k]() {
            return bm25_->search(query, top_k * 4);
        });
    }

    std::vector<VectorHit> vec_hits;
    if (vectors_ && query_vec) {
        vec_hits = vectors_->search(query_vec, dims, top_k * 4);
    }

    std::vector<BM25Hit> bm25_hits;
    if (bm25_future.valid()) bm25_hits = bm25_future.get();

    // Reciprocal Rank Fusion.
    struct Accum {
        float fused = 0.f;
        float bm25  = 0.f;
        float vec   = 0.f;
    };
    std::unordered_map<std::uint32_t, Accum> fused;
    fused.reserve(bm25_hits.size() + vec_hits.size());
    const auto k = static_cast<float>(rrf_k_);

    for (std::size_t rank = 0; rank < bm25_hits.size(); ++rank) {
        auto& a = fused[bm25_hits[rank].doc_id];
        a.fused += 1.f / (k + static_cast<float>(rank + 1));
        a.bm25   = bm25_hits[rank].score;
    }
    for (std::size_t rank = 0; rank < vec_hits.size(); ++rank) {
        auto& a = fused[vec_hits[rank].doc_id];
        a.fused += 1.f / (k + static_cast<float>(rank + 1));
        a.vec    = vec_hits[rank].score;
    }

    std::vector<HybridResult> results;
    results.reserve(fused.size());
    for (auto& [id, acc] : fused) {
        results.push_back({id, acc.fused, acc.bm25, acc.vec});
    }
    std::partial_sort(results.begin(),
        results.begin() + std::min(top_k, results.size()),
        results.end(),
        [](const HybridResult& a, const HybridResult& b) {
            return a.fused_score > b.fused_score;
        });
    if (results.size() > top_k) results.resize(top_k);
    return results;
}

}  // namespace ra::rag
