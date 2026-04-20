// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Per-primitive latency harness.
//
//   tools/benchmark/ra_bench [--primitive=generate_text] [--iterations=100]
//                            [--model=/path/to/model.gguf] [--engine=llamacpp]
//                            [--prompt="hello"] [--max-new-tokens=64]
//                            [--plugin-dir=build/…/engines]
//                            [--json-out=bench.json]
//
// Each iteration drives the real engine primitive and records a
// `ra_benchmark_timing_t` pair. Reports min / p50 / p90 / p99 / max
// latency plus tokens-per-second for LLM primitives.

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

#include "ra_benchmark.h"
#include "ra_primitives.h"
#include "ra_version.h"
#include "plugin_registry.h"
#include "engine_router.h"

using namespace ra::core;

namespace {

struct Options {
    std::string_view primitive       = "generate_text";
    std::string_view model;
    std::string_view engine;
    std::string_view json_out;
    std::string_view metric_name;
    std::string_view plugin_dir;
    std::string_view prompt          = "The quick brown fox";
    int              iterations      = 10;
    int              max_new_tokens  = 32;
    int              sample_rate_hz  = 16000;
    int              audio_duration_ms = 100;
};

Options parse_args(int argc, char** argv) {
    Options o{};
    for (int i = 1; i < argc; ++i) {
        std::string_view a = argv[i];
        auto suffix = [&](std::string_view pfx, std::string_view& dst) {
            if (a.rfind(pfx, 0) == 0) { dst = a.substr(pfx.size()); return true; }
            return false;
        };
        auto suffix_int = [&](std::string_view pfx, int& dst) {
            if (a.rfind(pfx, 0) == 0) {
                dst = std::atoi(std::string(a.substr(pfx.size())).c_str());
                return true;
            }
            return false;
        };
        if (suffix("--primitive=", o.primitive))     continue;
        if (suffix("--model=", o.model))             continue;
        if (suffix("--engine=", o.engine))           continue;
        if (suffix("--json-out=", o.json_out))       continue;
        if (suffix("--metric=", o.metric_name))      continue;
        if (suffix("--plugin-dir=", o.plugin_dir))   continue;
        if (suffix("--prompt=", o.prompt))           continue;
        if (suffix_int("--iterations=", o.iterations))           continue;
        if (suffix_int("--max-new-tokens=", o.max_new_tokens))   continue;
        if (suffix_int("--sample-rate=", o.sample_rate_hz))      continue;
        if (suffix_int("--audio-ms=", o.audio_duration_ms))      continue;
    }
    return o;
}

ra_primitive_t parse_primitive(std::string_view s) {
    if (s == "generate_text") return RA_PRIMITIVE_GENERATE_TEXT;
    if (s == "transcribe")    return RA_PRIMITIVE_TRANSCRIBE;
    if (s == "synthesize")    return RA_PRIMITIVE_SYNTHESIZE;
    if (s == "detect_voice")  return RA_PRIMITIVE_DETECT_VOICE;
    if (s == "embed")         return RA_PRIMITIVE_EMBED;
    if (s == "wake_word")     return RA_PRIMITIVE_WAKE_WORD;
    return RA_PRIMITIVE_UNKNOWN;
}

double percentile(std::vector<double>& xs, double p) {
    if (xs.empty()) return 0.0;
    auto sorted = xs;
    std::sort(sorted.begin(), sorted.end());
    const size_t idx = static_cast<size_t>(p * static_cast<double>(sorted.size() - 1));
    return sorted[idx];
}

ra_model_spec_t make_spec() {
    ra_model_spec_t spec{};
    spec.model_id          = "bench";
    spec.model_path        = "";
    spec.format            = RA_FORMAT_GGUF;
    spec.preferred_runtime = RA_RUNTIME_SELF_CONTAINED;
    return spec;
}

struct LlmCollector {
    int32_t tokens = 0;
    bool    done   = false;
};

void llm_on_token(const ra_token_output_t* t, void* ud) {
    auto* c = static_cast<LlmCollector*>(ud);
    if (!t) return;
    if (t->is_final) c->done = true;
    else             ++c->tokens;
}

struct Sample {
    double latency_ms;
    double tokens_per_sec;
};

bool run_generate_text(const Options& opts, const std::string& model_path,
                        std::vector<Sample>& out) {
    ra_model_spec_t spec = make_spec();
    // Need to keep the local string alive because spec holds a pointer.
    spec.model_path = model_path.c_str();

    ra_session_config_t cfg{};
    cfg.context_size = 2048;
    cfg.n_gpu_layers = -1;
    cfg.use_mmap = 1;

    ra_llm_session_t* session = nullptr;
    ra_status_t rc = ra_llm_create(&spec, &cfg, &session);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_llm_create: status=%d\n", rc);
        return false;
    }

