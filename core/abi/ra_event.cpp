// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_event.h"

#include <atomic>
#include <map>
#include <mutex>
#include <vector>

namespace {

struct Subscription {
    ra_event_category_t  category;
    ra_event_callback_fn cb;
    void*                user_data;
    bool                 all;
};

std::mutex                                  g_mu;
std::map<int32_t, Subscription>             g_subs;
std::atomic<int32_t>                        g_next_id{1};

ra_event_callback_fn                        g_global_cb       = nullptr;
void*                                       g_global_user     = nullptr;
ra_event_callback_fn                        g_analytics_cb    = nullptr;
void*                                       g_analytics_user  = nullptr;
ra_event_callback_fn                        g_public_cb       = nullptr;
void*                                       g_public_user     = nullptr;

}  // namespace

extern "C" {

ra_event_subscription_id_t ra_event_subscribe(ra_event_category_t  category,
                                                ra_event_callback_fn cb,
                                                void*                user_data) {
    if (!cb) return -1;
    std::lock_guard lock(g_mu);
    const int32_t id = g_next_id.fetch_add(1);
    g_subs[id] = Subscription{category, cb, user_data, false};
    return id;
}

ra_event_subscription_id_t ra_event_subscribe_all(ra_event_callback_fn cb,
                                                    void*                user_data) {
    if (!cb) return -1;
    std::lock_guard lock(g_mu);
    const int32_t id = g_next_id.fetch_add(1);
    g_subs[id] = Subscription{RA_EVENT_CATEGORY_UNKNOWN, cb, user_data, true};
    return id;
}

ra_status_t ra_event_unsubscribe(ra_event_subscription_id_t id) {
    std::lock_guard lock(g_mu);
    return g_subs.erase(id) > 0 ? RA_OK : RA_ERR_INVALID_ARGUMENT;
}

ra_status_t ra_event_set_callback(ra_event_callback_fn cb, void* user_data) {
    std::lock_guard lock(g_mu);
    g_global_cb   = cb;
    g_global_user = user_data;
    return RA_OK;
}

ra_status_t ra_analytics_events_set_callback(ra_event_callback_fn cb, void* user_data) {
    std::lock_guard lock(g_mu);
    g_analytics_cb   = cb;
    g_analytics_user = user_data;
    return RA_OK;
}

ra_status_t ra_analytics_events_set_public_callback(ra_event_callback_fn cb, void* user_data) {
    std::lock_guard lock(g_mu);
    g_public_cb   = cb;
    g_public_user = user_data;
    return RA_OK;
}

void ra_event_publish(const ra_event_t* event) {
    if (!event) return;

    // Snapshot subscribers so callbacks run without the lock held (avoids
    // deadlock if a callback subscribes/unsubscribes).
    std::vector<Subscription> snapshot;
    ra_event_callback_fn      g_cb       = nullptr;
    void*                     g_user     = nullptr;
    ra_event_callback_fn      a_cb       = nullptr;
    void*                     a_user     = nullptr;
    ra_event_callback_fn      p_cb       = nullptr;
    void*                     p_user     = nullptr;
    {
        std::lock_guard lock(g_mu);
        snapshot.reserve(g_subs.size());
        for (const auto& [id, s] : g_subs) {
            if (s.all || s.category == event->category) snapshot.push_back(s);
        }
        g_cb = g_global_cb;     g_user = g_global_user;
        a_cb = g_analytics_cb;  a_user = g_analytics_user;
        p_cb = g_public_cb;     p_user = g_public_user;
    }
    for (const auto& s : snapshot) s.cb(event, s.user_data);
    if (g_cb) g_cb(event, g_user);
    if (event->category == RA_EVENT_CATEGORY_TELEMETRY && a_cb) a_cb(event, a_user);
    if (p_cb) p_cb(event, p_user);
}

}  // extern "C"
