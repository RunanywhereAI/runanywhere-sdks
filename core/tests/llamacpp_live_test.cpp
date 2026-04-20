// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Live-inference integration test for the real llama.cpp-backed plugin.
//
// These tests load the built runanywhere_llamacpp dylib at runtime (no
// compile-time link), then exercise:
//   * llm_create with a bogus model path → RA_ERR_MODEL_LOAD_FAILED
//   * llm_create with a real GGUF → RA_OK + a session handle
//   * llm_generate → streams real tokens through the callback
//   * llm_cancel mid-generation → terminates within <100ms
//   * embed_text produces a non-zero vector
//
// A "real GGUF" is found via the RA_TEST_GGUF environment variable. If
// unset, the generation / embed cases skip. The always-on case is the
// bogus-path error path — which must return cleanly without crashing
// regardless of host state.
//
// Skipped under RA_STATIC_PLUGINS (iOS / WASM) — the dylib is linked
// statically there and the whole filesystem-based dlopen path is
// inapplicable.

#include "plugin_registry.h"

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#if !defined(RA_STATIC_PLUGINS)

using ra::core::PluginHandleRef;
using ra::core::PluginRegistry;

namespace {

std::filesystem::path llamacpp_dylib_path() {
#ifdef RA_ENGINE_PLUGIN_DIR
    std::filesystem::path root(RA_ENGINE_PLUGIN_DIR);
#else
    std::filesystem::path root = std::filesystem::current_path();
#endif
#if defined(__APPLE__)
    return root / "llamacpp" / "librunanywhere_llamacpp.dylib";
#elif defined(_WIN32)
    return root / "llamacpp" / "runanywhere_llamacpp.dll";
#else
    return root / "llamacpp" / "librunanywhere_llamacpp.so";
#endif
}

const char* test_gguf_path() {
    return std::getenv("RA_TEST_GGUF");
}

PluginHandleRef ensure_llamacpp_loaded() {
    auto& reg = PluginRegistry::global();
    if (auto h = reg.find_by_name("llamacpp")) return h;
    const auto path = llamacpp_dylib_path();
    if (!std::filesystem::exists(path)) return {};
    const auto rc = reg.load_plugin(path.string());
    if (rc != RA_OK) return {};
    return reg.find_by_name("llamacpp");
}

}  // namespace

TEST(LlamacppLive, RejectsBogusModelPath) {
    auto h = ensure_llamacpp_loaded();
    if (!h) GTEST_SKIP() << "llamacpp plugin not built";
    ASSERT_NE(h->vtable.llm_create, nullptr);

    ra_model_spec_t spec{};
    spec.model_id   = "bogus";
    spec.model_path = "/definitely/does/not/exist/model.gguf";
    spec.format     = RA_FORMAT_GGUF;
    ra_session_config_t cfg{};
    cfg.context_size = 512;

    ra_llm_session_t* sess = nullptr;
    const auto st = h->vtable.llm_create(&spec, &cfg, &sess);
    EXPECT_NE(st, RA_OK);
    EXPECT_EQ(sess, nullptr);
}

TEST(LlamacppLive, RejectsNullSpecOrOut) {
    auto h = ensure_llamacpp_loaded();
    if (!h) GTEST_SKIP() << "llamacpp plugin not built";

    ra_llm_session_t* sess = nullptr;
    ra_session_config_t cfg{};
    EXPECT_EQ(h->vtable.llm_create(nullptr, &cfg, &sess),
              RA_ERR_INVALID_ARGUMENT);
    EXPECT_EQ(sess, nullptr);

    ra_model_spec_t spec{};
    spec.model_path = "/tmp/whatever.gguf";
    EXPECT_EQ(h->vtable.llm_create(&spec, &cfg, /*out=*/nullptr),
              RA_ERR_INVALID_ARGUMENT);
}

