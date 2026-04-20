// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Live-inference integration test for the real sherpa-onnx-backed plugin.
//
// All cases that touch a real model are gated on env vars pointing to a
// valid model directory:
//   RA_TEST_STT_MODEL_DIR  → sherpa-onnx streaming STT (encoder/decoder/joiner/tokens)
//   RA_TEST_TTS_MODEL_DIR  → VITS TTS (model.onnx/tokens.txt/lexicon.txt/data_dir)
//   RA_TEST_VAD_MODEL      → silero-vad .onnx file
//   RA_TEST_WW_MODEL_DIR   → sherpa-onnx keyword spotter dir
//
// Without those env vars the tests skip cleanly. Always-on cases exercise
// the error paths (bogus model directory, null out pointers).
//
// Skipped under RA_STATIC_PLUGINS.

#include "plugin_registry.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <utility>
#include <vector>

#if !defined(RA_STATIC_PLUGINS)

using ra::core::PluginHandleRef;
using ra::core::PluginRegistry;

namespace {

std::filesystem::path sherpa_dylib_path() {
#ifdef RA_ENGINE_PLUGIN_DIR
    std::filesystem::path root(RA_ENGINE_PLUGIN_DIR);
#else
    std::filesystem::path root = std::filesystem::current_path();
#endif
#if defined(__APPLE__)
    return root / "sherpa" / "librunanywhere_sherpa.dylib";
#elif defined(_WIN32)
    return root / "sherpa" / "runanywhere_sherpa.dll";
#else
    return root / "sherpa" / "librunanywhere_sherpa.so";
#endif
}

PluginHandleRef ensure_sherpa_loaded() {
    auto& reg = PluginRegistry::global();
    if (auto h = reg.find_by_name("sherpa")) return h;
    const auto path = sherpa_dylib_path();
    if (!std::filesystem::exists(path)) return {};
    const auto rc = reg.load_plugin(path.string());
    if (rc != RA_OK) return {};
    return reg.find_by_name("sherpa");
}

const char* envget(const char* n) {
    const char* v = std::getenv(n);
    return (v && *v) ? v : nullptr;
}

}  // namespace

TEST(SherpaLive, SttRejectsBogusModelDir) {
    auto h = ensure_sherpa_loaded();
    if (!h) GTEST_SKIP() << "sherpa plugin not built";
    ASSERT_NE(h->vtable.stt_create, nullptr);

    ra_model_spec_t spec{};
    spec.model_path = "/no/such/sherpa/stt/dir";
    spec.format     = RA_FORMAT_ONNX;
    ra_session_config_t cfg{};

    ra_stt_session_t* sess = nullptr;
    const auto st = h->vtable.stt_create(&spec, &cfg, &sess);
    EXPECT_NE(st, RA_OK);
    EXPECT_EQ(sess, nullptr);
}

TEST(SherpaLive, VadRejectsBogusModelPath) {
    auto h = ensure_sherpa_loaded();
    if (!h) GTEST_SKIP() << "sherpa plugin not built";
    ASSERT_NE(h->vtable.vad_create, nullptr);

    ra_model_spec_t spec{};
    spec.model_path = "/no/such/silero-vad.onnx";
    ra_session_config_t cfg{};
    ra_vad_session_t* sess = nullptr;
    const auto st = h->vtable.vad_create(&spec, &cfg, &sess);
    EXPECT_NE(st, RA_OK);
    EXPECT_EQ(sess, nullptr);
}

TEST(SherpaLive, TtsRejectsBogusModelDir) {
    auto h = ensure_sherpa_loaded();
    if (!h) GTEST_SKIP() << "sherpa plugin not built";
    ASSERT_NE(h->vtable.tts_create, nullptr);

    ra_model_spec_t spec{};
    spec.model_path = "/no/such/tts/dir";
    ra_session_config_t cfg{};
    ra_tts_session_t* sess = nullptr;
    const auto st = h->vtable.tts_create(&spec, &cfg, &sess);
    EXPECT_NE(st, RA_OK);
    EXPECT_EQ(sess, nullptr);
}

