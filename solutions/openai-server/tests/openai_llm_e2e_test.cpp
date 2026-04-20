// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// End-to-end LLM tests for the OpenAI-compatible server. Gated on
//   RA_TEST_GGUF — path to a small GGUF model (e.g. TinyLlama Q4_K_M).
// When the env var is unset, tests skip.

#include <gtest/gtest.h>

#include "plugin_registry.h"
#include "ra_primitives.h"
#include "ra_server.h"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <thread>

extern "C" {
ra_status_t ra_solution_openai_server_register_session(const char*, ra_llm_session_t*);
void        ra_solution_openai_server_set_default_model(const char*);
void        ra_solution_openai_server_clear_sessions(void);
}

using json = nlohmann::json;

namespace {

std::filesystem::path llamacpp_dylib() {
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

}  // namespace

class OpenAiServerLlmE2E : public ::testing::Test {
protected:
    int port = 0;
    ra_llm_session_t* session = nullptr;

    void SetUp() override {
        const char* model_path = std::getenv("RA_TEST_GGUF");
        if (!model_path) GTEST_SKIP() << "RA_TEST_GGUF not set";
        if (!std::filesystem::exists(model_path)) {
            GTEST_SKIP() << "RA_TEST_GGUF file not found: " << model_path;
        }

#if !defined(RA_STATIC_PLUGINS)
        auto& reg = ra::core::PluginRegistry::global();
        const auto dylib = llamacpp_dylib();
        if (!std::filesystem::exists(dylib)) {
            GTEST_SKIP() << "llamacpp plugin not built: " << dylib.string();
        }
        ASSERT_EQ(reg.load_plugin(dylib.string()), 0);
#endif

        ra_model_spec_t spec{};
        spec.model_id          = "tiny-gguf";
        spec.model_path        = model_path;
        spec.format            = RA_FORMAT_GGUF;
        spec.preferred_runtime = RA_RUNTIME_SELF_CONTAINED;

        ra_session_config_t cfg{};
        cfg.context_size  = 512;
        cfg.n_gpu_layers  = 0;
        cfg.use_mmap      = 1;

        ASSERT_EQ(ra_llm_create(&spec, &cfg, &session), RA_OK);
        ra_solution_openai_server_register_session("tiny-gguf", session);
        ra_solution_openai_server_set_default_model("tiny-gguf");

        ra_server_config_t scfg{};
        scfg.host = "127.0.0.1";
        scfg.port = 0;
        ASSERT_EQ(ra_server_start(&scfg), RA_OK);
        ra_server_status_t st{};
        ra_server_get_status(&st);
        port = st.port;
    }

    void TearDown() override {
        ra_server_stop();
        ra_solution_openai_server_clear_sessions();
        if (session) ra_llm_destroy(session);
    }
};

TEST_F(OpenAiServerLlmE2E, NonStreamingReturnsRealTokens) {
    httplib::Client c("127.0.0.1", port);
    c.set_read_timeout(60, 0);
    json req = {
        {"model", "tiny-gguf"},
        {"messages", json::array({
            json{{"role", "user"}, {"content", "Reply with a single word."}}
        })},
        {"max_tokens", 16}
    };
    auto r = c.Post("/v1/chat/completions", req.dump(), "application/json");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 200);
    const auto body = json::parse(r->body);
    EXPECT_EQ(body.value("object", ""), "chat.completion");
    ASSERT_TRUE(body["choices"].is_array());
    ASSERT_GE(body["choices"].size(), 1u);
    const auto content = body["choices"][0]["message"].value("content", "");
    EXPECT_GT(content.size(), 0u) << "empty assistant content";
    EXPECT_GE(body["usage"].value("completion_tokens", 0), 1);
}

TEST_F(OpenAiServerLlmE2E, StreamingEmitsSseChunksAndDone) {
    httplib::Client c("127.0.0.1", port);
    c.set_read_timeout(60, 0);
    json req = {
        {"model", "tiny-gguf"},
        {"messages", json::array({
            json{{"role", "user"}, {"content", "Say hi."}}
        })},
        {"max_tokens", 8},
        {"stream", true}
    };
    auto r = c.Post("/v1/chat/completions", req.dump(), "application/json");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 200);
    const std::string& sse = r->body;
    EXPECT_NE(sse.find("data: {"), std::string::npos) << "no SSE data chunks";
    EXPECT_NE(sse.find("[DONE]"), std::string::npos) << "no SSE [DONE] marker";
    EXPECT_NE(sse.find("\"delta\""), std::string::npos) << "no delta field";
}

TEST_F(OpenAiServerLlmE2E, ModelsListIncludesRegisteredId) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Get("/v1/models");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 200);
    auto body = json::parse(r->body);
    bool found = false;
    for (const auto& m : body["data"]) {
        if (m.value("id", "") == "tiny-gguf") { found = true; break; }
    }
    EXPECT_TRUE(found) << r->body;
}

TEST_F(OpenAiServerLlmE2E, HealthReportsModelLoaded) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Get("/health");
    ASSERT_TRUE(r);
    auto body = json::parse(r->body);
    EXPECT_TRUE(body.value("model_loaded", false));
    EXPECT_EQ(body.value("model_id", ""), "tiny-gguf");
}
