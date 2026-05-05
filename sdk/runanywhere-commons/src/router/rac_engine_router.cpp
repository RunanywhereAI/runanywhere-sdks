/**
 * @file rac_engine_router.cpp
 * @brief Engine-router scoring implementation.
 *
 * GAP 04 Phase 10 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 * T4.1 extension. CPP-05 hardening: declared runtimes are now an executable
 * contract — engines whose declared L1 runtimes are not registered on this
 * host are removed from candidate selection and surface a dedicated
 * `RAC_ERROR_RUNTIME_UNAVAILABLE` through `rac_plugin_route`.
 *
 * Scoring stack (all weights deliberately explicit so a routing decision can
 * be explained as primitive/model/runtime/hardware components):
 *
 *   base               = metadata.priority
 *   primitive          = hard gate: requested primitive must have an ops slot
 *   runtime_compat     = +40 when a declared runtime is registered
 *   hardware_profile   = +20 when preferred_runtime is declared, registered,
 *                        and supported by the hardware profile
 *   model_format       = +10 when requested model format is declared
 *   pinned_engine      = +10000 name match short-circuit
 *   reject             = -1000 primitive miss, pin mismatch, or declared
 *                        runtime set with no registered runtime
 *
 * Descriptor-only legacy plugins (`metadata.runtimes == NULL`) remain routable
 * by priority. New plugins that declare runtimes are treated as executable
 * contracts: no registered runtime, no route.
 */

#include "rac/router/rac_engine_router.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_runtime_registry.h"

namespace rac {
namespace router {

namespace {

constexpr int kRejectScore = -1000;
/* Sentinel score used when a candidate is hard-rejected specifically
 * because none of its declared runtimes are registered. Distinct from
 * kRejectScore so the router can emit a precise rejection reason without
 * adding a parallel bookkeeping vector. Both values are filtered out by
 * `score > kRejectScore` (strict >) so neither becomes a candidate. */
constexpr int kRuntimeRejectScore = -1001;
constexpr int kPinnedEngineBonus = 10000;
constexpr int kRuntimeCompatibilityWeight = 40;
constexpr int kHardwareProfileWeight = 20;
constexpr int kModelFormatWeight = 10;

/** Snapshot the global registry's vtables for `primitive`, descending priority.
 *  Uses the C ABI `rac_plugin_list` so we don't reach into registry internals. */
std::vector<const rac_engine_vtable_t*> snapshot_for_primitive(rac_primitive_t p) {
    constexpr size_t kMax = 64;  /* cap; no realistic deployment has more engines per primitive */
    const rac_engine_vtable_t* buf[kMax] = {nullptr};
    size_t n = 0;
    if (rac_plugin_list(p, buf, kMax, &n) != RAC_SUCCESS) return {};
    std::vector<const rac_engine_vtable_t*> v;
    v.reserve(n);
    for (size_t i = 0; i < n; ++i) v.push_back(buf[i]);
    return v;
}

bool declares_runtime(const rac_engine_vtable_t& vt, rac_runtime_id_t runtime) {
    if (runtime == RAC_RUNTIME_UNSPECIFIED || vt.metadata.runtimes == nullptr) return false;
    for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
        if (vt.metadata.runtimes[i] == runtime) return true;
    }
    return false;
}

/* True when the engine either (a) declares no runtimes (legacy / opt-out of
 * runtime-aware routing) or (b) at least one of its declared runtimes is
 * currently registered with the L1 runtime registry. False is the only
 * value that triggers the runtime-unavailable hard reject. */
bool has_registered_declared_runtime(const rac_engine_vtable_t& vt) {
    if (vt.metadata.runtimes == nullptr || vt.metadata.runtimes_count == 0) return true;
    for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
        if (rac_runtime_is_registered(vt.metadata.runtimes[i])) return true;
    }
    return false;
}

bool preferred_runtime_registered(const rac_engine_vtable_t& vt, rac_runtime_id_t runtime) {
    return declares_runtime(vt, runtime) && rac_runtime_is_registered(runtime);
}

bool matches_model_format(const rac_engine_vtable_t& vt, uint32_t format) {
    if (format == 0 || vt.metadata.formats == nullptr) return false;
    for (size_t i = 0; i < vt.metadata.formats_count; ++i) {
        if (vt.metadata.formats[i] == format) return true;
    }
    return false;
}

}  // namespace

EngineRouter::EngineRouter(const HardwareProfile& profile) : profile_(profile) {}

bool EngineRouter::serves(const rac_engine_vtable_t& vt, rac_primitive_t p) const {
    return rac_engine_vtable_slot(&vt, p) != nullptr;
}

