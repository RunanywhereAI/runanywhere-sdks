/**
 * @file rac_engine_router.cpp
 * @brief Engine-router scoring implementation.
 *
 * GAP 04 Phase 10 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 * T4.1 extension — see sdk/runanywhere-commons/docs/RUNTIME_VTABLE_DESIGN.md.
 *
 * Scoring stack (all weights deliberately small and well-separated so the
 * ordering is easy to reason about when debugging a routing decision):
 *
 *   base        = metadata.priority
 *   +30         preferred_runtime declared AND hardware-profile confirmed
 *   +15         any declared runtime is registered in the L1 runtime registry
 *   +10         model-format match
 *   +10000      pinned-engine name match (short-circuit; beats all scoring)
 *   -1000       hard reject: primitive not served OR pinned-name mismatch
 *
 * The T4.1 +15 bonus makes the router prefer engines whose compute runtime
 * has actually been loaded in-process over ones that merely *could* run on
 * this host. It is strictly smaller than the +30 preferred_runtime bonus so
 * callers who explicitly request a runtime keep control of the decision.
 */

#include "rac/router/rac_engine_router.h"

#include <algorithm>
#include <cstring>
#include <vector>

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_runtime_registry.h"

namespace rac {
namespace router {

namespace {

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

}  // namespace

EngineRouter::EngineRouter(const HardwareProfile& profile) : profile_(profile) {}

bool EngineRouter::serves(const rac_engine_vtable_t& vt, rac_primitive_t p) const {
    return rac_engine_vtable_slot(&vt, p) != nullptr;
}

int EngineRouter::score(const rac_engine_vtable_t& vt, const RouteRequest& req) const {
    /* Hard reject: vtable does not serve the requested primitive. */
    if (!serves(vt, req.primitive)) return -1000;

    /* Hard reject: pinned engine name mismatch. */
    if (!req.pinned_engine.empty()) {
        if (vt.metadata.name == nullptr ||
            req.pinned_engine != vt.metadata.name) {
            return -1000;
        }
        /* Pinned-name match is itself a strong signal — give a large bonus
         * so it wins even against higher-priority unpinned plugins. */
        return 10000 + vt.metadata.priority;
    }

    /* Base score = plugin's declared priority. */
    int s = vt.metadata.priority;

    /* GAP 04 Phase 11: +30 when the caller's preferred_runtime is both
     * (a) declared on the plugin and (b) actually available on the host. */
    if (req.preferred_runtime != RAC_RUNTIME_UNSPECIFIED &&
        profile_.supports_runtime(req.preferred_runtime) &&
        vt.metadata.runtimes != nullptr) {
        for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
            if (vt.metadata.runtimes[i] == req.preferred_runtime) {
                s += 30;
                break;
            }
        }
    }

    /* T4.1: +15 when any of the plugin's declared runtimes is *registered*
     * in the L1 runtime registry. A registered runtime is a strictly
     * stronger signal than hardware presence alone (it means someone has
     * already loaded and initialised the runtime plugin), so we layer this
     * bonus on top of the preferred-runtime bonus above. Capped at a single
     * +15 per plugin so declaring many runtimes doesn't farm points. */
    if (vt.metadata.runtimes != nullptr) {
        for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
            if (rac_runtime_is_available(vt.metadata.runtimes[i])) {
                s += 15;
                break;
            }
        }
    }

    /* +10 when the caller's model format matches one of the plugin's
     * declared formats. 0 = no format hint; skip the check. */
    if (req.format != 0 && vt.metadata.formats != nullptr) {
        for (size_t i = 0; i < vt.metadata.formats_count; ++i) {
            if (vt.metadata.formats[i] == req.format) {
                s += 10;
                break;
            }
        }
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
    for (auto* vt : candidates) {
        if (vt == nullptr) continue;
        int s = score(*vt, req);
        if (s > -1000) {
            scored.push_back({s, vt});
        }
    }
    if (scored.empty()) {
        if (!req.pinned_engine.empty() && req.no_fallback) {
            return RouteResult{nullptr, -1,
                               std::string("pinned engine '") +
                               std::string(req.pinned_engine) +
                               "' not registered; no_fallback=true"};
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
