/**
 * @file rac_route.cpp
 * @brief Implementation of the C ABI route() wrapper.
 *
 * GAP 04 Phase 12.
 */

#include "rac/router/rac_route.h"
#include "rac/router/rac_engine_router.h"
#include "rac/router/rac_hardware_profile.h"

extern "C" {

rac_result_t rac_plugin_route(rac_primitive_t              primitive,
                              uint32_t                     format,
                              const rac_routing_hints_t*   hints,
                              const rac_engine_vtable_t**  out_vtable) {
    if (out_vtable == nullptr) return RAC_ERROR_NULL_POINTER;
    *out_vtable = nullptr;

    rac::router::RouteRequest req;
    req.primitive = primitive;
    req.format    = format;
    if (hints != nullptr) {
        req.estimated_memory_bytes = hints->estimated_memory_bytes;
        req.preferred_runtime      = hints->preferred_runtime;
        req.no_fallback            = (hints->no_fallback != 0);
        if (hints->preferred_engine_name != nullptr) {
            req.pinned_engine = hints->preferred_engine_name;
        }
    }

    rac::router::EngineRouter router(rac::router::HardwareProfile::cached());
    auto result = router.route(req);
    if (result.vtable == nullptr) {
        return RAC_ERROR_NOT_FOUND;
    }
    *out_vtable = result.vtable;
    return RAC_SUCCESS;
}

}  // extern "C"
