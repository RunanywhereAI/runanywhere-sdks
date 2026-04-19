// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Unit tests for solutions/rag/hybrid_retriever. Uses a StubVectorStore to
// exercise RRF fusion without requiring a real HNSW implementation.

#include "../hybrid_retriever.h"
#include "../bm25_index.h"

#include <gtest/gtest.h>

#include <algorithm>

using namespace ra::rag;

namespace {

class StubVectorStore final : public VectorStore {
public:
    std::vector<VectorHit> search(const float*   /*query_vec*/,
                                   int            /*dims*/,
                                   std::size_t    top_k) const override {
        auto hits = hits_;
        if (hits.size() > top_k) hits.resize(top_k);
        return hits;
    }
    void add(std::uint32_t /*doc_id*/,
             const float*   /*vec*/,
             int            /*dims*/) override { /* no-op in stub */ }

    void set_hits(std::vector<VectorHit> h) { hits_ = std::move(h); }

private:
    std::vector<VectorHit> hits_;
};

BM25Index build_index() {
    BM25Index idx;
    idx.add_document(0, "machine learning algorithms study data");
    idx.add_document(1, "python programming for data science and machine learning");
    idx.add_document(2, "kubernetes pod orchestration networking");
    idx.add_document(3, "natural language processing transformer models");
    idx.build_done();
    return idx;
}

}  // namespace

TEST(HybridRetriever, NoBm25NoVector_ReturnsEmpty) {
    HybridRetriever r(nullptr, nullptr);
    auto results = r.retrieve("anything", nullptr, 0, 5);
    EXPECT_TRUE(results.empty());
}

TEST(HybridRetriever, Bm25Only_PopulatesBm25ScoreLeavesVectorScoreZero) {
    auto idx = build_index();
    HybridRetriever r(&idx, nullptr);
    auto results = r.retrieve("machine learning", nullptr, 0, 5);
    ASSERT_FALSE(results.empty());
    for (const auto& h : results) {
        EXPECT_GT(h.bm25_score, 0.f);
        EXPECT_EQ(h.vector_score, 0.f);
        EXPECT_GT(h.fused_score, 0.f);
    }
}

TEST(HybridRetriever, VectorOnly_PopulatesVectorScore) {
    StubVectorStore vecs;
    vecs.set_hits({{5, 0.9f}, {6, 0.8f}, {7, 0.7f}});
    HybridRetriever r(nullptr, &vecs);
    float dummy_vec[4] = {1, 0, 0, 0};
    auto results = r.retrieve("", dummy_vec, 4, 5);
    ASSERT_EQ(results.size(), 3u);
    for (const auto& h : results) {
        EXPECT_EQ(h.bm25_score, 0.f);
        EXPECT_GT(h.vector_score, 0.f);
    }
}

TEST(HybridRetriever, FusionFavoursDocsInBothLists) {
    auto idx = build_index();
    StubVectorStore vecs;
    // Vector search returns docs 1 and 2 — the overlap with BM25 for
    // "machine learning" is doc 1, which should win the fused ordering.
    vecs.set_hits({{1, 0.95f}, {2, 0.40f}, {3, 0.10f}});

    HybridRetriever r(&idx, &vecs);
    float dummy_vec[4] = {1, 0, 0, 0};
    auto results = r.retrieve("machine learning", dummy_vec, 4, 4);
    ASSERT_FALSE(results.empty());

    // Doc 1 appears in both searches — it must be ranked first.
    EXPECT_EQ(results.front().doc_id, 1u);
    // The fused winner must carry both sub-scores.
    EXPECT_GT(results.front().bm25_score, 0.f);
    EXPECT_GT(results.front().vector_score, 0.f);
}

TEST(HybridRetriever, RrfIsMonotoneDescending) {
    auto idx = build_index();
    StubVectorStore vecs;
    vecs.set_hits({{0, 0.9f}, {1, 0.8f}, {2, 0.5f}});

    HybridRetriever r(&idx, &vecs);
    float dummy_vec[4] = {1, 0, 0, 0};
    auto results = r.retrieve("machine learning", dummy_vec, 4, 10);
    for (std::size_t i = 1; i < results.size(); ++i) {
        EXPECT_GE(results[i - 1].fused_score, results[i].fused_score);
    }
}

TEST(HybridRetriever, TopKBoundsFusedOutput) {
    auto idx = build_index();
    StubVectorStore vecs;
    vecs.set_hits({{0, 0.9f}, {1, 0.8f}, {2, 0.7f}, {3, 0.6f}});
    HybridRetriever r(&idx, &vecs);
    float dummy_vec[4] = {1, 0, 0, 0};
    auto results = r.retrieve("machine learning", dummy_vec, 4, 2);
    EXPECT_LE(results.size(), 2u);
}
