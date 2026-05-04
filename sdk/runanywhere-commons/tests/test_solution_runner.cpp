// SPDX-License-Identifier: Apache-2.0
//
// test_solution_runner.cpp — T4.7 lifecycle + C ABI tests.

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <utility>

#if defined(RAC_HAVE_PROTOBUF)
#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "rac/solutions/config_loader.hpp"
#include "rac/solutions/rac_solution.h"
#include "rac/solutions/solution_converter.hpp"
#include "rac/solutions/solution_runner.hpp"
#include "solutions.pb.h"

namespace {

int g_failed = 0;
int g_passed = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__, #cond); \
            g_failed++;                                                        \
            return;                                                            \
        }                                                                      \
    } while (0)

#define TEST(name)                                                             \
    static void test_##name();                                                 \
    static void run_test_##name() {                                            \
        std::fprintf(stderr, "[RUN ] %s\n", #name);                            \
        int before_failed = g_failed;                                          \
        test_##name();                                                         \
        if (g_failed == before_failed) {                                       \
            std::fprintf(stderr, "[  OK] %s\n", #name);                        \
            g_passed++;                                                        \
        }                                                                      \
    }                                                                          \
    static void test_##name()

using rac::solutions::SolutionRunner;
using runanywhere::v1::PipelineSpec;
using runanywhere::v1::SolutionConfig;

PipelineSpec make_linear_spec() {
    PipelineSpec spec;
    spec.set_name("run_linear");
    auto* a = spec.add_operators();
    a->set_name("src");
    a->set_type("source");
    auto* b = spec.add_operators();
    b->set_name("mid");
    b->set_type("echo");
    auto* c = spec.add_operators();
    c->set_name("snk");
    c->set_type("sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src");
    e1->set_to("mid");
    auto* e2 = spec.add_edges();
    e2->set_from("mid");
    e2->set_to("snk");
    return spec;
}

// ---------------------------------------------------------------------------
// 1. Full lifecycle: start + feed + close + wait.
// ---------------------------------------------------------------------------
TEST(start_feed_close_lifecycle) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed("hello") == RAC_SUCCESS);
    CHECK(runner.feed("world") == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
    CHECK(!runner.running());
}

// ---------------------------------------------------------------------------
// 2. Double-start returns ALREADY_INITIALIZED.
// ---------------------------------------------------------------------------
TEST(double_start_is_rejected) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.start() == RAC_ERROR_ALREADY_INITIALIZED);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 3. cancel() fires mid-stream and the scheduler joins.
// ---------------------------------------------------------------------------
TEST(cancel_mid_stream_joins) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);

    // Feed a few items but never close — the runner should only exit
    // because we cancel.
    for (int i = 0; i < 4; ++i) {
        CHECK(runner.feed("item") == RAC_SUCCESS);
    }
    runner.cancel();

    // Wait should return within a bounded time (cancellation deadline
    // in the graph runtime is ~50ms).
    auto start = std::chrono::steady_clock::now();
    runner.wait();
    auto elapsed = std::chrono::steady_clock::now() - start;
    CHECK(elapsed < std::chrono::seconds(5));
    CHECK(!runner.running());
}

// ---------------------------------------------------------------------------
// 4. feed() before start is a user error.
// ---------------------------------------------------------------------------
TEST(feed_before_start_fails) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.feed("x") == RAC_ERROR_COMPONENT_NOT_READY);
}

// ---------------------------------------------------------------------------
// 5. SolutionConfig (VoiceAgent) expands + compiles.
// ---------------------------------------------------------------------------
TEST(voice_agent_solution_compiles) {
    SolutionConfig cfg;
    auto* va = cfg.mutable_voice_agent();
    va->set_llm_model_id("qwen3-4b");
    va->set_stt_model_id("whisper");
    va->set_tts_model_id("kokoro");
    va->set_vad_model_id("silero");

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_SUCCESS);
    // Confirm the expanded spec has the expected topology.
    const auto& spec = runner.spec();
    CHECK(spec.operators_size() == 4);
    CHECK(spec.edges_size() == 3);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 6. SolutionConfig (RAG) expands + compiles.
// ---------------------------------------------------------------------------
TEST(rag_solution_compiles) {
    SolutionConfig cfg;
    auto* rag = cfg.mutable_rag();
    rag->set_embed_model_id("bge-small");
    rag->set_llm_model_id("qwen3-4b");
    rag->set_retrieve_k(12);

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_SUCCESS);
    const auto& spec = runner.spec();
    CHECK(spec.operators_size() == 5);
    CHECK(spec.edges_size() == 4);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 7. C ABI end-to-end: proto-bytes path.
