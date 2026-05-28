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

#include "accelerator_preference_internal.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "plugin/plugin_registry_internal.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_runtime_registry.h"

namespace rac::router {

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

/* Bonus granted when the engine declares a runtime whose accelerator class
 * matches the process-wide accelerator preference set through
 * `rac_hardware_set_accelerator_preference`. Sized to exceed a base-priority
 * gap of ~30 so a GPU engine with priority 50 beats a CPU engine with
 * priority 50 + runtime_compat (40) when GPU preference is active. */
constexpr int kAcceleratorPreferenceWeight = 50;

/* `runanywhere.v1.AccelerationPreference` values that this router recognises
 * as scoring hints.  Mirrors hardware_profile.proto. */
enum class AcceleratorClass {
    None,  // UNSPECIFIED / AUTO — no scoring effect
    Cpu,
    Gpu,
    Npu,
};

AcceleratorClass preference_to_class(int preference_enum) {
    switch (preference_enum) {
        case 2:
            return AcceleratorClass::Cpu;  // ACCELERATION_PREFERENCE_CPU
        case 3:
            return AcceleratorClass::Gpu;  // ACCELERATION_PREFERENCE_GPU
        case 4:
            return AcceleratorClass::Npu;  // ACCELERATION_PREFERENCE_NPU
        default:
            return AcceleratorClass::None;
    }
}

/* True when the given runtime belongs to the accelerator class. Grouping
 * follows the `rac_runtime_id_t` semantics: Metal / CUDA / Vulkan / WebGPU
 * are GPU-class; ANE / QNN / NNAPI / CoreML are NPU-class (CoreML routes
 * across ANE+GPU+CPU but is most commonly chosen for NPU-leaning workloads);
 * CPU is its own class. */
bool runtime_matches_class(rac_runtime_id_t r, AcceleratorClass c) {
    switch (c) {
        case AcceleratorClass::Cpu:
            return r == RAC_RUNTIME_CPU;
        case AcceleratorClass::Gpu:
            return r == RAC_RUNTIME_METAL || r == RAC_RUNTIME_CUDA || r == RAC_RUNTIME_VULKAN ||
                   r == RAC_RUNTIME_WEBGPU || r == RAC_RUNTIME_HIPBLAS || r == RAC_RUNTIME_OPENCL;
        case AcceleratorClass::Npu:
            return r == RAC_RUNTIME_ANE || r == RAC_RUNTIME_QNN || r == RAC_RUNTIME_NNAPI ||
                   r == RAC_RUNTIME_COREML;
        case AcceleratorClass::None:
        default:
            return false;
    }
}

bool engine_declares_class(const rac_engine_vtable_t& vt, AcceleratorClass c) {
    if (c == AcceleratorClass::None)
        return false;
    if (vt.metadata.runtimes == nullptr)
        return false;
    for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
        if (runtime_matches_class(vt.metadata.runtimes[i], c))
            return true;
    }
    return false;
}

/** Snapshot the global registry's vtables for `primitive`, descending priority.
 *  Uses the C ABI `rac_plugin_list` so we don't reach into registry internals. */
std::vector<const rac_engine_vtable_t*> snapshot_for_primitive(rac_primitive_t p) {
    constexpr size_t kMax = 64; /* cap; no realistic deployment has more engines per primitive */
    const rac_engine_vtable_t* buf[kMax] = {nullptr};
    size_t n = 0;
    if (rac_plugin_list(p, buf, kMax, &n) != RAC_SUCCESS)
        return {};
    std::vector<const rac_engine_vtable_t*> v;
    v.reserve(n);
    for (size_t i = 0; i < n; ++i)
        v.push_back(buf[i]);
    return v;
}

/* commons-007: RAII guard that pins every vtable currently registered against
 * concurrent dynamic unload for the lifetime of the scoring/sorting window.
 * Pairs with `rac_registry_unload_plugin`, which spin-waits the registry's
 * router-inflight counter to zero AFTER `rac_plugin_unregister` (so no NEW
 * router can pick up the about-to-be-unmapped vtable) and BEFORE `dlclose`
 * (so any router still holding a raw vtable pointer can finish reading the
 * plugin's `.rodata` before it is unmapped).
 *
 * Lifetime spans the entire snapshot/score/sort window, not just the
 * snapshot call: once `rac_plugin_list` returns, the router holds raw
 * vtable pointers that it will dereference during scoring and tiebreaking;
 * the pin MUST survive those dereferences. Acquiring BEFORE snapshot also
 * closes the race window where an unload could observe inflight=0 between
 * snapshot-return and our first deref. Stack-only — non-copyable, non-
 * movable, no heap allocation. */
