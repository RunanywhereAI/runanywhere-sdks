/**
 * @file rac_route.cpp
 * @brief Implementation of the C ABI route() wrapper.
 *
 * Distinguishes runtime-unavailable rejections from generic "no plugin"
 * rejections via `RAC_ERROR_RUNTIME_UNAVAILABLE`.
 */

#include "rac/router/rac_route.h"

#include <cstring>
#include <string>

#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/router/rac_engine_router.h"
#include "rac/router/rac_hardware_profile.h"

namespace {

/* Marker substring emitted by `EngineRouter::route` when every candidate was
 * rejected purely because their declared L1 runtimes are not registered.
 * Kept as a substring rather than a regex so the scoring/rejection plumbing
 * stays in pure C++ with no extra dependencies. */
constexpr const char* kRuntimeUnavailableMarker = "no registered runtime satisfies";

bool is_runtime_unavailable(const std::string& reason) {
    return reason.find(kRuntimeUnavailableMarker) != std::string::npos;
}

/* Pre-unification commons pinned VLM loads to "llamacpp_vlm"; the unified
 * llama.cpp plugin registers as "llamacpp". Normalize so routing succeeds on
 * both old and new binaries. */
const char* normalize_legacy_engine_pin(const char* pinned_engine) {
    if (pinned_engine != nullptr && std::strcmp(pinned_engine, "llamacpp_vlm") == 0) {
        return "llamacpp";
    }
    return pinned_engine;
}

}  // namespace

extern "C" {

rac_result_t rac_plugin_route(rac_primitive_t primitive, uint32_t format,
                              const rac_routing_hints_t* hints,
                              const rac_engine_vtable_t** out_vtable) {
    if (out_vtable == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out_vtable = nullptr;

    rac::router::RouteRequest req;
    req.primitive = primitive;
    req.format = format;
    if (hints != nullptr) {
        req.estimated_memory_bytes = static_cast<std::size_t>(hints->estimated_memory_bytes);
        req.preferred_runtime = static_cast<rac_runtime_id_t>(hints->preferred_runtime);
        req.no_fallback = (hints->no_fallback != 0);
        if (hints->preferred_engine_name != nullptr) {
            req.pinned_engine = normalize_legacy_engine_pin(hints->preferred_engine_name);
        }
    }

    rac::router::EngineRouter router(rac::router::HardwareProfile::cached());
    auto result = router.route(req);
    if (result.vtable == nullptr) {
        const rac_result_t rc = is_runtime_unavailable(result.rejection_reason)
                                    ? RAC_ERROR_RUNTIME_UNAVAILABLE
                                    : RAC_ERROR_NOT_FOUND;
        rac::events::publish_route_failed(primitive, rc, result.rejection_reason.c_str());
        return rc;
    }
    *out_vtable = result.vtable;
    rac::events::publish_route_selected(primitive, result.vtable, "engine_router");
    return RAC_SUCCESS;
}

}  // extern "C"