// ---------------------------------------------------------------------------
TEST(c_abi_proto_bytes_lifecycle) {
    SolutionConfig cfg;
    auto* rag = cfg.mutable_rag();
    rag->set_embed_model_id("bge-small");
    rag->set_llm_model_id("qwen3-4b");
    rag->set_retrieve_k(8);

    std::string buf;
    CHECK(cfg.SerializeToString(&buf));

    rac_solution_handle_t h = nullptr;
    rac_result_t st = rac_solution_create_from_proto(buf.data(), buf.size(), &h);
    CHECK(st == RAC_SUCCESS);
    CHECK(h != nullptr);

    CHECK(rac_solution_start(h) == RAC_SUCCESS);
    CHECK(rac_solution_feed(h, "why is the sky blue?") == RAC_SUCCESS);
    CHECK(rac_solution_close_input(h) == RAC_SUCCESS);
    rac_solution_destroy(h);
}

// ---------------------------------------------------------------------------
// 8. C ABI end-to-end: YAML path (SolutionConfig shape).
// ---------------------------------------------------------------------------
TEST(c_abi_yaml_solution_lifecycle) {
    const char* yaml =
        "voice_agent:\n"
        "  llm_model_id: \"qwen3-4b\"\n"
        "  stt_model_id: \"whisper\"\n"
        "  tts_model_id: \"kokoro\"\n"
        "  vad_model_id: \"silero\"\n"
        "  sample_rate_hz: 16000\n";

    rac_solution_handle_t h = nullptr;
    rac_result_t st = rac_solution_create_from_yaml(yaml, &h);
    CHECK(st == RAC_SUCCESS);
    CHECK(h != nullptr);

    CHECK(rac_solution_start(h) == RAC_SUCCESS);
    rac_solution_cancel(h);
    rac_solution_destroy(h);
}

// ---------------------------------------------------------------------------
// 9. C ABI YAML path — raw PipelineSpec shape (top-level `operators`).
// ---------------------------------------------------------------------------
TEST(c_abi_yaml_pipeline_lifecycle) {
    const char* yaml =
        "name: \"inline\"\n"
        "operators:\n"
        "  - name: \"src\"\n"
        "    type: \"source\"\n"
        "  - name: \"snk\"\n"
        "    type: \"sink\"\n"
        "edges:\n"
        "  - from: \"src\"\n"
        "    to: \"snk\"\n";

    rac_solution_handle_t h = nullptr;
    rac_result_t st = rac_solution_create_from_yaml(yaml, &h);
    CHECK(st == RAC_SUCCESS);
    CHECK(rac_solution_start(h) == RAC_SUCCESS);
    CHECK(rac_solution_feed(h, "tick") == RAC_SUCCESS);
    CHECK(rac_solution_close_input(h) == RAC_SUCCESS);
    rac_solution_destroy(h);
}

// ---------------------------------------------------------------------------
// 10. Null / invalid handle paths.
// ---------------------------------------------------------------------------
TEST(null_handle_paths) {
    CHECK(rac_solution_start(nullptr)       == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_stop(nullptr)        == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_cancel(nullptr)      == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_feed(nullptr, "x")   == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_close_input(nullptr) == RAC_ERROR_INVALID_HANDLE);
    rac_solution_destroy(nullptr);  // no-op; must not crash

    rac_solution_handle_t h = nullptr;
    CHECK(rac_solution_create_from_yaml(nullptr, &h) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(rac_solution_create_from_proto(nullptr, 10, &h) == RAC_ERROR_INVALID_ARGUMENT);
}

}  // namespace

int main() {
    run_test_start_feed_close_lifecycle();
    run_test_double_start_is_rejected();
    run_test_cancel_mid_stream_joins();
    run_test_feed_before_start_fails();
    run_test_voice_agent_solution_compiles();
    run_test_rag_solution_compiles();
    run_test_c_abi_proto_bytes_lifecycle();
    run_test_c_abi_yaml_solution_lifecycle();
    run_test_c_abi_yaml_pipeline_lifecycle();
    run_test_null_handle_paths();

    std::fprintf(stderr, "\n%d passed / %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}

#else  // !RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stderr, "[SKIP] RAC_HAVE_PROTOBUF not defined\n");
    return 0;
}

#endif