int EngineRouter::score(const rac_engine_vtable_t& vt, const RouteRequest& req) const {
    /* Hard reject: vtable does not serve the requested primitive. */
    if (!serves(vt, req.primitive)) return kRejectScore;

    /* Hard reject: pinned engine name mismatch. */
    if (!req.pinned_engine.empty()) {
        if (vt.metadata.name == nullptr ||
            req.pinned_engine != vt.metadata.name) {
            return kRejectScore;
        }
        /* Pinned-name match is itself a strong signal — give a large bonus
         * so it wins even against higher-priority unpinned plugins. */
        return kPinnedEngineBonus + vt.metadata.priority;
    }

    /* Hard reject — distinct sentinel: engine declares one or more L1 runtimes
     * but none of them are registered on this host. Surfaced as
     * `RAC_ERROR_RUNTIME_UNAVAILABLE` through the C ABI when no other
     * candidate survives. */
    if (!has_registered_declared_runtime(vt)) return kRuntimeRejectScore;

    /* Base score = plugin's declared priority. */
    int s = vt.metadata.priority;

    if (vt.metadata.runtimes != nullptr && vt.metadata.runtimes_count > 0) {
        s += kRuntimeCompatibilityWeight;
    }

    if (req.preferred_runtime != RAC_RUNTIME_UNSPECIFIED &&
        preferred_runtime_registered(vt, req.preferred_runtime) &&
        profile_.supports_runtime(req.preferred_runtime)) {
        s += kHardwareProfileWeight;
    }

    /* +10 when the caller's model format matches one of the plugin's
     * declared formats. 0 = no format hint; skip the check. */
    if (matches_model_format(vt, req.format)) {
        s += kModelFormatWeight;
    }

    return s;
}

RouteResult EngineRouter::route(const RouteRequest& req) const {
    auto candidates = snapshot_for_primitive(req.primitive);
    if (candidates.empty()) {
        return RouteResult{nullptr, -1, "no plugin serves this primitive"};
    }

    /* Score every candidate. */
    struct Scored {
        int                       score;
        const rac_engine_vtable_t* vt;
    };
    std::vector<Scored> scored;
    scored.reserve(candidates.size());
    /* Track whether every rejected candidate failed *only* because of
     * runtime unavailability — that promotes the rejection_reason from the
     * generic "all hard-rejected" message to a runtime-specific one that
     * the C ABI maps to `RAC_ERROR_RUNTIME_UNAVAILABLE`. */
    bool any_runtime_reject = false;
    bool any_other_reject = false;
    for (auto* vt : candidates) {
        if (vt == nullptr) continue;
        int s = score(*vt, req);
        if (s > kRejectScore) {
            scored.push_back({s, vt});
        } else if (s == kRuntimeRejectScore) {
            any_runtime_reject = true;
        } else {
            any_other_reject = true;
        }
    }
    if (scored.empty()) {
        if (!req.pinned_engine.empty() && req.no_fallback) {
            return RouteResult{nullptr, -1,
                               std::string("pinned engine '") +
                               std::string(req.pinned_engine) +
                               "' not registered; no_fallback=true"};
        }
        if (any_runtime_reject && !any_other_reject) {
            return RouteResult{nullptr, -1,
                               "no registered runtime satisfies any candidate "
                               "engine's declared runtimes"};
        }
        return RouteResult{nullptr, -1, "no eligible plugin (all hard-rejected)"};
    }

    /* Stable sort: score desc, priority desc (tiebreak), name asc (final tiebreak).
     * Determinism is required by the spec — same RouteRequest in same process
     * MUST yield same winner across 1000 calls. */
    std::sort(scored.begin(), scored.end(),
              [](const Scored& a, const Scored& b) {
                  if (a.score != b.score) return a.score > b.score;
                  if (a.vt->metadata.priority != b.vt->metadata.priority) {
                      return a.vt->metadata.priority > b.vt->metadata.priority;
                  }
                  return std::strcmp(a.vt->metadata.name, b.vt->metadata.name) < 0;
              });

    return RouteResult{scored.front().vt, scored.front().score, {}};
}

std::vector<RouteResult> EngineRouter::route_all(const RouteRequest& req) const {
    auto candidates = snapshot_for_primitive(req.primitive);
    std::vector<RouteResult> out;
    out.reserve(candidates.size());
    for (auto* vt : candidates) {
        if (vt == nullptr) continue;
        int s = score(*vt, req);
        out.push_back(RouteResult{vt, s, {}});
    }
    std::sort(out.begin(), out.end(),
              [](const RouteResult& a, const RouteResult& b) {
                  return a.score > b.score;
              });
    return out;
}

}  // namespace router
}  // namespace rac
