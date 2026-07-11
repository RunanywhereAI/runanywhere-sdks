/**
 * HybridWasmModule.ts
 *
 * Typed Emscripten export surface for the STT hybrid router. Mirrors the
 * commons C ABI the Swift/Kotlin bindings call:
 *   - rac_stt_hybrid_router_proto.h  (proto-byte router ABI)
 *   - rac_stt_hybrid_router.h        (create / destroy / cancel)
 *   - rac_hybrid_device_state.h      (cross-SDK host device-state vtable)
 *   - rac_hybrid_custom_filter.h     (named custom-filter callback table)
 *   - rac_plugin_entry_cloud.h       (rac_backend_cloud_register)
 *
 * EVERY symbol below is optional at the type level because the current Web
 * WASM targets do NOT export them yet (see the BUILD DELTA note). The router
 * facade checks for presence and surfaces `backendNotAvailable` with an
 * actionable message when a build is missing them — exactly how the rest of
 * the Web SDK degrades when a backend isn't linked (cf. SpeechBackendExports).
 *
 * ────────────────────────────────────────────────────────────────────────────
 * BUILD DELTA (what the WASM build needs before this runs end-to-end)
 * ────────────────────────────────────────────────────────────────────────────
 * The router + device-state + custom-filter C++ sources ALREADY compile into
 * `rac_commons` (sdk/runanywhere-commons/CMakeLists.txt:
 *   src/routing/rac_stt_hybrid_router.cpp
 *   src/routing/rac_stt_hybrid_router_proto.cpp
 *   src/routing/rac_hybrid_device_state.cpp
 *   src/routing/rac_hybrid_custom_filter.cpp)
 * and every Web WASM target links `rac_commons`. They are only DEAD-STRIPPED
 * because:
 *   (1) wasm/src/wasm_exports.cpp does NOT #include the routing headers, and
 *   (2) the symbols are NOT in any RAC_EXPORTED_FUNCTIONS list.
 *
 * To make this binding actually run, the WASM build must:
 *
 *   A. In sdk/runanywhere-web/wasm/src/wasm_exports.cpp, add:
 *        #include "rac/router/hybrid/rac_stt_hybrid_router_proto.h"
 *        #include "rac/router/hybrid/rac_stt_hybrid_router.h"
 *        #include "rac/router/hybrid/rac_hybrid_device_state.h"
 *        #include "rac/router/hybrid/rac_hybrid_custom_filter.h"
 *      so the linker keeps the symbols (KEEPALIVE / referenced TUs).
 *
 *   B. In sdk/runanywhere-web/wasm/CMakeLists.txt RAC_EXPORTED_FUNCTIONS_BASE,
 *      add the ROUTER_EXPORTS / DEVICE_STATE_EXPORTS / CUSTOM_FILTER_EXPORTS
 *      names below (these are commons-local, so they belong in the BASE list
 *      that every target inherits).
 *
 *   C. the cloud engine is its OWN engine static library (engines/cloud →
 *      `rac_backend_cloud`), NOT folded into rac_commons — exactly like
 *      rac_backend_sherpa / rac_backend_onnx / rac_backend_llamacpp. To make
 *      the ONLINE side routable in WASM the build must additionally:
 *        - link `rac_backend_cloud` into a target (the ONNX-sherpa target
 *          is the natural home — it already owns the OFFLINE sherpa STT side),
 *        - add a per-backend export list with `_rac_backend_cloud_register`
 *          + `_rac_backend_cloud_unregister` (mirrors
 *          RAC_EXPORTED_FUNCTIONS_SHERPA), appended to that target,
 *        - ensure RAC_STATIC_REGISTER_BACKEND(cloud) is folded into the
 *          static-plugin archive (the Web build already uses
 *          -DRAC_STATIC_PLUGINS=ON, the same path iOS uses).
 *
 *   D. Service creation. The router needs a `rac_stt_service_t*` for each side.
 *      Plugin SELECTION is shared commons: `rac_plugin_find_for_engine(
 *      RAC_PRIMITIVE_TRANSCRIBE, engine_name)` returns the engine's vtable
 *      pointer (0 when no plugin is registered under that engine for the
 *      primitive). Actually building the service from that vtable means
 *      dereferencing `vt->stt_ops->create` INSIDE the struct, which the Web
 *      SDK deliberately never does (it uses proto-byte ABIs + offset helpers,
 *      never raw vtable deref). So the create→wrap stays in a commons C ABI
 *      convenience export that does the selection + deref + heap-wrap in one:
 *
 *        // returns an opaque rac_stt_service_t* (as a pointer/number), or 0
 *        RAC_API rac_stt_service_t* rac_stt_hybrid_router_create_service(
 *            const char* engine_hint,      // "sherpa" | "cloud"
 *            const char* model_id_or_path, // sherpa model id; "" for cloud
 *            const char* config_json);     // cloud config JSON; NULL for sherpa
 *        RAC_API void rac_stt_hybrid_router_destroy_service(rac_stt_service_t*);
 *
 *      exported as `_rac_stt_hybrid_router_create_service` /
 *      `_rac_stt_hybrid_router_destroy_service` (both already land in commons +
 *      the WASM export list). This binding uses `rac_plugin_find_for_engine`
 *      as the routability guard before delegating create→wrap to that pair
 *      (see `HybridSttRouter.createService`).
 *
 * Until A–D land, `HybridSttRouter` constructs cleanly but
 * `supportsHybridRouter()` returns false and `setPair`/`transcribe` raise a
 * clear `backendNotAvailable` — no faked behaviour.
 */

