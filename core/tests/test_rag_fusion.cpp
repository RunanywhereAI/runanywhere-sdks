/**
 * @file test_rag_fusion.cpp
 * @brief Deterministic unit tests for RRF fusion + multi-query variant parsing.
 *
 * Verifies the LLM-independent halves of multi-query expansion (Item 6): the
 * N-way Reciprocal Rank Fusion math and the query-rewrite parser, without a
 * live model. The LLM generation itself is exercised for robustness in
 * test_rag_e2e.
 */

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#include "features/rag/rag_fusion.h"

using runanywhere::rag::fuse_rankings;
using runanywhere::rag::parse_query_variants;
using runanywhere::rag::SearchResult;

namespace {
int g_checks = 0;
int g_failures = 0;

#define CHECK(cond, label)                                                           \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (cond) {                                                                  \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                           \
    } while (0)

std::vector<std::string> ids_of(const std::vector<SearchResult>& v) {
    std::vector<std::string> out;
    for (const auto& r : v)
        out.push_back(r.id);
    return out;
}
}  // namespace

int main() {
    std::fprintf(stdout, "=== RAG fusion unit test ===\n");

    // --- single ranking: order preserved ---
    {
        auto f = fuse_rankings({{"a", "b", "c"}}, nullptr, 10);
        CHECK(ids_of(f) == std::vector<std::string>({"a", "b", "c"}), "single ranking preserves order");
    }

    // --- two rankings: an id ranked in both outranks singletons ---
    {
        // "b" appears rank-2 in list1 and rank-1 in list2 → highest combined.
        auto f = fuse_rankings({{"a", "b"}, {"b", "c"}}, nullptr, 10);
        CHECK(!f.empty() && f[0].id == "b", "id present in both rankings ranks first");
    }

    // --- top_k truncation ---
    {
        auto f = fuse_rankings({{"a", "b", "c", "d", "e"}}, nullptr, 2);
        CHECK(f.size() == 2, "top_k truncates result set");
    }

    // --- scores normalized into [0,1] ---
    {
        auto f = fuse_rankings({{"a"}, {"a"}}, nullptr, 10);
        CHECK(f.size() == 1 && f[0].score > 0.0f && f[0].score <= 1.0f,
              "fused score normalized to (0,1]");
    }

    // --- empty input ---
    {
        auto f = fuse_rankings({}, nullptr, 10);
        CHECK(f.empty(), "empty rankings -> empty result");
    }

    // --- variant parsing: dash list ---
    {
        auto v = parse_query_variants("- how does zephyr dedupe\n- zephyr duplicate avoidance",
                                      "orig", 3);
        CHECK(v.size() == 2, "dash-list variants parsed");
    }

    // --- variant parsing: numbered list + original dropped + count cap ---
    {
        auto v = parse_query_variants("1. first variant here\n2. orig\n3. second variant here\n"
                                      "4. third variant here",
                                      "orig", 2);
        CHECK(v.size() == 2, "count cap honored");
        CHECK(std::find(v.begin(), v.end(), std::string("orig")) == v.end(),
              "original query not echoed as a variant");
    }

    // --- variant parsing: too-short lines dropped ---
    {
        auto v = parse_query_variants("- ok\n- a valid longer variant", "orig", 5);
        CHECK(v.size() == 1, "too-short variant dropped");
    }

    std::fprintf(stdout, "=== %d checks, %d failures ===\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