    const std::string prompt_str = std::string(opts.prompt);
    ra_prompt_t p{prompt_str.c_str(), -1};

    for (int i = 0; i < opts.iterations; ++i) {
        LlmCollector col{};
        ra_benchmark_timing_t t{};
        ra_benchmark_timing_init(&t, "generate_text");
        rc = ra_llm_generate(session, &p, &llm_on_token, nullptr, &col);
        ra_benchmark_timing_finish(&t);
        if (rc != RA_OK) {
            std::fprintf(stderr, "ra_llm_generate failed at iter %d: %d\n", i, rc);
            ra_benchmark_string_free(t.label);
            ra_llm_destroy(session);
            return false;
        }
        const double ms = static_cast<double>(t.end_ms - t.start_ms);
        const double tps = (ms > 0) ? (col.tokens * 1000.0 / ms) : 0.0;
        out.push_back({ms, tps});
        ra_benchmark_string_free(t.label);
        ra_llm_reset(session);
    }
    ra_llm_destroy(session);
    return true;
}

bool run_transcribe(const Options& opts, const std::string& model_path,
                    std::vector<Sample>& out) {
    ra_model_spec_t spec = make_spec();
    spec.model_path = model_path.c_str();
    spec.format = RA_FORMAT_ONNX;

    ra_session_config_t cfg{};
    ra_stt_session_t* session = nullptr;
    ra_status_t rc = ra_stt_create(&spec, &cfg, &session);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_stt_create: status=%d\n", rc);
        return false;
    }
    const int sr = opts.sample_rate_hz;
    const int samples = sr * opts.audio_duration_ms / 1000;
    std::vector<float> pcm(samples, 0.0f);

    for (int i = 0; i < opts.iterations; ++i) {
        ra_benchmark_timing_t t{};
        ra_benchmark_timing_init(&t, "transcribe");
        rc = ra_stt_feed_audio(session, pcm.data(), samples, sr);
        if (rc == RA_OK) rc = ra_stt_flush(session);
        ra_benchmark_timing_finish(&t);
        out.push_back({static_cast<double>(t.end_ms - t.start_ms), 0.0});
        ra_benchmark_string_free(t.label);
    }
    ra_stt_destroy(session);
    return true;
}

bool run_synthesize(const Options& opts, const std::string& model_path,
                    std::vector<Sample>& out) {
    ra_model_spec_t spec = make_spec();
    spec.model_path = model_path.c_str();

    ra_session_config_t cfg{};
    ra_tts_session_t* session = nullptr;
    ra_status_t rc = ra_tts_create(&spec, &cfg, &session);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_tts_create: status=%d\n", rc);
        return false;
    }
    const std::string text = std::string(opts.prompt);
    std::vector<float> pcm(48000 * 4);  // 4 s @ 48 kHz
    int32_t sr = 0;
    for (int i = 0; i < opts.iterations; ++i) {
        int32_t written = 0;
        ra_benchmark_timing_t t{};
        ra_benchmark_timing_init(&t, "synthesize");
        rc = ra_tts_synthesize(session, text.c_str(), pcm.data(),
                                static_cast<int32_t>(pcm.size()),
                                &written, &sr);
        ra_benchmark_timing_finish(&t);
        if (rc != RA_OK) {
            std::fprintf(stderr, "ra_tts_synthesize status=%d iter=%d\n", rc, i);
        }
        out.push_back({static_cast<double>(t.end_ms - t.start_ms), 0.0});
        ra_benchmark_string_free(t.label);
    }
    ra_tts_destroy(session);
    return true;
}

