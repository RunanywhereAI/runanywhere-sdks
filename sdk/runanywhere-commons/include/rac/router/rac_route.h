/**
 * @file rac_route.h
 * @brief C ABI wrapper around rac::router::EngineRouter.
 *
 * GAP 04 Phase 12 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 *
 * Frontends written in C, Swift, Kotlin, etc. call `rac_plugin_route()` to
 * pick the best plugin for a primitive without instantiating the C++ router
 * class directly. The wrapper internally uses `HardwareProfile::cached()` so
 * the per-host probe runs once per process.
 *
 * v3.0.0: this is now the ONLY routing API. The legacy `rac_service_create()`
 * / `service_registry.cpp` path was removed in Phase C1. All commons consumers
 * (rac_llm_create, rac_stt_create, rac_tts_create, rac_vlm_create,
 *  rac_embeddings_create, rac_diffusion_create, vad_component.load_model)
 * go through `rac_plugin_route(primitive, format, hints, &vt)` followed by
 * `vt->ops->create(model_id, config_json, &impl)`.
 */

#ifndef RAC_ROUTER_ROUTE_H
#define RAC_ROUTER_ROUTE_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_routing_hints.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Pick the best registered plugin for `primitive`, applying caller hints.
 *
 * @param primitive   What the caller wants to do (e.g. RAC_PRIMITIVE_GENERATE_TEXT).
 * @param format      Optional model format (proto enum value cast to uint32_t),
 *                    or 0 for "no format hint".
 * @param hints       Optional routing hints, or NULL for "no hints".
 * @param out_vtable  On success, receives the chosen plugin's vtable pointer
 *                    (registry-owned, valid until the plugin is unregistered).
 *
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER, RAC_ERROR_NOT_FOUND
 *         (no eligible plugin / pinned name unavailable with no_fallback=1),
 *         or RAC_ERROR_CAPABILITY_NOT_FOUND (registry empty).
 *
 * Thread-safe. The first call also triggers HardwareProfile::detect();
 * subsequent calls reuse the memoized profile.
 */
rac_result_t rac_plugin_route(rac_primitive_t              primitive,
                              uint32_t                     format,
                              const rac_routing_hints_t*   hints,
                              const rac_engine_vtable_t**  out_vtable);

#ifdef __cplusplus
}
#endif

#endif  /* RAC_ROUTER_ROUTE_H */