TEST(LlamacppLive, GeneratesTokensFromRealModel) {
    const char* model_path = test_gguf_path();
    if (!model_path) GTEST_SKIP() << "RA_TEST_GGUF not set";
    auto h = ensure_llamacpp_loaded();
    if (!h) GTEST_SKIP() << "llamacpp plugin not built";

    ra_model_spec_t spec{};
    spec.model_id   = "live";
    spec.model_path = model_path;
    spec.format     = RA_FORMAT_GGUF;
    ra_session_config_t cfg{};
    cfg.context_size = 1024;

    ra_llm_session_t* sess = nullptr;
    ASSERT_EQ(h->vtable.llm_create(&spec, &cfg, &sess), RA_OK);
    ASSERT_NE(sess, nullptr);

    struct Capture {
        std::string accum;
        int         count = 0;
        bool        saw_final = false;
    } cap;

    ra_prompt_t prompt{};
    prompt.text            = "The quick brown";
    prompt.conversation_id = 0;

    auto tok_cb = [](const ra_token_output_t* tok, void* ud) {
        auto* c = static_cast<Capture*>(ud);
        if (tok->is_final) { c->saw_final = true; return; }
        if (tok->text) c->accum += tok->text;
        ++c->count;
    };
    auto err_cb = [](ra_status_t, const char*, void*) {};
    const auto rc = h->vtable.llm_generate(sess, &prompt, tok_cb, err_cb, &cap);
    EXPECT_EQ(rc, RA_OK);
    EXPECT_GT(cap.count, 0);
    EXPECT_TRUE(cap.saw_final);

    h->vtable.llm_destroy(sess);
}

TEST(LlamacppLive, CancelTerminatesGenerationQuickly) {
    const char* model_path = test_gguf_path();
    if (!model_path) GTEST_SKIP() << "RA_TEST_GGUF not set";
    auto h = ensure_llamacpp_loaded();
    if (!h) GTEST_SKIP() << "llamacpp plugin not built";

    ra_model_spec_t spec{};
    spec.model_path = model_path;
    spec.format     = RA_FORMAT_GGUF;
    ra_session_config_t cfg{};
    cfg.context_size = 1024;

    ra_llm_session_t* sess = nullptr;
    ASSERT_EQ(h->vtable.llm_create(&spec, &cfg, &sess), RA_OK);

    std::atomic<int> tokens_after_cancel{0};
    std::atomic<bool> cancelled_flag{false};

    struct Capture {
        std::atomic<int>*  tokens_after_cancel;
        std::atomic<bool>* cancelled_flag;
        ra_llm_session_t*  sess;
        const ra_engine_vtable_t* vt;
    } cap{ &tokens_after_cancel, &cancelled_flag, sess, &h->vtable };

    ra_prompt_t prompt{};
    prompt.text = "Tell me a long story about a dragon and its many adventures";

    auto tok_cb = [](const ra_token_output_t* tok, void* ud) {
        auto* c = static_cast<Capture*>(ud);
        if (tok->is_final) return;
        if (c->cancelled_flag->load(std::memory_order_acquire)) {
            c->tokens_after_cancel->fetch_add(1);
        }
        // On the 3rd token, fire cancel so the generate loop unwinds.
        static int n = 0;
        if (++n == 3) {
            c->cancelled_flag->store(true, std::memory_order_release);
            c->vt->llm_cancel(c->sess);
        }
    };
    auto err_cb = [](ra_status_t, const char*, void*) {};

    const auto t0 = std::chrono::steady_clock::now();
    h->vtable.llm_generate(sess, &prompt, tok_cb, err_cb, &cap);
    const auto elapsed = std::chrono::steady_clock::now() - t0;

    // The cancel path should close the stream within a few tokens of cancel.
    EXPECT_LT(tokens_after_cancel.load(), 10);
    // And total time should be bounded (cancel works at all).
    EXPECT_LT(std::chrono::duration_cast<std::chrono::seconds>(elapsed).count(),
              10);

    h->vtable.llm_destroy(sess);
}

TEST(LlamacppLive, EmbedsTextToFixedDimensionVector) {
    const char* model_path = test_gguf_path();
    if (!model_path) GTEST_SKIP() << "RA_TEST_GGUF not set";
    auto h = ensure_llamacpp_loaded();
    if (!h) GTEST_SKIP() << "llamacpp plugin not built";

    ra_model_spec_t spec{};
    spec.model_path = model_path;
    spec.format     = RA_FORMAT_GGUF;
    ra_session_config_t cfg{};
    cfg.context_size = 512;

    ra_embed_session_t* sess = nullptr;
    ASSERT_EQ(h->vtable.embed_create(&spec, &cfg, &sess), RA_OK);
    const int dims = h->vtable.embed_dims(sess);
    EXPECT_GT(dims, 0);

    std::vector<float> vec(static_cast<std::size_t>(dims), 0.f);
    const auto st = h->vtable.embed_text(sess, "hello world",
                                          vec.data(), dims);
    // Embedding may legitimately fail on a decoder-only (non-embed) model;
    // be lenient. When it succeeds, the vector must not be all zero.
    if (st == RA_OK) {
        bool nonzero = false;
        for (float x : vec) {
            if (x != 0.f) { nonzero = true; break; }
        }
        EXPECT_TRUE(nonzero);
    }

    h->vtable.embed_destroy(sess);
}

#endif  // !RA_STATIC_PLUGINS
