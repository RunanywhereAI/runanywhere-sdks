// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "graph_scheduler.h"

#include <exception>
#include <utility>

#include "ra_primitives.h"

namespace ra::core {

GraphScheduler::GraphScheduler() = default;

GraphScheduler::~GraphScheduler() {
    stop_and_join();
}

void GraphScheduler::add_node(std::shared_ptr<PipelineNode> node) {
    nodes_.push_back(std::move(node));
}

void GraphScheduler::start() {
    if (!root_cancel_) {
        root_cancel_ = CancelToken::create();
    }

    // initialize() all nodes before any worker thread starts — any exception
    // here must tear the DAG down cleanly, calling finalize() on every node
    // that already initialized successfully so they can release engine
    // sessions / file handles / threads before the scheduler object unwinds.
    std::size_t initialized_prefix = 0;
    for (auto& node : nodes_) {
        try {
            node->initialize();
            ++initialized_prefix;
        } catch (const std::exception& e) {
            {
                std::lock_guard<std::mutex> lk(error_mu_);
                first_error_message_ =
                    std::string("initialize() failed for '") +
                    std::string(node->name()) + "': " + e.what();
            }
            error_seen_.store(true, std::memory_order_release);
            root_cancel_->cancel();

            // Finalize every node that was successfully initialized before
            // the failure, in reverse order. finalize() is noexcept by
            // contract.
            for (std::size_t i = initialized_prefix; i > 0; --i) {
                try {
                    nodes_[i - 1]->finalize();
                } catch (...) {
                    // swallow — finalize must not throw, but we defend.
                }
            }
            maybe_signal_completion();
            return;
        }
    }

    alive_count_.store(nodes_.size(), std::memory_order_release);
    threads_.reserve(nodes_.size());
    for (auto& node : nodes_) {
        threads_.emplace_back(&GraphScheduler::thread_body, this, node);
    }
}

void GraphScheduler::stop_and_join() {
    if (root_cancel_) root_cancel_->cancel();
    for (auto& t : threads_) {
        if (t.joinable()) t.join();
    }
    threads_.clear();
    maybe_signal_completion();
}

void GraphScheduler::thread_body(std::shared_ptr<PipelineNode> node) {
    try {
        node->run();
    } catch (const std::exception& e) {
        {
            std::lock_guard<std::mutex> lk(error_mu_);
            if (first_error_message_.empty()) {
                first_error_message_ =
                    std::string("run() failed for '") +
                    std::string(node->name()) + "': " + e.what();
            }
        }
        error_seen_.store(true, std::memory_order_release);
        if (root_cancel_) root_cancel_->cancel();
    } catch (...) {
        {
            std::lock_guard<std::mutex> lk(error_mu_);
            if (first_error_message_.empty()) {
                first_error_message_ =
                    std::string("run() failed for '") +
                    std::string(node->name()) + "': unknown exception";
            }
        }
        error_seen_.store(true, std::memory_order_release);
        if (root_cancel_) root_cancel_->cancel();
    }

    try {
        node->finalize();
    } catch (...) {
        // finalize is noexcept by contract but swallow anyway.
    }

    if (alive_count_.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        maybe_signal_completion();
    }
}

void GraphScheduler::maybe_signal_completion() {
    bool expected = false;
    if (!completion_fired_.compare_exchange_strong(expected, true,
                                                    std::memory_order_acq_rel)) {
        return;
    }
    if (!on_complete_) return;

    int         status = RA_OK;
    std::string msg;
    {
        std::lock_guard<std::mutex> lk(error_mu_);
        if (error_seen_.load(std::memory_order_acquire)) {
            status = RA_ERR_INTERNAL;
            msg    = first_error_message_;
        } else if (root_cancel_ && root_cancel_->is_cancelled()) {
            status = RA_ERR_CANCELLED;
            msg    = "pipeline cancelled";
        }
    }
    on_complete_(status, std::move(msg));
}

}  // namespace ra::core
