// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Stub TelemetryManager used when RA_BUILD_HTTP_CLIENT=OFF. No HTTP
// transport is available so emit() queues in memory (bounded), start()/
// stop() are no-ops. Platform adapters that want real upload install
// an HTTP callback via `ra_telemetry_set_http_callback` (ABI-level);
// that path does not depend on TelemetryManager.

#include "telemetry.h"

namespace ra::core::net {

TelemetryManager& TelemetryManager::global() {
    static TelemetryManager instance;  // leverages private default ctor
    return instance;
}

TelemetryManager::~TelemetryManager() = default;

void TelemetryManager::start(TelemetryConfig cfg) {
    std::lock_guard lk(mu_);
    cfg_     = std::move(cfg);
    running_ = true;
}

void TelemetryManager::stop() {
    std::lock_guard lk(mu_);
    running_  = false;
    stopping_ = true;
    queue_.clear();
}

void TelemetryManager::emit(TelemetryEvent event) {
    std::lock_guard lk(mu_);
    if (queue_.size() >= cfg_.max_queue_size) queue_.pop_front();
    queue_.push_back(std::move(event));
}

std::size_t TelemetryManager::queue_depth() const {
    std::lock_guard lk(mu_);
    return queue_.size();
}

// The real manager spins a worker thread; the stub leaves these as
// no-ops so we don't pull in pthread startup cost on small builds.
void TelemetryManager::worker_loop() {}
void TelemetryManager::flush_locked(std::unique_lock<std::mutex>&) {}
std::string TelemetryManager::serialize_batch(
    const std::deque<TelemetryEvent>&) const { return "{}"; }

}  // namespace ra::core::net
