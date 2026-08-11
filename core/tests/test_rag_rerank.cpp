/**
 * @file test_rag_rerank.cpp
 * @brief Deterministic unit tests for RAG rerank parsing + reordering.
 *
 * Exercises parse_rerank_scores() and reorder_by_scores() directly, without a
 * live LLM, so the rerank logic is verified independent of model compliance
 * (small on-device models often don't emit the exact scoring format, in which
 * case the pipeline falls back to fused order — covered by test_rag_e2e).
 */

#include <cstdio>
#include <string>
#include <vector>

#include "features/rag/rag_rerank.h"
#include "features/rag/vector_store_usearch.h"

#ifdef RAC_HAVE_PROTOBUF
#include "rac/core/rac_error.h"
#include "rac/features/rag/rac_rag.h"

#include "rag.pb.h"
#endif

using runanywhere::rag::parse_rerank_scores;
using runanywhere::rag::reorder_by_scores;
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

std::vector<SearchResult> make_results(const std::vector<std::string>& ids) {
    std::vector<SearchResult> v;
    for (const auto& id : ids) {
        SearchResult r;
        r.id = id;
        r.text = id;
        v.push_back(r);
    }
    return v;
}

std::vector<std::string> ids_of(const std::vector<SearchResult>& v) {
    std::vector<std::string> out;
    for (const auto& r : v)
        out.push_back(r.id);
    return out;
}

}  // namespace

int main() {
    std::fprintf(stdout, "=== RAG rerank unit test ===\n");

    // --- parse: clean format ---
    {
        std::vector<int> s;
        size_t parsed = parse_rerank_scores("1: 5\n2: 3\n3: 4", 3, s);
        CHECK(parsed == 3 && s == std::vector<int>({5, 3, 4}), "clean '<i>: <s>' parses");
    }

    // --- parse: tolerant of prose / alternate separators ---
    {
        std::vector<int> s;
        size_t parsed = parse_rerank_scores("Passage 1 - 4\n2) 5", 2, s);
        CHECK(parsed == 2 && s == std::vector<int>({4, 5}), "prose/alt-separator parses");
    }

    // --- parse: score clamping to [1,5] ---
    {
        std::vector<int> s;
        parse_rerank_scores("1: 9\n2: 0", 2, s);
        CHECK(s == std::vector<int>({5, 1}), "scores clamp to [1,5]");
    }

    // --- parse: out-of-range index ignored ---
    {
        std::vector<int> s;
        size_t parsed = parse_rerank_scores("5: 3", 2, s);
        CHECK(parsed == 0 && s == std::vector<int>({0, 0}), "out-of-range index ignored");
    }

    // --- parse: unscorable output yields zero (pipeline falls back) ---
    {
        std::vector<int> s;
        size_t parsed = parse_rerank_scores("<index>1</index>", 2, s);
        CHECK(parsed == 0, "unscorable output -> 0 parsed (fallback path)");
    }

    // --- reorder: by descending score ---
    {
        auto r = make_results({"A", "B", "C"});
        reorder_by_scores(r, {1, 5, 3});
        CHECK(ids_of(r) == std::vector<std::string>({"B", "C", "A"}), "reorder by score desc");
    }

    // --- reorder: stable on ties (input order preserved) ---
    {
        auto r = make_results({"A", "B", "C"});
        reorder_by_scores(r, {2, 2, 5});
        CHECK(ids_of(r) == std::vector<std::string>({"C", "A", "B"}), "stable on tie");
    }

    // --- reorder: length mismatch is a no-op ---
    {
        auto r = make_results({"A", "B"});
        reorder_by_scores(r, {5});
        CHECK(ids_of(r) == std::vector<std::string>({"A", "B"}), "length mismatch = no-op");
    }

#ifdef RAC_HAVE_PROTOBUF
    // The dedicated cross-encoder reranker path previously gated here via
    // RAGConfiguration.reranker_model_id was deleted from rag.proto outright
    // (idl/rag.proto: RAGConfiguration no longer declares that field, not even
    // reserved -- confirmed by grep). rac_rag_proto_abi's matching
    // RAC_ERROR_NOT_IMPLEMENTED rejection was removed with it: rerank_results
    // (LLM-pointwise reranking with the session LLM) is now the only reranking
    // path, and it is fully wired via rag_pipeline_graph with no rejection
    // branch left to test here. There is nothing left for this RAG-gated case
    // to exercise; test_rerank.cpp still covers the standalone rerank
    // primitive/component contract independently of RAG.
#endif  // RAC_HAVE_PROTOBUF

    std::fprintf(stdout, "=== %d checks, %d failures ===\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
