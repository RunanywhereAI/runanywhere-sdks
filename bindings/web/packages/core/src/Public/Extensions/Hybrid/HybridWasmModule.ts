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
 * Symbols remain optional at the type level because a host may load an older
 * artifact or a capability-specific WASM that does not contain the hybrid
 * exports. Current Web build targets export the router ABI from
 * `RAC_EXPORTED_FUNCTIONS_BASE`; the ONNX-sherpa and llama.cpp targets also
 * export the cloud registration ABI. The router checks at runtime and reports
 * `backendNotAvailable` when the loaded artifact is stale or incomplete.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * BUILD STATUS
 * ────────────────────────────────────────────────────────────────────────────
 * The router, device-state, and custom-filter headers are included by
 * `wasm/src/wasm_exports.cpp`; their exports, including the opaque service
 * creation helpers, are listed in `RAC_EXPORTED_FUNCTIONS_BASE`. The cloud
 * register/unregister and provider-registry exports are appended to the
 * ONNX-sherpa and llama.cpp targets through `RAC_EXPORTED_FUNCTIONS_CLOUD`.
 * `_rac_plugin_find_for_engine` is also exported from the base list so the
 * binding can verify that its named STT engine is routable before service
 * creation. Rebuild WASM artifacts after changing any of these lists.
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

  // ── Service creation convenience ──────────────────────────────────────────
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

/** Actionable message for an artifact missing the current hybrid export set. */
export function hybridRouterRequirementMessage(missing: string[]): string {
  const list = missing.length > 0 ? missing.join(', ') : 'none';
  return (
    `Loaded RACommons WASM is missing hybrid STT router exports: ${list}. ` +
    'Rebuild the Web WASM with the current wasm/CMakeLists.txt export lists. ' +
    'For cloud routing, load the ONNX-sherpa or llama.cpp artifact that also ' +
    'exports rac_backend_cloud_register.'
  );
}
