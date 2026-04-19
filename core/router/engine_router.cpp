// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "engine_router.h"

#include <algorithm>

namespace ra::core {

namespace {

bool plugin_serves(const PluginHandle& plugin, ra_primitive_t p) {
    const auto& md = plugin.vtable.metadata;
    for (std::size_t i = 0; i < md.primitives_count; ++i) {
        if (md.primitives[i] == p) return true;
    }
    return false;
}

bool plugin_supports_format(const PluginHandle& plugin, ra_model_format_t f) {
    const auto& md = plugin.vtable.metadata;
    for (std::size_t i = 0; i < md.formats_count; ++i) {
        if (md.formats[i] == f) return true;
    }
    return false;
}

bool plugin_uses_runtime(const PluginHandle& plugin, ra_runtime_id_t r) {
    const auto& md = plugin.vtable.metadata;
    for (std::size_t i = 0; i < md.runtimes_count; ++i) {
        if (md.runtimes[i] == r) return true;
    }
    return false;
}

}  // namespace

int EngineRouter::score_plugin(const PluginHandle& plugin,
                                const RouteRequest& request) const {
    int score = 0;

    // Capability match is a hard gate (caller should have filtered).
    if (!plugin_serves(plugin, request.primitive)) return -1;

    // Format match is a hard gate.
    if (!plugin_supports_format(plugin, request.format)) return -1;

    score += 100;  // base score for matching plugin

    // Prefer self-contained engines (single dependency tree is simpler).
    if (plugin_uses_runtime(plugin, RA_RUNTIME_SELF_CONTAINED)) score += 10;

    // Apple Silicon → prefer engines that use Metal, MLX, or CoreML.
    if (hw_.has_metal) {
        if (plugin_uses_runtime(plugin, RA_RUNTIME_METAL))   score += 40;
        if (plugin_uses_runtime(plugin, RA_RUNTIME_MLX))     score += 40;
        if (plugin_uses_runtime(plugin, RA_RUNTIME_COREML))  score += 30;
    }
    // NVIDIA → prefer CUDA.
    if (hw_.has_cuda) {
        if (plugin_uses_runtime(plugin, RA_RUNTIME_CUDA)) score += 40;
    }
    // Fall back to ORT (cross-platform, no accelerator).
    if (plugin_uses_runtime(plugin, RA_RUNTIME_ORT)) score += 5;

    return score;
}

RouteResult EngineRouter::route(const RouteRequest& request) const {
    RouteResult best;

    // Pinned engine — exact-name lookup with format + memory verification.
    if (!request.pinned_engine.empty()) {
        PluginHandleRef pinned = registry_.find_by_name(request.pinned_engine);
        if (!pinned) {
            best.rejection_reason = std::string("pinned engine not found: ") +
                                    std::string(request.pinned_engine);
            return best;
        }
        if (!plugin_serves(*pinned, request.primitive)) {
            best.rejection_reason =
                "pinned engine does not serve requested primitive";
            return best;
        }
        if (!plugin_supports_format(*pinned, request.format)) {
            best.rejection_reason =
                "pinned engine does not support requested model format";
            return best;
        }
        best.score  = score_plugin(*pinned, request);
        best.plugin = std::move(pinned);
        return best;
    }

    // General search. The enumerate callback receives ref-counted handles;
    // we keep the best one alive via the same shared_ptr stored in
    // RouteResult, so the caller holds a valid reference even if the
    // registry is mutated after the callback returns.
    registry_.enumerate([&](const PluginHandleRef& p) {
        if (!p) return;
        const int s = score_plugin(*p, request);
        if (s > best.score) {
            best.score  = s;
            best.plugin = p;
        }
    });

    if (!best.plugin) {
        best.rejection_reason =
            "no registered plugin serves this (primitive, format) pair";
    }
    return best;
}

}  // namespace ra::core
