/**
 * @file test_rerank.cpp
 * @brief Contract test for the revived reranking primitive (RAC_PRIMITIVE_RERANK).
 *
 * Backend-neutral: registers a small in-test fake rerank engine (no model file,
 * no llama.cpp) and asserts:
 *   - RAC_PLUGIN_API_VERSION == 8 and the primitive/vtable-slot wiring.
 *   - A registered rerank engine routes via rac_plugin_find(RAC_PRIMITIVE_RERANK)
 *     and rac_engine_vtable_slot() resolves rerank_ops.
 *   - Full RerankRequest → RerankResult proto round-trip through the component
 *     ABI, including score-descending ordering, ranks, original indices, and id
 *     echo.
 *   - Graceful failure on null args, missing model (not loaded), and a missing
 *     rerank backend (none registered).
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/features/rerank/rac_rerank.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

#include "rag.pb.h"
#include "rerank.pb.h"

namespace {

int g_failures = 0;

void check(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        ++g_failures;
    }
}

// ---- Fake rerank engine (scores each candidate by its text length) ----------

// Mirrors the real llamacpp reranker: create/initialize receive the resolved
// model PATH, and the backend echoes that path back as rac_rerank_result_t
// .model_id. This lets the round-trip below prove that commons reports the
// LOGICAL model id (not the on-device path) in the proto.
struct FakeRerankImpl {
    std::string load_path;
};

rac_result_t fake_create(const char* model_id, const char* /*config*/, void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = new FakeRerankImpl{};
    return RAC_SUCCESS;
}

rac_result_t fake_initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    static_cast<FakeRerankImpl*>(impl)->load_path = model_path;
    return RAC_SUCCESS;
}

