// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "telemetry.h"

#include <chrono>
#include <sstream>
#include <utility>

#include "http_client.h"

namespace ra::core::net {

TelemetryManager& TelemetryManager::global() {
    static TelemetryManager inst;
    return inst;
}

TelemetryManager::~TelemetryManager() {
    stop();
}

void TelemetryManager::start(TelemetryConfig cfg) {
    std::lock_guard<std::mutex> lk(mu_);
    if (running_) return;
    cfg_      = cfg;
    stopping_ = false;
    running_  = true;
    worker_   = std::thread([this] { worker_loop(); });
}

void TelemetryManager::stop() {
    std::unique_lock<std::mutex> lk(mu_);
    if (!running_) return;
    stopping_ = true;
    cv_.notify_all();
    lk.unlock();

    if (worker_.joinable()) worker_.join();

    lk.lock();
    if (cfg_.emit_sync_on_stop && !queue_.empty()) {
        flush_locked(lk);
    }
    running_ = false;
}

void TelemetryManager::emit(TelemetryEvent event) {
    std::lock_guard<std::mutex> lk(mu_);
    if (queue_.size() >= cfg_.max_queue_size) {
        // Backpressure: drop oldest to keep the newest visible.
        queue_.pop_front();
    }
    queue_.push_back(std::move(event));
    cv_.notify_one();
}

std::size_t TelemetryManager::queue_depth() const {
    std::lock_guard<std::mutex> lk(mu_);
    return queue_.size();
}

void TelemetryManager::worker_loop() {
    std::unique_lock<std::mutex> lk(mu_);
    while (!stopping_) {
        // Wait until either the batch is full, the flush interval elapsed,
        // or shutdown was requested.
        cv_.wait_for(lk, cfg_.flush_interval, [this] {
            return stopping_ || queue_.size() >= cfg_.batch_size;
        });
        if (stopping_) break;
        if (!queue_.empty()) flush_locked(lk);
    }
}

void TelemetryManager::flush_locked(std::unique_lock<std::mutex>& lk) {
    if (queue_.empty()) return;

    // Drop expired events.
    const auto now = std::chrono::system_clock::now();
    const auto cutoff = now - cfg_.max_age;
    while (!queue_.empty() && queue_.front().timestamp < cutoff) {
        queue_.pop_front();
    }
    if (queue_.empty()) return;

    // Snapshot up to batch_size events and release the lock for the
    // network round-trip.
    std::deque<TelemetryEvent> batch;
    const std::size_t n = std::min(cfg_.batch_size, queue_.size());
    for (std::size_t i = 0; i < n; ++i) {
        batch.push_back(std::move(queue_.front()));
        queue_.pop_front();
    }
    const auto payload = serialize_batch(batch);
    const auto url     = AuthManager::global().endpoints().telemetry_url;
    const auto api_key = AuthManager::global().api_key();

    lk.unlock();
    // Best-effort POST. Failure doesn't re-enqueue — we prefer bounded
    // memory to perfect delivery.
    auto client = HttpClient::create();
    HttpRequest req;
    req.method       = HttpMethod::kPost;
    req.url          = url;
    req.body         = payload;
    req.headers["Content-Type"] = "application/json";
    if (!api_key.empty()) {
        req.headers["Authorization"] = "Bearer " + api_key;
    }
    req.connect_s = 5;
    req.timeout_s = 15;
    (void)client->send(req);
    lk.lock();
}

std::string TelemetryManager::serialize_batch(
        const std::deque<TelemetryEvent>& batch) const {
    // Minimal JSON writer — no external dep. Hand-written because the
    // event shape is known + fixed and the perf bar here is "not the
    // bottleneck", not "fastest json writer".
    auto escape = [](std::string_view s) {
        std::string out;
        out.reserve(s.size() + 2);
        out.push_back('"');
        for (char c : s) {
            switch (c) {
                case '"':  out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n");  break;
                case '\r': out.append("\\r");  break;
                case '\t': out.append("\\t");  break;
                default:
                    if (static_cast<unsigned char>(c) < 0x20) {
                        char buf[8];
                        std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                        out.append(buf);
                    } else {
                        out.push_back(c);
                    }
            }
        }
        out.push_back('"');
        return out;
    };

    std::ostringstream oss;
    oss << "{\"events\":[";
    bool first_evt = true;
    for (const auto& e : batch) {
        if (!first_evt) oss << ',';
        first_evt = false;
        oss << "{\"name\":" << escape(e.name);
        const auto ts_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            e.timestamp.time_since_epoch()).count();
        oss << ",\"ts_ms\":" << ts_ms;
        if (!e.tags.empty()) {
            oss << ",\"tags\":{";
            bool first = true;
            for (const auto& [k, v] : e.tags) {
                if (!first) oss << ',';
                first = false;
                oss << escape(k) << ':' << escape(v);
            }
            oss << '}';
        }
        if (!e.metrics.empty()) {
            oss << ",\"metrics\":{";
            bool first = true;
            for (const auto& [k, v] : e.metrics) {
                if (!first) oss << ',';
                first = false;
                oss << escape(k) << ':' << v;
            }
            oss << '}';
        }
        oss << '}';
    }
    oss << "]}";
    return oss.str();
}

}  // namespace ra::core::net