class RouterInflightGuard {
   public:
    RouterInflightGuard() { rac_plugin_registry_router_enter(); }
    ~RouterInflightGuard() { rac_plugin_registry_router_exit(); }
    RouterInflightGuard(const RouterInflightGuard&) = delete;
    RouterInflightGuard& operator=(const RouterInflightGuard&) = delete;
    RouterInflightGuard(RouterInflightGuard&&) = delete;
    RouterInflightGuard& operator=(RouterInflightGuard&&) = delete;
};

bool declares_runtime(const rac_engine_vtable_t& vt, rac_runtime_id_t runtime) {
    if (runtime == RAC_RUNTIME_UNSPECIFIED || vt.metadata.runtimes == nullptr)
        return false;
    for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
        if (vt.metadata.runtimes[i] == runtime)
            return true;
    }
    return false;
}

/* True when the engine either (a) declares no runtimes (legacy / opt-out of
 * runtime-aware routing) or (b) at least one of its declared runtimes is
 * currently registered with the L1 runtime registry. False is the only
 * value that triggers the runtime-unavailable hard reject. */
bool has_registered_declared_runtime(const rac_engine_vtable_t& vt) {
    if (vt.metadata.runtimes == nullptr || vt.metadata.runtimes_count == 0)
        return true;
    for (size_t i = 0; i < vt.metadata.runtimes_count; ++i) {
        if (rac_runtime_is_registered(vt.metadata.runtimes[i]) != 0)
            return true;
    }
    return false;
}

bool preferred_runtime_registered(const rac_engine_vtable_t& vt, rac_runtime_id_t runtime) {
    return declares_runtime(vt, runtime) && rac_runtime_is_registered(runtime) != 0;
}

bool matches_model_format(const rac_engine_vtable_t& vt, uint32_t format) {
    if (format == 0 || vt.metadata.formats == nullptr)
        return false;
    for (size_t i = 0; i < vt.metadata.formats_count; ++i) {
        if (vt.metadata.formats[i] == format)
            return true;
    }
    return false;
}

}  // namespace

EngineRouter::EngineRouter(HardwareProfile profile) : profile_(std::move(profile)) {}

bool EngineRouter::serves(const rac_engine_vtable_t& vt, rac_primitive_t p) const {
    return rac_engine_vtable_slot(&vt, p) != nullptr;
}

int EngineRouter::score(const rac_engine_vtable_t& vt, const RouteRequest& req) const {
    /* Hard reject: vtable does not serve the requested primitive. */
    if (!serves(vt, req.primitive))
        return kRejectScore;

    /* Hard reject: pinned engine name mismatch. */
    if (!req.pinned_engine.empty()) {
        if (vt.metadata.name == nullptr || req.pinned_engine != vt.metadata.name) {
            return kRejectScore;
        }
        /* Pinned-name match still has to satisfy the runtime-unavailable
         * contract: an engine whose declared L1 runtimes are all unregistered
         * cannot execute regardless of pinning. Returning the runtime-reject
         * sentinel here keeps no_fallback=true honest ("only this engine if it
         * is executable") and lets rac_plugin_route surface
         * RAC_ERROR_RUNTIME_UNAVAILABLE instead of a later generic load
         * failure. */
        if (!has_registered_declared_runtime(vt))
            return kRuntimeRejectScore;
        /* Pinned-name match is itself a strong signal — give a large bonus
         * so it wins even against higher-priority unpinned plugins. */
        return kPinnedEngineBonus + vt.metadata.priority;
    }

    /* Hard reject — distinct sentinel: engine declares one or more L1 runtimes
     * but none of them are registered on this host. Surfaced as
     * `RAC_ERROR_RUNTIME_UNAVAILABLE` through the C ABI when no other
     * candidate survives. */
    if (!has_registered_declared_runtime(vt))
        return kRuntimeRejectScore;

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

    /* +kAcceleratorPreferenceWeight when the process-wide accelerator
     * preference (set via `rac_hardware_set_accelerator_preference`)
     * matches an accelerator class declared by the engine. Lets callers
     * steer routing without a per-request `preferred_runtime` hint — e.g.
     * "GPU preferred, any GPU-class runtime is fine." */
    const AcceleratorClass pref_class = preference_to_class(internal::get_accelerator_preference());
    if (pref_class != AcceleratorClass::None && engine_declares_class(vt, pref_class)) {
        s += kAcceleratorPreferenceWeight;
    }

    return s;
}

