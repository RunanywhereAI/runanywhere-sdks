// SPDX-License-Identifier: Apache-2.0
//
// rac_solution.cpp — T4.7 public C ABI for SolutionRunner.

#include "rac/solutions/rac_solution.h"

#include <memory>
#include <string>

#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/solutions/config_loader.hpp"
#include "rac/solutions/solution_runner.hpp"
#include "solutions.pb.h"

using rac::solutions::SolutionRunner;

namespace {

SolutionRunner* as_runner(rac_solution_handle_t h) {
    return static_cast<SolutionRunner*>(h);
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
        while (i < yaml.size() && yaml[i] != '\n') ++i;
        std::string line = yaml.substr(line_start, i - line_start);
        if (i < yaml.size()) ++i;

        // Strip comments.
        auto hash = line.find('#');
        if (hash != std::string::npos) line = line.substr(0, hash);

        // Skip blank lines and indented lines (must be top-level keys).
        size_t first = line.find_first_not_of(" \t\r");
        if (first == std::string::npos) continue;
        if (first > 0) continue;

        // Top-level key.
        auto colon = line.find(':');
        if (colon == std::string::npos) continue;
        std::string key = line.substr(0, colon);
        if (key == "operators" || key == "edges" || key == "options") {
            return true;
        }
        if (key == "voice_agent" || key == "rag" || key == "wake_word"
            || key == "agent_loop" || key == "time_series") {
            return false;
        }
        (void)in_block;
    }
    return false;
}

}  // namespace

extern "C" {

RAC_API rac_result_t rac_solution_create_from_proto(const void*            proto_bytes,
                                                    size_t                 len,
                                                    rac_solution_handle_t* out_handle) {
    if (!out_handle) {
        RAC_LOG_ERROR("RAC_SOLUTION",
                      "rac_solution_create_from_proto: out_handle is null");
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_handle = nullptr;

    runanywhere::v1::SolutionConfig config;
    rac_result_t st = rac::solutions::load_solution_from_proto_bytes(
        proto_bytes, len, &config);
    if (st != RAC_SUCCESS) {
        RAC_LOG_ERROR("RAC_SOLUTION",
                      "rac_solution_create_from_proto: failed to decode "
                      "SolutionConfig (rc=%d, details=%s)",
                      st, rac_error_get_details() ? rac_error_get_details() : "");
        return st;
    }

    auto runner = std::make_unique<SolutionRunner>(config);
    *out_handle = runner.release();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_create_from_yaml(const char*            yaml_text,
                                                   rac_solution_handle_t* out_handle) {
    if (!out_handle) {
        RAC_LOG_ERROR("RAC_SOLUTION",
                      "rac_solution_create_from_yaml: out_handle is null");
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_handle = nullptr;
    if (!yaml_text) {
        RAC_LOG_ERROR("RAC_SOLUTION",
                      "rac_solution_create_from_yaml: yaml_text is null");
        rac_error_set_details("rac_solution_create_from_yaml: yaml_text is null");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string yaml(yaml_text);
    if (yaml_looks_like_pipeline_spec(yaml)) {
        runanywhere::v1::PipelineSpec spec;
        rac_result_t st = rac::solutions::load_pipeline_from_yaml(yaml, &spec);
        if (st != RAC_SUCCESS) {
            RAC_LOG_ERROR("RAC_SOLUTION",
                          "rac_solution_create_from_yaml: pipeline YAML parse "
                          "failed (rc=%d, details=%s)",
                          st, rac_error_get_details() ? rac_error_get_details() : "");
            return st;
        }
        auto runner = std::make_unique<SolutionRunner>(std::move(spec));
        *out_handle = runner.release();
        return RAC_SUCCESS;
    }

    runanywhere::v1::SolutionConfig config;
    rac_result_t st = rac::solutions::load_solution_from_yaml(yaml, &config);
    if (st != RAC_SUCCESS) {
        RAC_LOG_ERROR("RAC_SOLUTION",
                      "rac_solution_create_from_yaml: solution YAML parse "
                      "failed (rc=%d, details=%s)",
                      st, rac_error_get_details() ? rac_error_get_details() : "");
        return st;
    }
    auto runner = std::make_unique<SolutionRunner>(config);
    *out_handle = runner.release();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_start(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner) return RAC_ERROR_INVALID_HANDLE;
    return runner->start();
}

RAC_API rac_result_t rac_solution_stop(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner) return RAC_ERROR_INVALID_HANDLE;
    runner->stop();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_cancel(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner) return RAC_ERROR_INVALID_HANDLE;
    runner->cancel();
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_solution_feed(rac_solution_handle_t handle,
                                       const char*           item) {
    auto* runner = as_runner(handle);
    if (!runner) return RAC_ERROR_INVALID_HANDLE;
    if (!item)   return RAC_ERROR_INVALID_ARGUMENT;
    return runner->feed(std::string(item));
}

RAC_API rac_result_t rac_solution_close_input(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner) return RAC_ERROR_INVALID_HANDLE;
    runner->close_input();
    return RAC_SUCCESS;
}

RAC_API void rac_solution_destroy(rac_solution_handle_t handle) {
    auto* runner = as_runner(handle);
    if (!runner) return;
    runner->cancel();
    runner->wait();
    delete runner;
}

}  // extern "C"