import type { EmscriptenRunanywhereModule } from '../../../runtime/EmscriptenModule.js';

/**
 * `rac_primitive_t` value for the TRANSCRIBE (STT) primitive. Used to pin the
 * STT plugin via `rac_plugin_find_for_engine`. Mirrors the C enum
 * RAC_PRIMITIVE_TRANSCRIBE (rac/plugin/rac_plugin_entry.h).
 */
export const RAC_PRIMITIVE_TRANSCRIBE = 2;

/**
 * The hybrid-router proto-byte ABI + supporting vtable/register exports.
 * Pointers are `number` (wasm32). `*_proto` calls take heap pointers + sizes,
 * matching the proto-byte pattern every other Web adapter uses.
 */
export interface HybridWasmModule extends EmscriptenRunanywhereModule {
  // ── Router lifecycle (rac_stt_hybrid_router.h) ────────────────────────────
  /** `rac_result_t rac_stt_hybrid_router_create(rac_handle_t* out_handle)`.
   * `outHandlePtr` is a malloc'd pointer-width slot; read the handle back. */
  _rac_stt_hybrid_router_create?(outHandlePtr: number): number;
  /** `void rac_stt_hybrid_router_destroy(rac_handle_t handle)`. */
  _rac_stt_hybrid_router_destroy?(handle: number): void;
  /** `rac_result_t rac_stt_hybrid_router_cancel(rac_handle_t handle)`. */
  _rac_stt_hybrid_router_cancel?(handle: number): number;

  // ── Proto-byte router ABI (rac_stt_hybrid_router_proto.h) ─────────────────
  /** `rac_stt_hybrid_router_set_offline_service_proto(handle, service,
   *    descriptor_bytes, descriptor_size)`. Pass service=0 to clear the slot. */
  _rac_stt_hybrid_router_set_offline_service_proto?(
    handle: number,
    servicePtr: number,
    descriptorBytes: number,
    descriptorSize: number,
  ): number;
  /** Symmetric to the offline setter. */
  _rac_stt_hybrid_router_set_online_service_proto?(
    handle: number,
    servicePtr: number,
    descriptorBytes: number,
    descriptorSize: number,
  ): number;
  /** `rac_stt_hybrid_router_set_policy_proto(handle, policy_bytes, policy_size)`. */
  _rac_stt_hybrid_router_set_policy_proto?(
    handle: number,
    policyBytes: number,
    policySize: number,
  ): number;
  /** `rac_stt_hybrid_router_transcribe_proto(handle, request_bytes,
   *    request_size, out_response_bytes**, out_response_size*)`. On success
   *    *out_response_bytes is a heap allocation freed via the buffer-free
   *    export below. */
  _rac_stt_hybrid_router_transcribe_proto?(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResponseBytesPtr: number,
    outResponseSizePtr: number,
  ): number;
  /** `void rac_stt_hybrid_router_proto_buffer_free(uint8_t* response_bytes)`. */
  _rac_stt_hybrid_router_proto_buffer_free?(responseBytes: number): void;

  // ── Plugin selection (rac_plugin_entry.h) ─────────────────────────────────
  /** `const rac_engine_vtable_t* rac_plugin_find_for_engine(
   *    rac_primitive_t primitive, const char* engine_name)` — returns the
   *    engine's vtable pointer for `primitive`, or 0 when no plugin is
   *    registered under that engine name for the primitive. Used to pin the
   *    offline "sherpa" vs online "cloud" STT engine (priority order cannot
   *    distinguish two plugins that serve the same primitive). */
  _rac_plugin_find_for_engine?(
    primitive: number,
    engineNamePtr: number,
  ): number;

  // ── Service creation convenience (BUILD DELTA item D) ─────────────────────
  /** `rac_stt_service_t* rac_stt_hybrid_router_create_service(
   *    engine_hint, model_id_or_path, config_json)` — opaque ptr or 0.
   *    Internally selects the engine via `rac_plugin_find_for_engine`, then
   *    dereferences `stt_ops->create` + heap-wraps (commons does the deref so
   *    JS never touches the vtable). */
  _rac_stt_hybrid_router_create_service?(
    engineHintPtr: number,
    modelIdOrPathPtr: number,
    configJsonPtr: number,
  ): number;
  /** `void rac_stt_hybrid_router_destroy_service(rac_stt_service_t*)`. */
  _rac_stt_hybrid_router_destroy_service?(servicePtr: number): void;