rac_result_t fake_rerank(void* impl, const char* query, const rac_rerank_candidate_t* candidates,
                         size_t candidate_count, const rac_rerank_options_t* options,
                         rac_rerank_result_t* out_result) {
    if (!impl || !query || !out_result || (candidate_count > 0 && !candidates)) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_result = {};

    struct Scored {
        float score;
        uint32_t original_index;
        const char* id;
    };
    std::vector<Scored> scored;
    scored.reserve(candidate_count);
    for (size_t i = 0; i < candidate_count; ++i) {
        const char* text = candidates[i].text ? candidates[i].text : "";
        scored.push_back(
            Scored{static_cast<float>(std::strlen(text)), static_cast<uint32_t>(i), candidates[i].id});
    }
    // Stable sort by descending score (longer text = more "relevant").
    for (size_t i = 0; i + 1 < scored.size(); ++i) {
        for (size_t j = i + 1; j < scored.size(); ++j) {
            if (scored[j].score > scored[i].score) {
                std::swap(scored[i], scored[j]);
            }
        }
    }

    size_t emit = scored.size();
    const uint32_t top_n = options ? options->top_n : 0;
    if (top_n > 0 && static_cast<size_t>(top_n) < emit) {
        emit = top_n;
    }

    // Echo the resolved LOAD PATH (as the llamacpp reranker does), not a clean
    // logical id — commons must still surface the logical id in the proto.
    const auto* fake = static_cast<const FakeRerankImpl*>(impl);
    out_result->model_id =
        strdup(fake->load_path.empty() ? "fake-reranker" : fake->load_path.c_str());
    out_result->processing_time_ms = 1;
    if (emit == 0) {
        return RAC_SUCCESS;
    }
    out_result->items = static_cast<rac_rerank_scored_item_t*>(
        std::calloc(emit, sizeof(rac_rerank_scored_item_t)));
    if (!out_result->items) {
        rac_rerank_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->item_count = emit;
    for (size_t i = 0; i < emit; ++i) {
        out_result->items[i].score = scored[i].score;
        out_result->items[i].original_index = scored[i].original_index;
        out_result->items[i].rank = static_cast<uint32_t>(i);
        out_result->items[i].id = scored[i].id ? strdup(scored[i].id) : nullptr;
    }
    return RAC_SUCCESS;
}

rac_result_t fake_cleanup(void* /*impl*/) { return RAC_SUCCESS; }

void fake_destroy(void* impl) { delete static_cast<FakeRerankImpl*>(impl); }

const rac_rerank_service_ops_t g_fake_rerank_ops = {
    /* initialize */ fake_initialize,
    /* rerank     */ fake_rerank,
    /* cleanup    */ fake_cleanup,
    /* destroy    */ fake_destroy,
    /* create     */ fake_create,
};

rac_engine_vtable_t make_fake_vtable() {
    rac_engine_vtable_t vt{};
    vt.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vt.metadata.name = "fake_rerank";
    vt.metadata.display_name = "Fake Reranker";
    vt.metadata.engine_version = "0.0.0";
    vt.metadata.priority = 10;
    vt.rerank_ops = &g_fake_rerank_ops;
    return vt;
}

std::string build_request(const std::string& query,
                          const std::vector<std::pair<std::string, std::string>>& candidates,
                          uint32_t top_n) {
    runanywhere::v1::RerankRequest request;
    request.set_query(query);
    for (const auto& [id, text] : candidates) {
        auto* candidate = request.add_candidates();
        candidate->set_id(id);
        candidate->set_text(text);
    }
    if (top_n > 0) {
        request.mutable_options()->set_top_n(top_n);
    }
    return request.SerializeAsString();
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_rerank\n");

    // (1) ABI + primitive naming.
    check(RAC_PLUGIN_API_VERSION == 8u, "RAC_PLUGIN_API_VERSION must be 8");
    check(std::strcmp(rac_primitive_name(RAC_PRIMITIVE_RERANK), "rerank") == 0,
          "rac_primitive_name(RAC_PRIMITIVE_RERANK) == \"rerank\"");
    check(static_cast<int>(RAC_PRIMITIVE_RERANK) == 11, "RAC_PRIMITIVE_RERANK wire value is 11");

    // (2) No backend registered yet → create fails gracefully, no route.
    check(rac_plugin_find(RAC_PRIMITIVE_RERANK) == nullptr,
          "no rerank plugin before registration");
    rac_handle_t no_engine = nullptr;
    check(rac_rerank_create("some-model", &no_engine) == RAC_ERROR_BACKEND_NOT_FOUND,
          "rac_rerank_create with no engine → BACKEND_NOT_FOUND");
    check(no_engine == nullptr, "no service handle produced without a backend");
    check(rac_rerank_create(nullptr, &no_engine) == RAC_ERROR_NULL_POINTER,
          "rac_rerank_create(nullptr) → NULL_POINTER");

    // (3) Register the fake engine and assert routing + slot resolution.
    static rac_engine_vtable_t fake_vt = make_fake_vtable();
    check(rac_plugin_register(&fake_vt) == RAC_SUCCESS, "fake rerank engine registers");
    const rac_engine_vtable_t* found = rac_plugin_find(RAC_PRIMITIVE_RERANK);
    check(found == &fake_vt, "rac_plugin_find(RAC_PRIMITIVE_RERANK) returns the fake engine");
    check(rac_engine_vtable_slot(&fake_vt, RAC_PRIMITIVE_RERANK) == fake_vt.rerank_ops,
          "rac_engine_vtable_slot resolves rerank_ops");

    // (4) Component lifecycle + proto round-trip against the fake backend.
    rac_handle_t component = nullptr;
    check(rac_rerank_component_create(&component) == RAC_SUCCESS && component != nullptr,
          "rerank component created");

    // Missing-model: reranking before a model is loaded fails gracefully.
    {
        const std::string request_bytes =
            build_request("q", {{"a", "alpha"}}, /*top_n=*/0);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc != RAC_SUCCESS, "rerank before load → error (not loaded)");
        rac_proto_buffer_free(&out);
    }

    check(rac_rerank_component_load_model(component, "/tmp/fake-reranker", "fake-reranker",
                                          "Fake Reranker") == RAC_SUCCESS,
          "rerank component loads via the fake engine");
    check(rac_rerank_component_is_loaded(component) == RAC_TRUE, "component reports loaded");

    {
        // Text lengths: "short"=5, "a considerably longer passage"=30, "medium len"=10.
        const std::string request_bytes = build_request(
            "which is most relevant",
            {{"a", "short"}, {"b", "a considerably longer passage"}, {"c", "medium len"}},
            /*top_n=*/0);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "rerank_proto succeeds against a loaded model");

        uint8_t* data = nullptr;
        size_t size = 0;
        check(rac_proto_buffer_take_data(&out, &data, &size) == RAC_SUCCESS,
              "rerank result buffer holds serialized proto");
        runanywhere::v1::RerankResult result;
        check(result.ParseFromArray(data, static_cast<int>(size)), "RerankResult parses");
        check(result.items_size() == 3, "all three candidates returned, ranked");
        if (result.items_size() == 3) {
            // Expected descending order: b (30) > c (10) > a (5).
            check(result.items(0).id() == "b" && result.items(0).original_index() == 1 &&
                      result.items(0).rank() == 0,
                  "rank 0 is candidate b (longest)");
            check(result.items(1).id() == "c" && result.items(1).original_index() == 2 &&
                      result.items(1).rank() == 1,
                  "rank 1 is candidate c");
            check(result.items(2).id() == "a" && result.items(2).original_index() == 0 &&
                      result.items(2).rank() == 2,
                  "rank 2 is candidate a (shortest)");
            check(result.items(0).score() >= result.items(1).score() &&
                      result.items(1).score() >= result.items(2).score(),
                  "scores are monotonically non-increasing");
        }
        // The backend echoed the load path ("/tmp/fake-reranker"); commons must
        // report the LOGICAL model id ("fake-reranker"), never the device path.
        check(result.model_id() == "fake-reranker",
              "result carries the logical model id, not the backend-reported load path");
        std::free(data);
        rac_proto_buffer_free(&out);
    }

    // top_n truncation.
    {
        const std::string request_bytes = build_request(
            "q", {{"a", "short"}, {"b", "a considerably longer passage"}, {"c", "medium len"}},
            /*top_n=*/2);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "rerank_proto with top_n succeeds");
        uint8_t* data = nullptr;
        size_t size = 0;
        if (rac_proto_buffer_take_data(&out, &data, &size) == RAC_SUCCESS) {
            runanywhere::v1::RerankResult result;
            check(result.ParseFromArray(data, static_cast<int>(size)) && result.items_size() == 2,
                  "top_n=2 truncates to two items");
            std::free(data);
        }
        rac_proto_buffer_free(&out);
    }

    // Empty candidate list is a valid request: the component returns a
    // well-formed, empty result rather than an error.
    {
        const std::string request_bytes = build_request("q", {}, /*top_n=*/0);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "rerank with zero candidates succeeds");
        uint8_t* data = nullptr;
        size_t size = 0;
        if (rac_proto_buffer_take_data(&out, &data, &size) == RAC_SUCCESS) {
            runanywhere::v1::RerankResult result;
            check(result.ParseFromArray(data, static_cast<int>(size)) && result.items_size() == 0,
                  "zero-candidate result carries no items");
            std::free(data);
        }
        rac_proto_buffer_free(&out);
    }

    // top_n larger than the candidate count clamps to all available candidates.
    {
        const std::string request_bytes =
            build_request("q", {{"a", "short"}, {"b", "longer text"}}, /*top_n=*/9);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "rerank with an oversized top_n succeeds");
        uint8_t* data = nullptr;
        size_t size = 0;
        if (rac_proto_buffer_take_data(&out, &data, &size) == RAC_SUCCESS) {
            runanywhere::v1::RerankResult result;
            check(result.ParseFromArray(data, static_cast<int>(size)) && result.items_size() == 2,
                  "top_n greater than the candidate count returns all candidates");
            std::free(data);
        }
        rac_proto_buffer_free(&out);
    }

    // A candidate with empty text is still ranked (scored by length 0) and kept
    // in the result, ordered below any longer candidate.
    {
        const std::string request_bytes =
            build_request("q", {{"empty", ""}, {"full", "meaningful passage"}}, /*top_n=*/0);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "rerank with an empty-text candidate succeeds");
        uint8_t* data = nullptr;
        size_t size = 0;
        if (rac_proto_buffer_take_data(&out, &data, &size) == RAC_SUCCESS) {
            runanywhere::v1::RerankResult result;
            const bool shape =
                result.ParseFromArray(data, static_cast<int>(size)) && result.items_size() == 2;
            check(shape, "empty-text candidate is still returned, ranked");
            if (shape) {
                check(result.items(0).id() == "full" && result.items(1).id() == "empty",
                      "empty-text candidate ranks below a longer candidate");
            }
            std::free(data);
        }
        rac_proto_buffer_free(&out);
    }

    // Invalid request (empty query) is rejected gracefully with an error buffer.
    {
        const std::string request_bytes = build_request("", {{"a", "alpha"}}, 0);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_rerank_component_rerank_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc != RAC_SUCCESS, "empty-query request rejected");
        rac_proto_buffer_free(&out);
    }

    rac_rerank_component_destroy(component);

    // (5) Standalone request/result proto round-trip (no backend involved).
    {
        const std::string request_bytes = build_request("hello", {{"x", "world"}}, 5);
        runanywhere::v1::RerankRequest parsed;
        check(parsed.ParseFromString(request_bytes) && parsed.query() == "hello" &&
                  parsed.candidates_size() == 1 && parsed.candidates(0).id() == "x" &&
                  parsed.options().top_n() == 5,
              "RerankRequest proto round-trips");

        runanywhere::v1::RerankResult result;
        auto* item = result.add_items();
        item->set_id("x");
        item->set_score(1.5f);
        item->set_original_index(0);
        item->set_rank(0);
        result.set_model_id("m");
        std::string result_bytes = result.SerializeAsString();
        runanywhere::v1::RerankResult reparsed;
        check(reparsed.ParseFromString(result_bytes) && reparsed.items_size() == 1 &&
                  reparsed.items(0).id() == "x" && reparsed.items(0).score() == 1.5f,
              "RerankResult proto round-trips");
    }

    rac_plugin_unregister("fake_rerank");
    check(rac_plugin_find(RAC_PRIMITIVE_RERANK) == nullptr,
          "rerank route removed after unregister");

    // NOTE: this target only covers the standalone rerank primitive/component via
    // the fake engine above; it intentionally does NOT link RAG (rac_rag_* symbols
    // are absent on RAG-disabled presets such as rcli-*-release), so it must not
    // reference rac_rag_session_create_proto here. RAG's session-create handling of
    // reranker_model_id — currently a fail-fast RAC_ERROR_NOT_IMPLEMENTED rejection
    // because the query-time cross-encoder path is not yet wired — is exercised by
    // test_rag_rerank.cpp (which links the RAG pipeline and asserts that rejection),
    // not here.

    if (g_failures == 0) {
        std::fprintf(stdout, "  ok: rerank primitive wiring, routing, proto round-trip, graceful "
                             "failure\n");
        return 0;
    }
    std::fprintf(stderr, "test_rerank: %d checks failed\n", g_failures);
    return 1;
}