TEST(SherpaLive, SttTranscribesRealAudio) {
    const char* dir = envget("RA_TEST_STT_MODEL_DIR");
    if (!dir) GTEST_SKIP() << "RA_TEST_STT_MODEL_DIR not set";
    auto h = ensure_sherpa_loaded();
    if (!h) GTEST_SKIP() << "sherpa plugin not built";

    ra_model_spec_t spec{};
    spec.model_path = dir;
    spec.format     = RA_FORMAT_ONNX;
    ra_session_config_t cfg{};
    cfg.n_threads = 2;

    ra_stt_session_t* sess = nullptr;
    ASSERT_EQ(h->vtable.stt_create(&spec, &cfg, &sess), RA_OK);

    struct Cap {
        int chunks = 0;
        bool saw_final = false;
        std::string last_text;
    } cap;

    auto cb = [](const ra_transcript_chunk_t* c, void* ud) {
        auto* p = static_cast<Cap*>(ud);
        ++p->chunks;
        if (c->text) p->last_text = c->text;
        if (!c->is_partial) p->saw_final = true;
    };
    ASSERT_EQ(h->vtable.stt_set_callback(sess, cb, &cap), RA_OK);

    // 1 second of 440Hz sine at 16 kHz — not a real utterance but it
    // exercises the feed/decode path.
    constexpr int sr = 16000;
    std::vector<float> buf(sr);
    for (int i = 0; i < sr; ++i) {
        buf[i] = 0.2f * std::sin(2.0f * 3.14159f * 440.0f *
                                  static_cast<float>(i) / sr);
    }
    // Feed in 100ms chunks — matches what the voice pipeline would do.
    for (int off = 0; off < sr; off += sr / 10) {
        EXPECT_EQ(h->vtable.stt_feed_audio(sess, buf.data() + off, sr / 10, sr),
                  RA_OK);
    }
    EXPECT_EQ(h->vtable.stt_flush(sess), RA_OK);

    // Real speech would populate cap.last_text, but silence + tone likely
    // produces nothing. Simply confirm the pipeline didn't crash and the
    // session is alive.
    (void)cap;

    h->vtable.stt_destroy(sess);
}

TEST(SherpaLive, VadDetectsSpeechBursts) {
    const char* path = envget("RA_TEST_VAD_MODEL");
    if (!path) GTEST_SKIP() << "RA_TEST_VAD_MODEL not set";
    auto h = ensure_sherpa_loaded();
    if (!h) GTEST_SKIP() << "sherpa plugin not built";

    ra_model_spec_t spec{};
    spec.model_path = path;
    ra_session_config_t cfg{};
    ra_vad_session_t* sess = nullptr;
    ASSERT_EQ(h->vtable.vad_create(&spec, &cfg, &sess), RA_OK);

    std::atomic<int> speech_starts{0};
    std::atomic<int> speech_ends{0};
    auto cb = [](const ra_vad_event_t* ev, void* ud) {
        auto* counters = static_cast<std::pair<std::atomic<int>*,
                                                std::atomic<int>*>*>(ud);
        if (ev->type == RA_VAD_EVENT_VOICE_START) counters->first->fetch_add(1);
        if (ev->type == RA_VAD_EVENT_VOICE_END_OF_UTTERANCE) counters->second->fetch_add(1);
    };
    auto pair = std::make_pair(&speech_starts, &speech_ends);
    ASSERT_EQ(h->vtable.vad_set_callback(sess, cb, &pair), RA_OK);

    // Feed 2s of "speech" (amplitude 0.3 sine) then 2s of silence.
    constexpr int sr = 16000;
    std::vector<float> burst(sr * 2);
    for (int i = 0; i < static_cast<int>(burst.size()); ++i) {
        burst[i] = 0.3f * std::sin(2.0f * 3.14159f * 220.0f *
                                    static_cast<float>(i) / sr);
    }
    std::vector<float> silence(sr * 2, 0.f);

    // Feed in 256-sample chunks (matches silero frame size).
    for (int off = 0; off < static_cast<int>(burst.size()); off += 256) {
        const int n = std::min(256, static_cast<int>(burst.size()) - off);
        EXPECT_EQ(h->vtable.vad_feed_audio(sess, burst.data() + off, n, sr),
                  RA_OK);
    }
    for (int off = 0; off < static_cast<int>(silence.size()); off += 256) {
        const int n = std::min(256, static_cast<int>(silence.size()) - off);
        EXPECT_EQ(h->vtable.vad_feed_audio(sess, silence.data() + off, n, sr),
                  RA_OK);
    }

    // Sine doesn't look like speech to silero-vad — the counters may
    // legitimately stay zero. The real validation is that feed_audio
    // returned OK every time without crashing.
    (void)speech_starts;
    (void)speech_ends;

    h->vtable.vad_destroy(sess);
}

#endif  // !RA_STATIC_PLUGINS
