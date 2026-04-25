// SPDX-License-Identifier: Apache-2.0
//
// graph_scheduler.cpp — implementation of the v3.1 Phase 9 DAG runtime.
// See include/rac/graph/graph_scheduler.hpp for contract + design notes.

#include "rac/graph/graph_scheduler.hpp"

#include <utility>

namespace rac::graph {

GraphScheduler::GraphScheduler(size_t thread_pool_size)
    : thread_pool_size_(thread_pool_size == 0 ? 1u : thread_pool_size),
      root_(std::make_shared<CancelToken>()) {}

GraphScheduler::~GraphScheduler() {
    // Best-effort shutdown so a graph that's dropped mid-run doesn't leave
    // worker threads behind. Caller really should have called stop()+wait().
    cancel_all();
    wait();
}

void GraphScheduler::add_node(std::shared_ptr<IPipelineNode> node) {
    if (!node) return;
    std::lock_guard<std::mutex> lock(mu_);
    nodes_.emplace_back(std::move(node));
}

void GraphScheduler::start() {
    std::vector<std::shared_ptr<IPipelineNode>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (started_) return;
        started_ = true;
        snapshot = nodes_;
    }
    // Start outside the lock so a node's start() is free to call back
    // into the scheduler (e.g. query node_count()) without deadlock.
    for (auto& node : snapshot) {
        node->start(root_);
    }
}

void GraphScheduler::stop() {
    std::vector<std::shared_ptr<IPipelineNode>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (stopped_) return;
        stopped_ = true;
        snapshot = nodes_;
    }
    for (auto& node : snapshot) {
        node->stop();
    }
}

void GraphScheduler::wait() {
    std::vector<std::shared_ptr<IPipelineNode>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mu_);
        snapshot = nodes_;
    }
    for (auto& node : snapshot) {
        node->join();
    }
}

void GraphScheduler::cancel_all() {
    if (root_) root_->cancel();
    // Also close every input edge so blocked pops unblock immediately
    // instead of waiting up to the 50 ms cancel-poll timeout.
    stop();
}

bool GraphScheduler::running() const noexcept {
    std::lock_guard<std::mutex> lock(mu_);
    return started_ && !stopped_;
}

size_t GraphScheduler::node_count() const {
    std::lock_guard<std::mutex> lock(mu_);
    return nodes_.size();
}

}  // namespace rac::graph
