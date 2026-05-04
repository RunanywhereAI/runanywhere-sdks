/**
 * @file rac_engine_router.h
 * @brief Hardware-aware scorer that picks the best engine plugin for a primitive.
 *
 * GAP 04 Phase 10 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 *
 * The router consumes the global plugin registry (populated via GAP 02 + 03)
 * and a `HardwareProfile`, then scores every plugin that serves the
 * requested primitive. The highest-scoring plugin wins; ties break
 * deterministically (priority desc, then metadata.name asc) so the same
 * RouteRequest always returns the same plugin in the same process.
 *
 * Layered on top of `rac_plugin_find` (which only knows priority); callers
 * who don't need scoring continue to call `rac_plugin_find` directly. The
 * routing-aware C ABI wrapper `rac_plugin_route` (Phase 12) lets non-C++
 * callers use the router without instantiating the class manually.
 */

#ifndef RAC_ROUTER_ENGINE_ROUTER_H
#define RAC_ROUTER_ENGINE_ROUTER_H

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_hardware_profile.h"

namespace rac {
namespace router {

/**
 * @brief Inputs to a single routing decision.
 *
 * `format` is a `uint32_t` rather than the proto-generated enum so this
 * header doesn't pull in the IDL — frontends pass the proto enum value cast
 * to int. 0 = no format hint.
 */
struct RouteRequest {
    rac_primitive_t   primitive            = RAC_PRIMITIVE_UNSPECIFIED;
    uint32_t          format               = 0;          /* runanywhere.v1.ModelFormat or 0 */
    std::size_t       estimated_memory_bytes = 0;
    std::string_view  pinned_engine        = {};         /* hard pin by metadata.name */
    rac_runtime_id_t  preferred_runtime    = RAC_RUNTIME_UNSPECIFIED;
    bool              no_fallback          = false;      /* honored only when pinned_engine set */
};

/**
 * @brief Outcome of a routing decision.
 */
struct RouteResult {
    /** The chosen plugin, or `nullptr` when no plugin satisfied the request. */
    const rac_engine_vtable_t* vtable = nullptr;

    /** Total score of the chosen plugin. Negative when nothing was selected. */
    int score = -1;

    /** Human-readable rejection reason when `vtable == nullptr`. Empty on success. */
    std::string rejection_reason;
};

/**
 * @brief Stateless scorer over the global plugin registry.
 *
 * Construct once per call site (or once per process) and re-use. Thread-safe;
 * each `route()` call snapshots the registry under its lock, then scores
 * outside the lock so concurrent registrations don't block routing.
 */
class EngineRouter {
public:
    explicit EngineRouter(const HardwareProfile& profile);

    /** Pick the single best plugin. */
    RouteResult route(const RouteRequest& req) const;

    /** Return every plugin that COULD serve the request, descending by score.
     *  Useful for debugging + the C ABI introspection wrapper. */
    std::vector<RouteResult> route_all(const RouteRequest& req) const;

private:
    /** Score a single plugin against `req`. Negative = ineligible (hard reject). */
    int score(const rac_engine_vtable_t& vt, const RouteRequest& req) const;

    /** True iff the vtable serves this primitive (slot is non-NULL). */
    bool serves(const rac_engine_vtable_t& vt, rac_primitive_t p) const;

    const HardwareProfile& profile_;
};

}  // namespace router
}  // namespace rac

#endif  /* RAC_ROUTER_ENGINE_ROUTER_H */
