// SPDX-License-Identifier: Apache-2.0
//
// solution_runner.cpp — T4.7 lifecycle owner for compiled PipelineSpecs.

#include "rac/solutions/solution_runner.hpp"

#include <memory>
#include <mutex>
#include <utility>

#include "rac/core/rac_error.h"
#include "rac/solutions/operator_registry.hpp"
#include "rac/solutions/pipeline_executor.hpp"
#include "rac/solutions/solution_converter.hpp"

namespace rac::solutions {

SolutionRunner::SolutionRunner(const runanywhere::v1::SolutionConfig& config) {
    init_status_ = convert_solution_to_pipeline(config, &spec_);
}

SolutionRunner::SolutionRunner(runanywhere::v1::PipelineSpec spec) : spec_(std::move(spec)) {}

SolutionRunner::~SolutionRunner() {
    cancel();
    wait();
}

rac_result_t SolutionRunner::start() {
    std::lock_guard<std::mutex> lock(mu_);
    if (init_status_ != RAC_SUCCESS)
        return init_status_;
    if (started_)
        return RAC_ERROR_ALREADY_INITIALIZED;

    executor_ = std::make_unique<PipelineExecutor>(spec_);
    rac_result_t build_status = RAC_SUCCESS;
    scheduler_ = executor_->build(&build_status);
    if (!scheduler_) {
        executor_.reset();
        return build_status == RAC_SUCCESS ? RAC_ERROR_INVALID_CONFIGURATION : build_status;
    }
    root_input_ = executor_->root_input_edge();
    root_output_ = executor_->root_output_edge();
    root_input_payload_type_ = executor_->root_input_payload_type();
    root_output_payload_type_ = executor_->root_output_payload_type();

    scheduler_->start();
    started_ = true;
    joined_ = false;
    return RAC_SUCCESS;
}

void SolutionRunner::stop() {
    std::shared_ptr<OperatorEdge> input;
    rac::graph::GraphScheduler* sched = nullptr;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_)
            return;
        input = root_input_;
        sched = scheduler_.get();
    }
    if (input)
        input->close();
    if (sched)
        sched->stop();
}

void SolutionRunner::cancel() {
    rac::graph::GraphScheduler* sched = nullptr;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_)
            return;
        sched = scheduler_.get();
    }
    if (sched)
        sched->cancel_all();
}

void SolutionRunner::wait() {
    std::unique_ptr<rac::graph::GraphScheduler> sched;
    std::unique_ptr<PipelineExecutor> exec;
    std::shared_ptr<OperatorEdge> in_edge;
    std::shared_ptr<OperatorEdge> out_edge;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_ || joined_)
            return;
        sched = std::move(scheduler_);
        exec = std::move(executor_);
        in_edge = std::move(root_input_);
        out_edge = std::move(root_output_);
        root_input_payload_type_.clear();
        root_output_payload_type_.clear();
        joined_ = true;
        started_ = false;
    }
    if (in_edge)
        in_edge->close();
    if (sched)
        sched->wait();
    // Drain any residual items sitting in the tail output edge so the
    // graph releases memory promptly. Non-blocking because the
    // scheduler has already joined.
    if (out_edge) {
        while (true) {
            auto v = out_edge->try_pop();
            if (!v)
                break;
        }
    }
    sched.reset();
    exec.reset();
    // Promote any cross-thread error detail recorded by an operator (in a
    // scheduler worker thread) into the calling thread's thread_local
    // `rac_error_set_details` slot so the C ABI reflects the honest cause.
    std::string op_detail = rac::solutions::consume_operator_error_detail();
    if (!op_detail.empty()) {
        rac_error_set_details(op_detail.c_str());
    }
}

bool SolutionRunner::running() const noexcept {
    std::lock_guard<std::mutex> lock(mu_);
    return started_ && scheduler_ && scheduler_->running();
}

rac_result_t SolutionRunner::feed(Item item) {
    std::shared_ptr<OperatorEdge> input;
    std::shared_ptr<rac::graph::CancelToken> token;
    std::string expected_type;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!started_ || !scheduler_)
            return RAC_ERROR_COMPONENT_NOT_READY;
        input = root_input_;
        token = scheduler_->root_cancel_token();
        expected_type = root_input_payload_type_;
    }
    if (!input)
        return RAC_ERROR_INVALID_STATE;
    if (expected_type.empty()) {
        rac_error_set_details("solution root input has no resolved payload type contract");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    std::string body_err;
    if (!item.validate_body_contract(&body_err)) {
        const std::string msg = "solution feed payload body contract violation: " + body_err;
        rac_error_set_details(msg.c_str());
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (item.type_id != expected_type) {
        const std::string msg = "solution feed payload type '" + item.type_id +
                                "' does not match root input payload type '" + expected_type + "'";
        rac_error_set_details(msg.c_str());
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const bool ok = input->push(std::move(item), token.get());
    return ok ? RAC_SUCCESS : RAC_ERROR_CANCELLED;
}

void SolutionRunner::close_input() {
    std::shared_ptr<OperatorEdge> input;
    {
        std::lock_guard<std::mutex> lock(mu_);
        input = root_input_;
    }
    if (input)
        input->close();
}

}  // namespace rac::solutions
