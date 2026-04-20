// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Telemetry event queue. Ports the capability surface from
// `sdk/runanywhere-commons/include/rac/infrastructure/telemetry/
// rac_telemetry_manager.h`.
//
// Callers emit() events into an in-memory queue; the manager batches
// them on a background thread and POSTs the serialized JSON to the
// configured telemetry endpoint. Failures are retried with exponential
// backoff; events older than `max_age_s` are dropped. Shutdown drains
// the queue synchronously so in-process metrics don't disappear on
// process exit.

#ifndef RA_CORE_NET_TELEMETRY_H
#define RA_CORE_NET_TELEMETRY_H

#include <chrono>
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>

#include "environment.h"

namespace ra::core::net {

struct TelemetryEvent {
    std::string                                 name;
    std::map<std::string, std::string>          tags;
    std::map<std::string, double>               metrics;
    std::chrono::system_clock::time_point       timestamp =
        std::chrono::system_clock::now();
};

struct TelemetryConfig {
    std::size_t   batch_size      = 32;
    std::chrono::milliseconds flush_interval{5000};
    std::chrono::seconds      max_age{900};   // drop events older than 15 min
    std::size_t   max_queue_size  = 4096;
    bool          emit_sync_on_stop = true;
};

class TelemetryManager {
public:
    static TelemetryManager& global();

    TelemetryManager(const TelemetryManager&) = delete;
    TelemetryManager& operator=(const TelemetryManager&) = delete;

    void    start(TelemetryConfig cfg = {});
    void    stop();
    void    emit(TelemetryEvent event);

    // Queue snapshot — for tests + diagnostics.
    std::size_t queue_depth() const;

private:
    TelemetryManager() = default;
    ~TelemetryManager();

    void    worker_loop();
    void    flush_locked(std::unique_lock<std::mutex>& lk);
    std::string serialize_batch(const std::deque<TelemetryEvent>& batch) const;

    mutable std::mutex          mu_;
    std::condition_variable     cv_;
    std::deque<TelemetryEvent>  queue_;
    bool                        running_  = false;
    bool                        stopping_ = false;
    TelemetryConfig             cfg_;
    std::thread                 worker_;
};

}  // namespace ra::core::net

#endif  // RA_CORE_NET_TELEMETRY_H