  // ── Device-state vtable (rac_hybrid_device_state.h) ───────────────────────
  // Installed via a small struct the binding packs with three function-table
  // indices (is_online → 'ip', battery_percent → 'ip', is_thermal_throttled →
  // 'ip') + user_data. The Web SDK already packs the platform-adapter struct
  // the same way (offsetof helpers), so the same pattern applies. The simplest
  // ABI surface — and the one this binding targets — is a flattened helper
  // that takes the three callback table indices directly, so JS never has to
  // know the struct layout:
  /** `rac_result_t rac_hybrid_set_device_state_from_js(
   *    isOnlineFnIdx, batteryPercentFnIdx, isThermalThrottledFnIdx)`; pass all
   *    zero to restore the optimistic default. Thin commons wrapper over
   *    rac_hybrid_set_device_state that builds the ops struct internally. */
  _rac_hybrid_set_device_state_from_js?(
    isOnlineFnIdx: number,
    batteryPercentFnIdx: number,
    isThermalThrottledFnIdx: number,
  ): number;

  // ── Custom-filter table (rac_hybrid_custom_filter.h) ──────────────────────
  /** `rac_result_t rac_hybrid_register_custom_filter(name, predicate, user_data)`.
   * `predicateFnIdx` is a function-table index for a
   * `rac_bool_t (*)(const rac_hybrid_routing_context_t*, void*)`. The binding
   * reads the candidate model id from the ctx struct (char[128] at
   * offsetof(candidate_model_id)) inside the trampoline. A flattened
   * name+predicate wrapper that passes the candidate id as a C-string to the
   * JS trampoline avoids exposing the ctx struct layout: */
  _rac_hybrid_register_custom_filter_from_js?(
    namePtr: number,
    predicateFnIdx: number,
  ): number;
  /** `rac_result_t rac_hybrid_unregister_custom_filter(const char* name)`. */
  _rac_hybrid_unregister_custom_filter?(namePtr: number): number;

  // ── Cloud STT engine registration (rac_plugin_entry_cloud.h) ──────────────
  /** `rac_result_t rac_backend_cloud_register(void)` — folds the
   * "cloud" plugin into the registry so the ONLINE side is routable. */
  _rac_backend_cloud_register?(): number;
  /** `rac_result_t rac_backend_cloud_unregister(void)`. */
  _rac_backend_cloud_unregister?(): number;
}

/**
 * Exports the proto-byte router ABI requires to function at all (lifecycle +
 * the 5 proto-byte calls + buffer-free + the two service-creation helpers).
 * Used by `supportsHybridRouter()`.
 */
export const REQUIRED_HYBRID_ROUTER_EXPORTS = [
  '_rac_stt_hybrid_router_create',
  '_rac_stt_hybrid_router_destroy',
  '_rac_stt_hybrid_router_set_offline_service_proto',
  '_rac_stt_hybrid_router_set_online_service_proto',
  '_rac_stt_hybrid_router_set_policy_proto',
  '_rac_stt_hybrid_router_transcribe_proto',
  '_rac_stt_hybrid_router_proto_buffer_free',
  '_rac_stt_hybrid_router_create_service',
  '_rac_stt_hybrid_router_destroy_service',
] as const;

export function missingHybridRouterExports(
  module: HybridWasmModule | null | undefined,
): string[] {
  if (!module) return [...REQUIRED_HYBRID_ROUTER_EXPORTS];
  const record = module as unknown as Record<string, unknown>;
  return REQUIRED_HYBRID_ROUTER_EXPORTS.filter(
    (name) => typeof record[name] !== 'function',
  );
}

export function hasHybridRouterExports(
  module: HybridWasmModule | null | undefined,
): boolean {
  return missingHybridRouterExports(module).length === 0;
}

/** Actionable message pointing at the WASM build delta when exports are absent. */
export function hybridRouterRequirementMessage(missing: string[]): string {
  const list = missing.length > 0 ? missing.join(', ') : 'none';
  return (
    `Loaded RACommons WASM is missing hybrid STT router exports: ${list}. ` +
    'The router C++ already compiles into rac_commons; rebuild the Web WASM ' +
    'with the routing headers #included in wasm_exports.cpp and the ' +
    'rac_stt_hybrid_router_* / rac_hybrid_* symbols added to ' +
    'RAC_EXPORTED_FUNCTIONS (see HybridWasmModule.ts BUILD DELTA). For the ' +
    'online cloud side, also link rac_backend_cloud and export ' +
    'rac_backend_cloud_register.'
  );
}