RouteResult EngineRouter::route(const RouteRequest& req) const {
    /* commons-007: pin every snapshotted vtable for the lifetime of this
     * call. See RouterInflightGuard comment for the unload-side handshake. */
    RouterInflightGuard inflight_guard;

    auto candidates = snapshot_for_primitive(req.primitive);
    if (candidates.empty()) {
        return RouteResult{
            .vtable = nullptr, .score = -1, .rejection_reason = "no plugin serves this primitive"};
    }

    /* Score every candidate. */
    struct Scored {
        int score;
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
    /* commons-160: when the pinned engine itself was rejected purely because
     * its declared runtimes are all unregistered, the user-visible failure is
     * "runtime unavailable" even if other (non-pin) plugins serve the same
     * primitive and were rejected for the pin mismatch. Without this, the
     * router falls through to the generic "pinned engine '<x>' not registered;
     * no_fallback=true" reason — wrong, because the engine IS registered; the
     * failure is missing runtime. Callers (e.g. model_lifecycle) then
     * misclassify and tell the user to install a framework instead of
     * switching device. */
    bool pinned_engine_runtime_rejected = false;
    for (auto* vt : candidates) {
        if (vt == nullptr)
            continue;
        int s = score(*vt, req);
        if (s > kRejectScore) {
            scored.push_back({s, vt});
        } else if (s == kRuntimeRejectScore) {
            any_runtime_reject = true;
            if (!req.pinned_engine.empty() && vt->metadata.name != nullptr &&
                req.pinned_engine == vt->metadata.name) {
                pinned_engine_runtime_rejected = true;
            }
        } else {
            any_other_reject = true;
        }
    }
    if (scored.empty()) {
        /* Runtime-unavailable takes precedence over pinned/no_fallback so the
         * C ABI surfaces RAC_ERROR_RUNTIME_UNAVAILABLE (not NOT_FOUND) when a
         * pinned engine exists in the registry but every one of its declared
         * L1 runtimes is unregistered on this host. Without this ordering
         * model_lifecycle's framework-pinned loads would receive a generic
         * "pinned engine not registered" reason even though the engine is
         * registered and the real failure is missing runtime. */
        if ((any_runtime_reject && !any_other_reject) || pinned_engine_runtime_rejected) {
            return RouteResult{.vtable = nullptr,
                               .score = -1,
                               .rejection_reason =
                                   "no registered runtime satisfies any candidate "
                                   "engine's declared runtimes"};
        }
        if (!req.pinned_engine.empty() && req.no_fallback) {
            return RouteResult{.vtable = nullptr,
                               .score = -1,
                               .rejection_reason = std::string("pinned engine '") +
                                                   std::string(req.pinned_engine) +
                                                   "' not registered; no_fallback=true"};
        }
        return RouteResult{.vtable = nullptr,
                           .score = -1,
                           .rejection_reason = "no eligible plugin (all hard-rejected)"};
    }

    /* Stable sort: score desc, priority desc (tiebreak), name asc (final tiebreak).
     * Determinism is required by the spec — same RouteRequest in same process
     * MUST yield same winner across 1000 calls.
     *
     * commons-090: defensive null-guard on `metadata.name` for the final
     * tiebreak. The registry rejects null-name vtables at register time, so a
     * reachable vtable can only have null name if its underlying storage was
     * repurposed concurrently. With the RouterInflightGuard above that
     * shouldn't happen, but a belt-and-braces guard costs nothing on the hot
     * path and turns a hypothetical SEGV into a deterministic ordering. */
    std::ranges::sort(scored, [](const Scored& a, const Scored& b) {
        if (a.score != b.score)
            return a.score > b.score;
        if (a.vt->metadata.priority != b.vt->metadata.priority) {
            return a.vt->metadata.priority > b.vt->metadata.priority;
        }
        if (a.vt->metadata.name == nullptr)
            return false;
        if (b.vt->metadata.name == nullptr)
            return true;
        return std::strcmp(a.vt->metadata.name, b.vt->metadata.name) < 0;
    });

    return RouteResult{
        .vtable = scored.front().vt, .score = scored.front().score, .rejection_reason = {}};
}

std::vector<RouteResult> EngineRouter::route_all(const RouteRequest& req) const {
    /* commons-007: same pin window as route() — every vtable observed via
     * `snapshot_for_primitive` must outlive its dereferences in score(). */
    RouterInflightGuard inflight_guard;

    auto candidates = snapshot_for_primitive(req.primitive);
    std::vector<RouteResult> out;
    out.reserve(candidates.size());
    for (auto* vt : candidates) {
        if (vt == nullptr)
            continue;
        int s = score(*vt, req);
        out.push_back(RouteResult{.vtable = vt, .score = s, .rejection_reason = {}});
    }
    std::ranges::sort(out,
                      [](const RouteResult& a, const RouteResult& b) { return a.score > b.score; });
    return out;
}

}  // namespace rac::router
