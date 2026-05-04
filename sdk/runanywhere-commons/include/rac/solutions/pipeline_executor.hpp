// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/pipeline_executor.hpp — T4.7 spec → GraphScheduler
// compiler.
//
// `PipelineSpec` describes a labelled DAG of operators (L5 layer in the
// v3.1 architecture). `PipelineExecutor` is a pure translation layer that
// walks the spec, asks `OperatorRegistry` to materialize one
// `PipelineNode` per operator, resolves `EdgeSpec` endpoints against the
// operator names, and wires up a `GraphScheduler`.
//
// The executor is deliberately narrow: it does NOT start the scheduler,
// does NOT own engines, does NOT touch models. It hands back a live
// `GraphScheduler` ready for the caller (usually `SolutionRunner`) to
// start/wait/cancel. This keeps the class responsibility sharp — spec
// validation + graph wiring — and makes it trivial to unit-test.
//
// Validation
// ----------
// `build()` returns `RAC_ERROR_INVALID_CONFIGURATION` and sets
// `rac_error_set_details(...)` when:
//   * any operator name appears twice
//   * an edge endpoint references an unknown operator
//   * a factory is missing for a declared operator type
//
// Strict validation (`options.strict_validation`) additionally rejects
// pipelines with disconnected nodes.

#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/solutions/operator_registry.hpp"

namespace rac::solutions {

class PipelineExecutor {
public:
    explicit PipelineExecutor(runanywhere::v1::PipelineSpec spec);

    /// Compile the spec into a live `GraphScheduler`. On failure the
    /// returned pointer is null and `*out_error` receives a commons
    /// error code. The scheduler is returned unstarted; the caller is
    /// expected to `start()` / `wait()` / `stop()` / `cancel_all()` as
    /// their run model dictates.
    std::unique_ptr<rac::graph::GraphScheduler> build(rac_result_t* out_error);

    /// Access the original spec (useful for diagnostics and tests).
    const runanywhere::v1::PipelineSpec& spec() const noexcept { return spec_; }

    /// After a successful build(), returns the input edge of the
    /// "source" or first topologically-rooted operator. Callers can
    /// push seed items into this edge when the spec's source operator
    /// expects its frames to be injected externally (e.g. for
    /// microphone capture, file streaming, or unit-testing harnesses).
    /// Returns nullptr if called before build() or when no input edges
    /// were captured.
    std::shared_ptr<OperatorEdge> root_input_edge() const noexcept {
        return root_input_edge_;
    }

    /// Terminal output edge of the last topologically-sorted operator.
    /// Useful in tests that drain the pipeline's tail; production
    /// sinks usually close silently.
    std::shared_ptr<OperatorEdge> root_output_edge() const noexcept {
        return root_output_edge_;
    }

private:
    runanywhere::v1::PipelineSpec                              spec_;
    std::shared_ptr<OperatorEdge>                              root_input_edge_;
    std::shared_ptr<OperatorEdge>                              root_output_edge_;
};

}  // namespace rac::solutions