bool run_detect_voice(const Options& opts, const std::string& model_path,
                     std::vector<Sample>& out) {
    ra_model_spec_t spec = make_spec();
    spec.model_path = model_path.c_str();

    ra_session_config_t cfg{};
    ra_vad_session_t* session = nullptr;
    ra_status_t rc = ra_vad_create(&spec, &cfg, &session);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_vad_create: status=%d\n", rc);
        return false;
    }
    const int sr = opts.sample_rate_hz;
    const int samples = sr * opts.audio_duration_ms / 1000;
    std::vector<float> pcm(samples, 0.1f);
    for (int i = 0; i < opts.iterations; ++i) {
        ra_benchmark_timing_t t{};
        ra_benchmark_timing_init(&t, "detect_voice");
        rc = ra_vad_feed_audio(session, pcm.data(), samples, sr);
        ra_benchmark_timing_finish(&t);
        out.push_back({static_cast<double>(t.end_ms - t.start_ms), 0.0});
        ra_benchmark_string_free(t.label);
    }
    ra_vad_destroy(session);
    return true;
}

bool run_embed(const Options& opts, const std::string& model_path,
               std::vector<Sample>& out) {
    ra_model_spec_t spec = make_spec();
    spec.model_path = model_path.c_str();

    ra_session_config_t cfg{};
    ra_embed_session_t* session = nullptr;
    ra_status_t rc = ra_embed_create(&spec, &cfg, &session);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_embed_create: status=%d\n", rc);
        return false;
    }
    const int32_t dims = ra_embed_dims(session);
    std::vector<float> vec(dims > 0 ? dims : 384);
    const std::string text = std::string(opts.prompt);
    for (int i = 0; i < opts.iterations; ++i) {
        ra_benchmark_timing_t t{};
        ra_benchmark_timing_init(&t, "embed");
        rc = ra_embed_text(session, text.c_str(), vec.data(),
                            static_cast<int32_t>(vec.size()));
        ra_benchmark_timing_finish(&t);
        out.push_back({static_cast<double>(t.end_ms - t.start_ms), 0.0});
        ra_benchmark_string_free(t.label);
    }
    ra_embed_destroy(session);
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    std::printf("RunAnywhere v2 benchmark — ABI 0x%x\n", ra_abi_version());
    const auto opts = parse_args(argc, argv);
    if (opts.iterations <= 0) {
        std::fprintf(stderr, "error: --iterations must be positive (got %d)\n",
                     opts.iterations);
        return 2;
    }

    auto& reg = PluginRegistry::global();
    EngineRouter router(reg, HardwareProfile::detect());

    if (!opts.plugin_dir.empty()) {
        namespace fs = std::filesystem;
        const fs::path root(opts.plugin_dir);
        if (fs::is_directory(root)) {
            for (const auto& e : fs::recursive_directory_iterator(root)) {
                if (!e.is_regular_file()) continue;
                const auto ext = e.path().extension().string();
                if (ext == ".dylib" || ext == ".so") {
                    reg.load_plugin(e.path().string());
                }
            }
        }
    }

    const auto prim = parse_primitive(opts.primitive);
    if (prim == RA_PRIMITIVE_UNKNOWN) {
        std::fprintf(stderr, "unknown primitive: %.*s\n",
                     static_cast<int>(opts.primitive.size()),
                     opts.primitive.data());
        return 2;
    }

    RouteRequest req{prim, RA_FORMAT_GGUF, 0, opts.engine};
    auto result = router.route(req);
    if (!result.plugin) {
        std::fprintf(stderr, "no engine available: %s\n",
                     result.rejection_reason.c_str());
        return 3;
    }
    std::printf("Engine: %s (score=%d)\n",
                result.plugin->name.c_str(), result.score);

    const std::string model_path(opts.model);
    if (model_path.empty()) {
        std::fprintf(stderr,
                     "warning: --model is empty — engines that require a "
                     "model will fail to create a session.\n");
    }

    std::vector<Sample> samples;
    samples.reserve(opts.iterations);
    bool ok = false;
    switch (prim) {
    case RA_PRIMITIVE_GENERATE_TEXT: ok = run_generate_text(opts, model_path, samples); break;
    case RA_PRIMITIVE_TRANSCRIBE:    ok = run_transcribe(opts, model_path, samples); break;
    case RA_PRIMITIVE_SYNTHESIZE:    ok = run_synthesize(opts, model_path, samples); break;
    case RA_PRIMITIVE_DETECT_VOICE:  ok = run_detect_voice(opts, model_path, samples); break;
    case RA_PRIMITIVE_EMBED:         ok = run_embed(opts, model_path, samples); break;
    default:
        std::fprintf(stderr, "primitive %.*s not implemented in bench yet\n",
                     static_cast<int>(opts.primitive.size()),
                     opts.primitive.data());
        return 4;
    }
    if (!ok || samples.empty()) return 5;

    std::vector<double> lat;
    lat.reserve(samples.size());
    for (const auto& s : samples) lat.push_back(s.latency_ms);

    const double minv = *std::min_element(lat.begin(), lat.end());
    const double p50  = percentile(lat, 0.5);
    const double p90  = percentile(lat, 0.9);
    const double p99  = percentile(lat, 0.99);
    const double maxv = *std::max_element(lat.begin(), lat.end());

    double tps_p50 = 0.0;
    if (prim == RA_PRIMITIVE_GENERATE_TEXT) {
        std::vector<double> tps;
        for (const auto& s : samples) tps.push_back(s.tokens_per_sec);
        tps_p50 = percentile(tps, 0.5);
    }

    std::printf("Iterations: %d\n", opts.iterations);
    std::printf("min    = %.3f ms\n", minv);
    std::printf("p50    = %.3f ms\n", p50);
    std::printf("p90    = %.3f ms\n", p90);
    std::printf("p99    = %.3f ms\n", p99);
    std::printf("max    = %.3f ms\n", maxv);
    if (prim == RA_PRIMITIVE_GENERATE_TEXT) {
        std::printf("tok/s  = %.1f (p50)\n", tps_p50);
    }

    if (!opts.json_out.empty()) {
        std::string path(opts.json_out);
        FILE* f = std::fopen(path.c_str(), "w");
        if (!f) {
            std::fprintf(stderr, "warning: could not open %s for JSON output\n",
                         path.c_str());
        } else {
            const std::string metric = opts.metric_name.empty()
                ? std::string(opts.primitive) + "_ms"
                : std::string(opts.metric_name);
            std::fprintf(f,
                "{\n"
                "  \"metric\":      \"%s\",\n"
                "  \"iterations\":  %d,\n"
                "  \"min_ms\":      %.6f,\n"
                "  \"p50_ms\":      %.6f,\n"
                "  \"p90_ms\":      %.6f,\n"
                "  \"p99_ms\":      %.6f,\n"
                "  \"max_ms\":      %.6f,\n"
                "  \"tokens_per_sec_p50\": %.3f,\n"
                "  \"engine\":      \"%s\"\n"
                "}\n",
                metric.c_str(), opts.iterations, minv,
                p50, p90, p99, maxv, tps_p50,
                result.plugin->name.c_str());
            std::fclose(f);
            std::printf("Wrote %s\n", path.c_str());
        }
    }
    return 0;
}
