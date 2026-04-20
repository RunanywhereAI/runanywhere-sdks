// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// L3 engine router — chooses an L2 engine given a (primitive, model_format,
// hardware, memory_budget) tuple.
//
// Priority, highest to lowest:
//   1. capability match (primitive must be served)
//   2. format match    (model file must load)
//   3. hardware match  (prefer engines that use local accelerators)
//   4. memory fit      (refuse if model would OOM)
//
// The router is stateless — it reads from the PluginRegistry on every call.

#ifndef RA_CORE_ENGINE_ROUTER_H
#define RA_CORE_ENGINE_ROUTER_H

#include <cstddef>
#include <string_view>

#include "ra_primitives.h"
#include "plugin_registry.h"
#include "hardware_profile.h"

namespace ra::core {

struct RouteRequest {
    ra_primitive_t     primitive;
    ra_model_format_t  format;
    std::size_t        estimated_memory_bytes = 0;
    std::string_view   pinned_engine;   // Empty = no pin.
};

struct RouteResult {
    // Ref-counted handle — safe to retain even if the registry is mutated
    // concurrently. Empty when no engine matches.
    PluginHandleRef     plugin;
    int                 score  = 0;      // Higher = better match.
    std::string         rejection_reason;
};

class EngineRouter {
public:
    EngineRouter(PluginRegistry& registry, HardwareProfile hw)
        : registry_(registry), hw_(std::move(hw)) {}

    // Select the best engine for `request`. If `pinned_engine` is non-empty,
    // the router looks up that engine by name and returns it regardless of
    // other scoring (still subject to format + memory checks).
    RouteResult route(const RouteRequest& request) const;

    void refresh_hardware() { hw_ = HardwareProfile::detect(); }
    const HardwareProfile& hardware() const noexcept { return hw_; }

private:
    int score_plugin(const PluginHandle& plugin,
                     const RouteRequest& request) const;

    PluginRegistry& registry_;
    HardwareProfile hw_;
};

}  // namespace ra::core

#endif  // RA_CORE_ENGINE_ROUTER_H
