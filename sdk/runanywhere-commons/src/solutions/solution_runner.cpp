// SPDX-License-Identifier: Apache-2.0
//
// solution_runner.cpp — T4.7 lifecycle owner for compiled PipelineSpecs.

#include "rac/solutions/solution_runner.hpp"

#include <memory>
#include <mutex>
#include <utility>

#include "rac/core/rac_error.h"
#include "rac/solutions/pipeline_executor.hpp"
#include "rac/solutions/solution_converter.hpp"

namespace rac::solutions {

SolutionRunner::SolutionRunner(const runanywhere::v1::SolutionConfig& config) {
    init_status_ = convert_solution_to_pipeline(config, &spec_);
}

SolutionRunner::SolutionRunner(runanywhere::v1::PipelineSpec spec)
    : spec_(std::move(spec)) {}

SolutionRunner::~SolutionRunner() {
    cancel();
    wait();
}

rac_result_t SolutionRunner::start() {
    std::lock_guard<std::mutex> lock(mu_);
    if (init_status_ != RAC_SUCCESS) return init_status_;
    if (started_)                    return RAC_ERROR_ALREADY_INITIALIZED;

    executor_ = std::make_unique<PipelineExecutor>(spec_);
    rac_result_t build_status = RAC_SUCCESS;
    scheduler_ = executor_->build(&build_status);
    if (!scheduler_) {
        executor_.reset();
        return build_status == RAC_SUCCESS ? RAC_ERROR_INVALID_CONFIGURATION
                                           : build_status;
    }
    root_input_  = executor_->root_input_edge();
    root_output_ = executor_->root_output_edge();

    scheduler_->start();
    started_ = true;
    joined_  = false;
    return RAC_SUCCESS;
}

void SolutionRunner::stop() {
    std::shared_ptr<OperatorEdge> input;
    rac::graph::GraphScheduler*   sched = nullptr;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_) return;
        input = root_input_;
        sched = scheduler_.get();
    }
    if (input) input->close();
    if (sched) sched->stop();
}

void SolutionRunner::cancel() {
    rac::graph::GraphScheduler* sched = nullptr;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_) return;
        sched = scheduler_.get();
    }
    if (sched) sched->cancel_all();
}

void SolutionRunner::wait() {
    std::unique_ptr<rac::graph::GraphScheduler> sched;
    std::unique_ptr<PipelineExecutor>           exec;
    std::shared_ptr<OperatorEdge>               in_edge;
    std::shared_ptr<OperatorEdge>               out_edge;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_ || joined_) return;
        sched    = std::move(scheduler_);
        exec     = std::move(executor_);
        in_edge  = std::move(root_input_);
        out_edge = std::move(root_output_);
        joined_  = true;
        started_ = false;
    }
    if (in_edge) in_edge->close();
    if (sched)   sched->wait();
    // Drain any residual items sitting in the tail output edge so the
    // graph releases memory promptly. Non-blocking because the
    // scheduler has already joined.
    if (out_edge) {
        while (true) {
            auto v = out_edge->try_pop();
            if (!v) break;
        }
    }
    sched.reset();
    exec.reset();
}

bool SolutionRunner::running() const noexcept {
    std::lock_guard<std::mutex> lock(mu_);
    return started_ && scheduler_ && scheduler_->running();
}

rac_result_t SolutionRunner::feed(Item item) {
    std::shared_ptr<OperatorEdge>              input;
    std::shared_ptr<rac::graph::CancelToken>   token;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_ || !scheduler_) return RAC_ERROR_COMPONENT_NOT_READY;
        input = root_input_;
        token = scheduler_->root_cancel_token();
    }
    if (!input) return RAC_ERROR_INVALID_STATE;
    const bool ok = input->push(std::move(item), token.get());
    return ok ? RAC_SUCCESS : RAC_ERROR_CANCELLED;
}

void SolutionRunner::close_input() {
    std::shared_ptr<OperatorEdge> input;
    {
        std::lock_guard<std::mutex> lock(mu_);
        input = root_input_;
    }
    if (input) input->close();
}

}  // namespace rac::solutions
