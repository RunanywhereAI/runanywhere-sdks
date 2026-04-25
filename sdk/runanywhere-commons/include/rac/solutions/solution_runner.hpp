// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/solution_runner.hpp — T4.7 high-level lifecycle owner.
//
// A thin wrapper that pairs `SolutionConfig` (or a pre-expanded
// `PipelineSpec`) with a `GraphScheduler` and exposes the start / stop
// / cancel semantics required by the public C ABI (`rac_solution_*`).
// The runner is a single-DAG construct today; if a future solution
// requires multiple cooperating graphs (e.g. a supervisor loop that
// spawns ephemeral sub-pipelines) this class is the natural seam.
//
// Threading
// ---------
// `start()` is non-blocking — it spawns the scheduler workers and
// returns. `stop()` closes every input edge and cancels the scheduler
// (still non-blocking); `cancel()` is an alias that additionally
// prioritises immediate shutdown. `wait()` joins the worker threads.
// Destruction always cancels + joins, making the runner safe against
// accidental early drop.
//
// SOLID
// -----
//   * Single responsibility: lifecycle (start/stop/cancel/wait); no
//     protocol, no I/O, no engine wiring — those live in the executor
//     and the operator registry respectively.
//   * Open/closed: additional solution arms flow through
//     `solution_converter.hpp` without changing this class.

#pragma once

#include <memory>
#include <mutex>

#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/solutions/operator_registry.hpp"
#include "solutions.pb.h"

namespace rac::solutions {

class PipelineExecutor;

class SolutionRunner {
public:
    /// Build a runner from a SolutionConfig. The config is expanded to
    /// a PipelineSpec up front so invalid oneofs surface at
    /// construction time. Expansion failures set an error on the
    /// runner that `start()` returns to the caller.
    explicit SolutionRunner(const runanywhere::v1::SolutionConfig& config);

    /// Build a runner from a pre-expanded PipelineSpec. Useful for
    /// callers that already have a validated PipelineSpec in hand (e.g.
    /// tests or tools that hand-craft the DAG).
    explicit SolutionRunner(runanywhere::v1::PipelineSpec spec);

    ~SolutionRunner();

    SolutionRunner(const SolutionRunner&)            = delete;
    SolutionRunner& operator=(const SolutionRunner&) = delete;

    /// Compile + launch the pipeline. Idempotent — subsequent calls
    /// while running return RAC_ERROR_ALREADY_INITIALIZED.
    rac_result_t start();

    /// Request a graceful shutdown (close input edges; scheduler
    /// drains naturally). Non-blocking.
    void stop();

    /// Force cancellation across the whole graph. Non-blocking; the
    /// caller should follow with `wait()` to observe termination.
    void cancel();

    /// Block until every worker thread has exited. Safe to call after
    /// stop/cancel or immediately if the scheduler has already
    /// drained.
    void wait();

    /// Current state predicate. Best-effort; racy against
    /// stop/cancel/wait, so callers must not use it for correctness.
    bool running() const noexcept;

    /// Push a single item into the root of the graph. Intended for
    /// tests and for pipelines whose "source" operator expects to be
    /// fed externally. Returns RAC_ERROR_COMPONENT_NOT_READY if the
    /// scheduler has not been started.
    rac_result_t feed(Item item);

    /// Close the root input edge — signals end-of-stream to the
    /// pipeline so downstream workers observe EOF and the scheduler
    /// drains. Idempotent.
    void close_input();

    /// Access the expanded spec (after construction).
    const runanywhere::v1::PipelineSpec& spec() const noexcept { return spec_; }

private:
    runanywhere::v1::PipelineSpec                 spec_;
    rac_result_t                                  init_status_{RAC_SUCCESS};

    mutable std::mutex                            mu_;
    std::unique_ptr<PipelineExecutor>             executor_;
    std::unique_ptr<rac::graph::GraphScheduler>   scheduler_;
    std::shared_ptr<OperatorEdge>                 root_input_;
    std::shared_ptr<OperatorEdge>                 root_output_;
    bool                                          started_{false};
    bool                                          joined_{false};
};

}  // namespace rac::solutions
