// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Per-primitive latency harness.
//
//   tools/benchmark/ra_bench [--primitive=generate_text] [--iterations=100]
//                            [--model=qwen3-4b-q4_k_m.gguf] [--engine=llamacpp]
//
// Reports: min / median / p90 / p99 / max in milliseconds. Used by the
// Phase 0 go/no-go gate to validate first-audio latency targets.

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "core/abi/ra_primitives.h"
#include "core/abi/ra_version.h"
#include "core/registry/plugin_registry.h"
#include "core/router/engine_router.h"

using namespace ra::core;
using clock_type = std::chrono::steady_clock;

namespace {

struct Options {
    std::string_view primitive  = "generate_text";
    std::string_view model      = "qwen3-4b";
    std::string_view engine;
    int              iterations = 10;
};

Options parse_args(int argc, char** argv) {
    Options o{};
    for (int i = 1; i < argc; ++i) {
        std::string_view a = argv[i];
        if (a.rfind("--primitive=", 0) == 0)   o.primitive  = a.substr(12);
        else if (a.rfind("--model=", 0) == 0)   o.model      = a.substr(8);
        else if (a.rfind("--engine=", 0) == 0)  o.engine     = a.substr(9);
        else if (a.rfind("--iterations=", 0) == 0) o.iterations = std::atoi(
            std::string(a.substr(13)).c_str());
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
    size_t idx = static_cast<size_t>(p * static_cast<double>(sorted.size() - 1));
    return sorted[idx];
}

}  // namespace

int main(int argc, char** argv) {
    std::printf("RunAnywhere v2 benchmark — ABI 0x%x\n", ra_abi_version());
    const auto opts = parse_args(argc, argv);
    if (opts.iterations <= 0) {
        std::fprintf(stderr,
                     "error: --iterations must be a positive integer, got %d\n",
                     opts.iterations);
        return 2;
    }

    auto& reg    = PluginRegistry::global();
    EngineRouter router(reg, HardwareProfile::detect());

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
    std::printf("Using engine: %s (score %d)\n",
                result.plugin->name.c_str(), result.score);

    std::vector<double> latencies;
    latencies.reserve(opts.iterations);
    for (int i = 0; i < opts.iterations; ++i) {
        const auto t0 = clock_type::now();
        // TODO: exercise the engine's primitive. For bootstrap, just sleep.
        std::this_thread::sleep_for(std::chrono::microseconds(100));
        const auto t1 = clock_type::now();
        latencies.push_back(
            std::chrono::duration<double, std::milli>(t1 - t0).count());
    }

    std::printf("Iterations: %d\n", opts.iterations);
    std::printf("min    = %.3f ms\n", *std::min_element(latencies.begin(), latencies.end()));
    std::printf("median = %.3f ms\n", percentile(latencies, 0.5));
    std::printf("p90    = %.3f ms\n", percentile(latencies, 0.9));
    std::printf("p99    = %.3f ms\n", percentile(latencies, 0.99));
    std::printf("max    = %.3f ms\n", *std::max_element(latencies.begin(), latencies.end()));
    return 0;
}
