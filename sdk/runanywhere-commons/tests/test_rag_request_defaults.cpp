/**
 * @file test_rag_request_defaults.cpp
 * @brief Parity tests for rac_rag_request_with_defaults_proto (P2-T14).
 *
 * Verifies the canonical RAGConfiguration defaults emitted by commons match
 * Swift's `RARAGConfiguration.defaults()`
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/
 * RAGProto+Helpers.swift). When the Swift extension is slimmed in P3, every
 * SDK will call into this ABI for default-population so a single source of
 * truth governs the values and the field-merge semantics.
 *
 * Coverage:
 *   - Empty inbound bytes → pure defaults (model ids empty, numerics canonical).
 *   - Inbound id strings (embedding_model_id / llm_model_id) pass through.
 *   - Inbound non-zero numerics (top_k / chunk_size / etc.) override defaults.
 *   - Negative paths: NULL out pointer, malformed bytes.
 */

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "rag.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                   \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
            return 1;                                                                       \
        }                                                                                   \
    } while (0)

#define ASSERT_EQ(a, b)                                                                            \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

#define ASSERT_FLOAT_EQ(a, b)                                                                      \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d (got=%f expected=%f)\n", #a, #b, \
                         __FILE__, __LINE__, static_cast<double>(a), static_cast<double>(b));      \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF

bool dispatch_with_defaults(const runanywhere::v1::RAGConfiguration& request,
                            runanywhere::v1::RAGConfiguration* out) {
    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        std::fprintf(stderr, "failed to serialize RAGConfiguration request\n");
        return false;
    }

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_rag_request_with_defaults_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buffer);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_rag_request_with_defaults_proto rc=%d\n", rc);
        rac_proto_buffer_free(&buffer);
        return false;
    }
    if (buffer.status != RAC_SUCCESS) {
        std::fprintf(stderr, "buffer.status=%d msg=%s\n", buffer.status,
                     buffer.error_message ? buffer.error_message : "(null)");
        rac_proto_buffer_free(&buffer);
        return false;
    }
    bool parsed = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return parsed;
}

// Verifies the returned proto bytes parse to the canonical default values
// from Swift's RARAGConfiguration.defaults() with empty input bytes:
//   embedding_model_id    = ""
//   llm_model_id          = ""
//   embedding_dimension   = 384
//   top_k                 = 5
//   similarity_threshold  = 0.7
//   chunk_size            = 512
//   chunk_overlap         = 64
int test_rag_defaults_with_empty_input() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_rag_request_with_defaults_proto(nullptr, 0, &buffer);
    ASSERT_EQ(rc, RAC_SUCCESS);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);

    runanywhere::v1::RAGConfiguration cfg;
    ASSERT_TRUE(cfg.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));

    ASSERT_EQ(cfg.embedding_model_id(), std::string(""));
    ASSERT_EQ(cfg.llm_model_id(), std::string(""));
    ASSERT_EQ(cfg.embedding_dimension(), 384);
    ASSERT_EQ(cfg.top_k(), 5);
    ASSERT_FLOAT_EQ(cfg.similarity_threshold(), 0.7f);
    ASSERT_EQ(cfg.chunk_size(), 512);
    ASSERT_EQ(cfg.chunk_overlap(), 64);

    rac_proto_buffer_free(&buffer);
    return 0;
}

// Verifies the inbound id strings pass through verbatim while the numeric
// canonical defaults remain. Mirrors Swift's
//   RARAGConfiguration.defaults(embeddingModelID: "embed-v1", llmModelID: "llm-v1")
int test_rag_defaults_with_inbound_ids() {
    runanywhere::v1::RAGConfiguration request;
    request.set_embedding_model_id("embed-v1");
    request.set_llm_model_id("llm-v1");

    runanywhere::v1::RAGConfiguration cfg;
    ASSERT_TRUE(dispatch_with_defaults(request, &cfg));

    ASSERT_EQ(cfg.embedding_model_id(), std::string("embed-v1"));
    ASSERT_EQ(cfg.llm_model_id(), std::string("llm-v1"));
    // Numerics still canonical — caller did not override.
    ASSERT_EQ(cfg.embedding_dimension(), 384);
    ASSERT_EQ(cfg.top_k(), 5);
    ASSERT_FLOAT_EQ(cfg.similarity_threshold(), 0.7f);
    ASSERT_EQ(cfg.chunk_size(), 512);
    ASSERT_EQ(cfg.chunk_overlap(), 64);
    return 0;
}

