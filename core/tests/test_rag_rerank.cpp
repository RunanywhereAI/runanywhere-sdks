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

using runanywhere::rag::flatten_and_truncate;
using runanywhere::rag::kMaxChunkChars;
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

bool is_valid_utf8(const std::string& s) {
    size_t i = 0;
    while (i < s.size()) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        size_t need = 0;
        if (c < 0x80) {
            need = 0;
        } else if (c >= 0xC2 && c <= 0xDF) {
            need = 1;
        } else if (c >= 0xE0 && c <= 0xEF) {
            need = 2;
        } else if (c >= 0xF0 && c <= 0xF4) {
            need = 3;
        } else {
            return false;  // continuation byte or invalid lead
        }
        for (size_t k = 1; k <= need; ++k) {
            if (i + k >= s.size() || (static_cast<unsigned char>(s[i + k]) & 0xC0) != 0x80) {
                return false;  // truncated or malformed sequence
            }
        }
        if (need > 0) {
            const unsigned char second = static_cast<unsigned char>(s[i + 1]);
            if ((c == 0xE0 && second < 0xA0) ||
                (c == 0xED && second > 0x9F) ||
                (c == 0xF0 && second < 0x90) ||
                (c == 0xF4 && second > 0x8F)) {
                return false;
            }
        }
        i += need + 1;
    }
    return true;
}

}  // namespace

int main() {
    std::fprintf(stdout, "=== RAG rerank unit test ===\n");

    // --- flatten_and_truncate: whitespace substitution & budget intact ---
    {
        std::string raw = "First line\nSecond line\rThird line\tDone";
        std::string flattened = flatten_and_truncate(raw, kMaxChunkChars);
        CHECK(flattened == "First line Second line Third line Done",
              "whitespace flattened to single spaces");
        CHECK(is_valid_utf8(flattened), "flattened ASCII is valid UTF-8");
    }

    // --- flatten_and_truncate: ASCII truncation at limit ---
    {
        std::string long_ascii(500, 'x');
        std::string truncated = flatten_and_truncate(long_ascii, kMaxChunkChars);
        CHECK(truncated.size() == kMaxChunkChars, "ASCII text truncated at exact budget limit");
        CHECK(is_valid_utf8(truncated), "truncated ASCII is valid UTF-8");
    }

    // --- flatten_and_truncate: CJK multi-byte boundary holding across prefix shifts (#921) ---
    {
        // 3-byte CJK code points: 机器学习
        const std::string cjk_unit = "\xe6\x9c\xba\xe5\x99\xa8\xe5\xad\xa6\xe4\xb9\xa0";
        for (const char* prefix : {"", "a", "ab"}) {
            std::string text = prefix;
            for (int i = 0; i < 50; ++i) {
                text += cjk_unit;
            }
            std::string truncated = flatten_and_truncate(text, kMaxChunkChars);
            CHECK(truncated.size() <= kMaxChunkChars, "CJK truncated text within byte budget");
            CHECK(is_valid_utf8(truncated), "CJK truncated text never cuts mid-character");
            CHECK(truncated.size() >= kMaxChunkChars - 3,
                  "CJK truncation backs off at most one code point");
        }
    }

    // --- flatten_and_truncate: Cyrillic 2-byte boundary holding ---
    {
        // 2-byte code points: привет мир
        const std::string cyrillic_unit =
            "\xd0\xbf\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82 \xd0\xbc\xd0\xb8\xd1\x80 ";
        for (const char* prefix : {"", "a"}) {
            std::string text = prefix;
            for (int i = 0; i < 40; ++i) {
                text += cyrillic_unit;
            }
            std::string truncated = flatten_and_truncate(text, kMaxChunkChars);
            CHECK(truncated.size() <= kMaxChunkChars, "Cyrillic truncated text within byte budget");
            CHECK(is_valid_utf8(truncated), "Cyrillic truncated text never cuts mid-character");
        }
    }

    // --- flatten_and_truncate: Emoji 4-byte boundary holding ---
    {
        // 4-byte code points: 😀🎉🚀
        const std::string emoji_unit = "\xf0\x9f\x98\x80\xf0\x9f\x8e\x89\xf0\x9f\x9a\x80";
        for (const char* prefix : {"", "a", "ab", "abc"}) {
            std::string text = prefix;
            for (int i = 0; i < 50; ++i) {
                text += emoji_unit;
            }
            std::string truncated = flatten_and_truncate(text, kMaxChunkChars);
            CHECK(truncated.size() <= kMaxChunkChars, "Emoji truncated text within byte budget");
            CHECK(is_valid_utf8(truncated), "Emoji truncated text never cuts mid-character");
        }
    }

    // --- flatten_and_truncate: narrow budget smaller than single character ---
    {
        std::string single_cjk = "\xe6\x9c\xba";  // 3 bytes
        std::string truncated = flatten_and_truncate(single_cjk, 2);
        CHECK(truncated.empty(), "sub-character budget returns empty without partial code units");
        CHECK(is_valid_utf8(truncated), "sub-character result is valid UTF-8");
    }

    // --- flatten_and_truncate: reject malformed UTF-8 sequences ---
    {
        // Lone continuation byte (0x80..0xBF)
        std::string lone_continuation = "Hello\x80World";
        std::string res1 = flatten_and_truncate(lone_continuation, kMaxChunkChars);
        CHECK(res1 == "HelloWorld", "lone continuation byte is dropped");
        CHECK(is_valid_utf8(res1), "result is valid UTF-8");

        // Overlong 2-byte encoding of ASCII (0xC0, 0xC1)
        std::string overlong_2byte = "Over\xC0\xAFlong";
        std::string res2 = flatten_and_truncate(overlong_2byte, kMaxChunkChars);
        CHECK(res2 == "Overlong", "overlong 2-byte sequence is dropped");
        CHECK(is_valid_utf8(res2), "result is valid UTF-8");

        // Overlong 3-byte encoding (0xE0 with second byte < 0xA0)
        std::string overlong_3byte = "Over\xE0\x80\xAFlong";
        std::string res3 = flatten_and_truncate(overlong_3byte, kMaxChunkChars);
        CHECK(res3 == "Overlong", "overlong 3-byte sequence is dropped");
        CHECK(is_valid_utf8(res3), "result is valid UTF-8");

        // UTF-16 surrogate code point (0xED with second byte > 0x9F)
        std::string surrogate = "Surr\xED\xA0\x80ogate";
        std::string res4 = flatten_and_truncate(surrogate, kMaxChunkChars);
        CHECK(res4 == "Surrogate", "surrogate sequence is dropped");
        CHECK(is_valid_utf8(res4), "result is valid UTF-8");

        // Out-of-range codepoint > U+10FFFF (0xF4 with second byte > 0x8F, or lead > 0xF4)
        std::string out_of_range = "Out\xF4\x90\x80\x80of\xF5\x80\x80\x80range";
        std::string res5 = flatten_and_truncate(out_of_range, kMaxChunkChars);
        CHECK(res5 == "Outofrange", "out-of-range codepoint is dropped");
        CHECK(is_valid_utf8(res5), "result is valid UTF-8");
    }

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
