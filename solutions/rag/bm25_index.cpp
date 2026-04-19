// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "bm25_index.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <unordered_set>

namespace ra::rag {

namespace {

const std::unordered_set<std::string> kStopwords = {
    "a", "an", "the", "and", "or", "but", "of", "in", "on", "to", "is",
    "it", "for", "with", "this", "that", "by", "as", "at"
};

std::vector<std::string> tokenize(std::string_view text) {
    std::vector<std::string> out;
    std::string token;
    token.reserve(16);
    for (char c : text) {
        if (std::isalnum(static_cast<unsigned char>(c))) {
            token.push_back(static_cast<char>(
                std::tolower(static_cast<unsigned char>(c))));
        } else if (!token.empty()) {
            if (kStopwords.find(token) == kStopwords.end()) {
                out.push_back(std::move(token));
            }
            token.clear();
        }
    }
    if (!token.empty() && kStopwords.find(token) == kStopwords.end()) {
        out.push_back(std::move(token));
    }
    return out;
}

}  // namespace

void BM25Index::add_document(std::uint32_t doc_id, std::string_view text) {
    if (built_) return;  // idempotent after build_done

    auto tokens = tokenize(text);
    if (doc_id >= doc_lengths_.size()) {
        doc_lengths_.resize(doc_id + 1, 0);
    }
    doc_lengths_[doc_id] = static_cast<std::uint32_t>(tokens.size());

    std::unordered_map<std::string, std::uint32_t> tf;
    for (auto& tok : tokens) ++tf[tok];
    for (auto& [term, freq] : tf) {
        postings_[term].push_back({doc_id, freq});
    }
}

void BM25Index::build_done() {
    const auto n = static_cast<float>(doc_lengths_.size());
    if (n == 0.f) { built_ = true; return; }

    std::uint64_t total_len = 0;
    for (auto l : doc_lengths_) total_len += l;
    avg_doc_length_ = static_cast<float>(total_len) / n;

    idf_.reserve(postings_.size());
    for (const auto& [term, postings] : postings_) {
        const float df = static_cast<float>(postings.size());
        idf_[term] = std::log((n - df + 0.5f) / (df + 0.5f) + 1.f);
    }

    scratch_scores_.assign(doc_lengths_.size(), 0.f);
    built_ = true;
}

std::vector<BM25Hit> BM25Index::search(std::string_view query,
                                        std::size_t      top_k) const {
    if (!built_ || doc_lengths_.empty()) return {};

    std::fill(scratch_scores_.begin(), scratch_scores_.end(), 0.f);
    auto tokens = tokenize(query);
    for (const auto& tok : tokens) {
        auto p_it = postings_.find(tok);
        if (p_it == postings_.end()) continue;
        auto i_it = idf_.find(tok);
        if (i_it == idf_.end()) continue;
        const float idf = i_it->second;
        for (const auto& posting : p_it->second) {
            const float doc_len = static_cast<float>(
                doc_lengths_[posting.doc_id]);
            const float tf = static_cast<float>(posting.term_freq);
            const float denom = tf + params_.k1 *
                (1.f - params_.b + params_.b * doc_len / avg_doc_length_);
            scratch_scores_[posting.doc_id] += idf * (tf * (params_.k1 + 1.f))
                / denom;
        }
    }

    std::vector<BM25Hit> hits;
    hits.reserve(scratch_scores_.size());
    for (std::uint32_t i = 0; i < scratch_scores_.size(); ++i) {
        if (scratch_scores_[i] > 0.f) {
            hits.push_back({i, scratch_scores_[i]});
        }
    }
    std::partial_sort(hits.begin(),
        hits.begin() + std::min(top_k, hits.size()),
        hits.end(),
        [](const BM25Hit& a, const BM25Hit& b) { return a.score > b.score; });
    if (hits.size() > top_k) hits.resize(top_k);
    return hits;
}

}  // namespace ra::rag