// Verifies inbound non-zero numerics override the canonical defaults.
int test_rag_defaults_with_numeric_overrides() {
    runanywhere::v1::RAGConfiguration request;
    request.set_top_k(10);
    request.set_embedding_dimension(512);
    request.set_similarity_threshold(0.9f);
    request.set_chunk_size(1024);
    request.set_chunk_overlap(128);

    runanywhere::v1::RAGConfiguration cfg;
    ASSERT_TRUE(dispatch_with_defaults(request, &cfg));

    ASSERT_EQ(cfg.top_k(), 10);
    ASSERT_EQ(cfg.embedding_dimension(), 512);
    ASSERT_FLOAT_EQ(cfg.similarity_threshold(), 0.9f);
    ASSERT_EQ(cfg.chunk_size(), 1024);
    ASSERT_EQ(cfg.chunk_overlap(), 128);
    // String ids untouched.
    ASSERT_EQ(cfg.embedding_model_id(), std::string(""));
    ASSERT_EQ(cfg.llm_model_id(), std::string(""));
    return 0;
}

// Verifies that explicitly setting a numeric field to zero is honored
// post-defaults (proto3 `optional` semantics). This guards the fix for
// idl-008-A: callers who explicitly want chunk_overlap=0 (no overlap)
// must not have it silently replaced by the canonical default of 64.
int test_rag_defaults_preserves_explicit_zero() {
    runanywhere::v1::RAGConfiguration request;
    request.set_chunk_overlap(0);
    request.set_top_k(0);
    request.set_similarity_threshold(0.0f);

    runanywhere::v1::RAGConfiguration cfg;
    ASSERT_TRUE(dispatch_with_defaults(request, &cfg));

    ASSERT_EQ(cfg.chunk_overlap(), 0);
    ASSERT_EQ(cfg.top_k(), 0);
    ASSERT_FLOAT_EQ(cfg.similarity_threshold(), 0.0f);
    // Unset numeric fields still receive canonical defaults.
    ASSERT_EQ(cfg.embedding_dimension(), 384);
    ASSERT_EQ(cfg.chunk_size(), 512);
    return 0;
}

// Verifies optional string overrides (prompt_template, reranker_model_id, etc.)
// pass through verbatim.
int test_rag_defaults_with_optional_strings() {
    runanywhere::v1::RAGConfiguration request;
    request.set_embedding_model_id("embed-v2");
    request.set_llm_model_id("llm-v2");
    request.set_prompt_template("custom prompt: {context}\n{question}");
    request.set_reranker_model_id("rerank-v1");
    request.set_index_path("/tmp/index");

    runanywhere::v1::RAGConfiguration cfg;
    ASSERT_TRUE(dispatch_with_defaults(request, &cfg));

    ASSERT_EQ(cfg.embedding_model_id(), std::string("embed-v2"));
    ASSERT_EQ(cfg.llm_model_id(), std::string("llm-v2"));
    ASSERT_EQ(cfg.prompt_template(), std::string("custom prompt: {context}\n{question}"));
    ASSERT_EQ(cfg.reranker_model_id(), std::string("rerank-v1"));
    ASSERT_EQ(cfg.index_path(), std::string("/tmp/index"));
    return 0;
}

int test_rag_defaults_null_out() {
    rac_result_t rc = rac_rag_request_with_defaults_proto(nullptr, 0, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

int test_rag_defaults_invalid_input_bytes() {
    // Non-zero size with NULL data is invalid.
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_rag_request_with_defaults_proto(nullptr, 42, &buffer);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&buffer);
    return 0;
}

int test_rag_defaults_malformed_input_bytes() {
    // Wire-format garbage that does not parse as a RAGConfiguration.
    static const uint8_t kGarbage[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_rag_request_with_defaults_proto(kGarbage, sizeof(kGarbage), &buffer);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&buffer);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("SKIP: RAC_HAVE_PROTOBUF not defined; RAG request defaults tests skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {"rag_defaults_with_empty_input", test_rag_defaults_with_empty_input},
        {"rag_defaults_with_inbound_ids", test_rag_defaults_with_inbound_ids},
        {"rag_defaults_with_numeric_overrides", test_rag_defaults_with_numeric_overrides},
        {"rag_defaults_preserves_explicit_zero", test_rag_defaults_preserves_explicit_zero},
        {"rag_defaults_with_optional_strings", test_rag_defaults_with_optional_strings},
        {"rag_defaults_null_out", test_rag_defaults_null_out},
        {"rag_defaults_invalid_input_bytes", test_rag_defaults_invalid_input_bytes},
        {"rag_defaults_malformed_input_bytes", test_rag_defaults_malformed_input_bytes},
    };

    int failures = 0;
    for (const auto& t : kTests) {
        std::printf("RUN  %s\n", t.name);
        int rc = t.fn();
        if (rc != 0) {
            std::printf("FAIL %s\n", t.name);
            failures++;
        } else {
            std::printf("PASS %s\n", t.name);
        }
    }

    if (failures > 0) {
        std::fprintf(stderr, "\n%d test(s) failed.\n", failures);
        return 1;
    }
    std::printf("\nAll %zu test(s) passed.\n", sizeof(kTests) / sizeof(kTests[0]));
    return 0;
#endif
}
