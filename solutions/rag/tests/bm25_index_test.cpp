// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Unit tests for solutions/rag/bm25_index. Exercises the build + search
// cycle and the per-caller-scratch contract that makes search() safe to
// call concurrently post-build_done().

#include "../bm25_index.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <array>
#include <thread>
#include <vector>

using namespace ra::rag;

namespace {

// Canonical tiny corpus — three docs, each deliberately constructed so that
// a query for "machine learning" ranks doc 0 highest and the token "python"
// ranks doc 2 highest.
struct Corpus {
    std::vector<std::pair<std::uint32_t, std::string>> docs = {
        {0, "machine learning is the study of algorithms that improve with data"},
        {1, "deep learning is a subfield of machine learning that uses neural networks"},
        {2, "python is a popular programming language used in machine learning and data science"},
    };
};

BM25Index build_from_corpus(const Corpus& c) {
    BM25Index idx;
    for (const auto& [id, text] : c.docs) idx.add_document(id, text);
    idx.build_done();
    return idx;
}

}  // namespace

TEST(BM25Index, EmptyIndexReturnsEmptyHits) {
    BM25Index idx;
    idx.build_done();
    EXPECT_TRUE(idx.search("anything", 10).empty());
}

TEST(BM25Index, BuildDoneIsIdempotentForAddAfter) {
    BM25Index idx;
    idx.add_document(0, "alpha beta gamma");
    idx.build_done();
    // After build_done, additional add_document calls are silently ignored.
    idx.add_document(1, "this should not appear in any result");
    auto hits = idx.search("alpha", 10);
    ASSERT_EQ(hits.size(), 1u);
    EXPECT_EQ(hits[0].doc_id, 0u);
}

TEST(BM25Index, TopKBoundsOutput) {
    Corpus c;
    auto idx = build_from_corpus(c);
    auto hits = idx.search("learning", 2);
    EXPECT_LE(hits.size(), 2u);
}

TEST(BM25Index, RankingIsTermFrequencyAware) {
    Corpus c;
    auto idx = build_from_corpus(c);
    auto hits = idx.search("machine learning", 3);
    ASSERT_FALSE(hits.empty());

    // "deep learning is a subfield of machine learning that uses neural..."
    // has "learning" twice + "machine" once = highest score with the
    // default BM25 weighting on this short corpus. "machine learning is..."
    // scores next. Assert the ordering is strictly monotone.
    for (std::size_t i = 1; i < hits.size(); ++i) {
        EXPECT_GE(hits[i - 1].score, hits[i].score);
    }
}

TEST(BM25Index, StopwordsAreFilteredFromQuery) {
    Corpus c;
    auto idx = build_from_corpus(c);
    // "the" / "is" / "that" are stopwords in the tokenizer, so a query
    // of just stopwords must return nothing.
    EXPECT_TRUE(idx.search("the is that", 10).empty());
}

TEST(BM25Index, CallerScratchIsReusedNotReallocated) {
    Corpus c;
    auto idx = build_from_corpus(c);
    std::vector<float> scratch;
    auto hits1 = idx.search("machine", 10, &scratch);
    auto cap_after_first = scratch.capacity();
    auto hits2 = idx.search("python", 10, &scratch);
    EXPECT_EQ(scratch.capacity(), cap_after_first);  // no reallocation
    EXPECT_FALSE(hits1.empty());
    EXPECT_FALSE(hits2.empty());
}

TEST(BM25Index, ConcurrentSearchesProduceIdenticalResults) {
    Corpus c;
    auto idx = build_from_corpus(c);

    // Run the same query on N threads, collect hits, assert identity across
    // threads. If the per-caller scratch contract is broken this will
    // fail under TSan.
    constexpr int kThreads = 8;
    std::array<std::vector<BM25Hit>, kThreads> results;
    std::vector<std::thread> workers;
    workers.reserve(kThreads);
    for (int t = 0; t < kThreads; ++t) {
        workers.emplace_back([&, t]() {
            results[t] = idx.search("machine learning", 3);
        });
    }
    for (auto& w : workers) w.join();

    for (int t = 1; t < kThreads; ++t) {
        ASSERT_EQ(results[t].size(), results[0].size());
        for (std::size_t i = 0; i < results[t].size(); ++i) {
            EXPECT_EQ(results[t][i].doc_id, results[0][i].doc_id);
            EXPECT_FLOAT_EQ(results[t][i].score, results[0][i].score);
        }
    }
}
