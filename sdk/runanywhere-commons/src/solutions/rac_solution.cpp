// SPDX-License-Identifier: Apache-2.0
//
// rac_solution.cpp — T4.7 public C ABI for SolutionRunner.

#include "rac/solutions/rac_solution.h"

#include "pipeline.pb.h"
#include "solutions.pb.h"

#include <memory>
#include <mutex>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/solutions/config_loader.hpp"
#include "rac/solutions/operator_registry.hpp"
#include "rac/solutions/solution_runner.hpp"

using rac::solutions::SolutionRunner;

namespace {

SolutionRunner* as_runner(rac_solution_handle_t h) {
    return static_cast<SolutionRunner*>(h);
}

// The engine-backed operator factories (generate_text, transcribe, synthesize,
// detect_voice, embed, retrieve) are not part of the registry's builtin
// scaffolding — they must be registered into the shared OperatorRegistry before
// any pipeline that references them is built, or PipelineExecutor::build() fails
// the operator with RAC_ERROR_FEATURE_NOT_AVAILABLE. Nothing in the C core wired
// this up (only the unit tests registered them, on a private registry), so every
// Voice Agent / RAG / STT / TTS solution failed at build time. Register once,
// here at the solution-create entry, so all SDKs get working solutions.
void ensure_engine_backed_operators_registered() {
    static std::once_flag once;
    std::call_once(once, [] {
        const std::size_t registered = rac::solutions::register_engine_backed_operators(
            rac::solutions::OperatorRegistry::instance());
        if (registered == 0) {
            RAC_LOG_WARNING("Solutions",
                            "register_engine_backed_operators registered 0 operators; "
                            "engine-backed solution steps will fail to build");
        } else {
            RAC_LOG_DEBUG("Solutions", "Registered %zu engine-backed operators", registered);
        }
    });
}

/// Heuristic: a YAML document whose top level declares `operators:` is
/// a raw PipelineSpec; otherwise it's treated as a SolutionConfig (one
/// of the oneof arms). We deliberately keep this dumb — a real parser
/// would look for the first non-blank non-comment line, but the YAML
/// subset we accept keeps things predictable.
bool yaml_looks_like_pipeline_spec(const std::string& yaml) {
    bool in_block = false;
    size_t i = 0;
    while (i < yaml.size()) {
        // Skip leading whitespace on the line.
        size_t line_start = i;
        while (i < yaml.size() && yaml[i] != '\n')
            ++i;
        std::string line = yaml.substr(line_start, i - line_start);
        if (i < yaml.size())
            ++i;

        // Strip comments.
        auto hash = line.find('#');
        if (hash != std::string::npos)
            line = line.substr(0, hash);

        // Skip blank lines and indented lines (must be top-level keys).
        size_t first = line.find_first_not_of(" \t\r");
        if (first == std::string::npos)
            continue;
        if (first > 0)
            continue;

        // Top-level key.
        auto colon = line.find(':');
        if (colon == std::string::npos)
            continue;
        std::string key = line.substr(0, colon);
        if (key == "operators" || key == "edges" || key == "options") {
            return true;
        }
        if (key == "voice_agent" || key == "rag" || key == "agent_loop" ||
            key == "time_series") {
            return false;
        }
        (void)in_block;
    }
    return false;
}

}  // namespace

extern "C" {

RAC_API rac_result_t rac_solution_create_from_proto(const void* proto_bytes, size_t len,
                                                    rac_solution_handle_t* out_handle) {
    if (!out_handle)
        return RAC_ERROR_INVALID_ARGUMENT;
    *out_handle = nullptr;
    ensure_engine_backed_operators_registered();

    runanywhere::v1::SolutionConfig config;
    rac_result_t st = rac::solutions::load_solution_from_proto_bytes(proto_bytes, len, &config);
    if (st != RAC_SUCCESS)
        return st;

    auto runner = std::make_unique<SolutionRunner>(config);
    *out_handle = runner.release();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_create_from_yaml(const char* yaml_text,
                                                   rac_solution_handle_t* out_handle) {
    if (!out_handle)
        return RAC_ERROR_INVALID_ARGUMENT;
    *out_handle = nullptr;
    if (!yaml_text)
        return RAC_ERROR_INVALID_ARGUMENT;
    ensure_engine_backed_operators_registered();

    const std::string yaml(yaml_text);
    if (yaml_looks_like_pipeline_spec(yaml)) {
        runanywhere::v1::PipelineSpec spec;
        rac_result_t st = rac::solutions::load_pipeline_from_yaml(yaml, &spec);
        if (st != RAC_SUCCESS)
            return st;
        auto runner = std::make_unique<SolutionRunner>(std::move(spec));
        *out_handle = runner.release();
        return RAC_SUCCESS;
    }

    runanywhere::v1::SolutionConfig config;
    rac_result_t st = rac::solutions::load_solution_from_yaml(yaml, &config);
    if (st != RAC_SUCCESS)
        return st;
    auto runner = std::make_unique<SolutionRunner>(config);
    *out_handle = runner.release();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_start(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner)
        return RAC_ERROR_INVALID_HANDLE;
    return runner->start();
}

RAC_API rac_result_t rac_solution_stop(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner)
        return RAC_ERROR_INVALID_HANDLE;
    runner->stop();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_cancel(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner)
        return RAC_ERROR_INVALID_HANDLE;
    runner->cancel();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_feed(rac_solution_handle_t handle, const char* item) {
    auto* runner = as_runner(handle);
    if (!runner)
        return RAC_ERROR_INVALID_HANDLE;
    if (!item)
        return RAC_ERROR_INVALID_ARGUMENT;
    return runner->feed(rac::solutions::Item::text(std::string(item)));
}

RAC_API rac_result_t rac_solution_close_input(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner)
        return RAC_ERROR_INVALID_HANDLE;
    runner->close_input();
    return RAC_SUCCESS;
}

RAC_API void rac_solution_destroy(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner)
        return;
    runner->cancel();
    runner->wait();
    delete runner;
}

}  // extern "C"
