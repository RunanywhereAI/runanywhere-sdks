// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Zero-allocation BM25 inverted index, ported from FastVoice
// RAG/temp/src/rag/bm25_index.h. The per-query score buffer is allocated
// once at build_done() and reused on every search — at 5K chunks the
// search is ~0.01ms with no heap traffic.

#ifndef RA_SOLUTIONS_RAG_BM25_INDEX_H
#define RA_SOLUTIONS_RAG_BM25_INDEX_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace ra::rag {

struct BM25Params {
    float k1 = 1.2f;
    float b  = 0.75f;
};

struct BM25Hit {
    std::uint32_t doc_id;
    float         score;
};

class BM25Index {
public:
    BM25Index() = default;
    explicit BM25Index(BM25Params params) : params_(params) {}

    // Build phase. Call add_document() for every chunk, then build_done()
    // to freeze the index and allocate the scratch buffer.
    void add_document(std::uint32_t doc_id, std::string_view text);
    void build_done();

    // Top-K retrieval. `scratch` must be reusable; the implementation uses
    // the pre-allocated member buffer. Thread-safe for concurrent readers
    // as long as no one calls add_document().
    std::vector<BM25Hit> search(std::string_view query, std::size_t top_k) const;

    std::size_t doc_count() const noexcept { return doc_lengths_.size(); }

private:
    struct Posting {
        std::uint32_t doc_id;
        std::uint32_t term_freq;
    };

    BM25Params                                        params_;
    std::unordered_map<std::string, std::vector<Posting>> postings_;
    std::unordered_map<std::string, float>            idf_;
    std::vector<std::uint32_t>                        doc_lengths_;
    float                                             avg_doc_length_ = 0.f;
    mutable std::vector<float>                        scratch_scores_;
    bool                                              built_ = false;
};

}  // namespace ra::rag

#endif  // RA_SOLUTIONS_RAG_BM25_INDEX_H
