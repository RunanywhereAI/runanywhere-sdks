// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/pipeline_executor.hpp — spec → GraphScheduler
// compiler.
//
// `PipelineSpec` describes a labelled DAG of operators (L5 layer in the
// architecture). `PipelineExecutor` is a pure translation layer that
// walks the spec, asks `OperatorRegistry` to materialize one
// `PipelineNode` per operator, resolves `EdgeSpec` endpoints against the
// registered operator port schemas, and wires up a `GraphScheduler`.
//
// The executor is deliberately narrow: it does NOT start the scheduler,
// does NOT own engines, does NOT touch models. It hands back a live
// `GraphScheduler` ready for the caller (usually `SolutionRunner`) to
// start/wait/cancel. This keeps the class responsibility sharp — spec
// validation + graph wiring — and makes it trivial to unit-test.
//
// Validation
// `build()` returns `RAC_ERROR_INVALID_CONFIGURATION` and sets
// `rac_error_set_details(...)` when:
//   * any operator name appears twice
//   * an operator or endpoint has an invalid name/port shape
//   * an edge endpoint references an unknown operator
//   * an edge endpoint names a port not declared by its operator type
//   * an active endpoint uses empty or legacy opaque payload metadata
//   * an edge appears twice
//   * an operator factory does not expose a declared active port as an
//     independent edge
//   * an edge declares an invalid capacity or EdgePolicy enum value
//   * a factory is missing for an arbitrary declared operator type
//
// Same-endpoint fan-out/fan-in is supported by inserting graph SplitNode /
// MergeNode adapters. For example, two edges from `a.out` are duplicated
// through a SplitNode, while two edges into `b.in` are combined through a
// MergeNode. This keeps split/merge behavior explicit instead of overwriting
// input/output slots. Every compiled solution edge also passes through a
// payload type guard that rejects operator-emitted `Payload.type_id` values
// that do not match the resolved port contract. Distinct named operator
// ports are wired through the OperatorAdapter interface returned by
// OperatorRegistry.
//
// Known engine-backed solution operator types from `SolutionConfig`
// expansion are narrower: when their factories are absent, `build()`
// returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` so callers can distinguish
// "this solution references a real primitive that has not been wired"
// from a misspelled or unknown operator type.
//
// Strict validation (`options.strict_validation`) additionally rejects
// pipelines with disconnected nodes.

#pragma once

#include "pipeline.pb.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

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
    std::shared_ptr<OperatorEdge> root_input_edge() const noexcept { return root_input_edge_; }

    /// Terminal output edge of the last topologically-sorted operator.
    /// Useful in tests that drain the pipeline's tail; production
    /// sinks usually close silently.
    std::shared_ptr<OperatorEdge> root_output_edge() const noexcept { return root_output_edge_; }

    const std::string& root_input_payload_type() const noexcept { return root_input_payload_type_; }

    const std::string& root_output_payload_type() const noexcept {
        return root_output_payload_type_;
    }

   private:
    runanywhere::v1::PipelineSpec spec_;
    std::shared_ptr<OperatorEdge> root_input_edge_;
    std::shared_ptr<OperatorEdge> root_output_edge_;
    std::string root_input_payload_type_;
    std::string root_output_payload_type_;
};

}  // namespace rac::solutions
