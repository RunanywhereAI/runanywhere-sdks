/**
 * HybridDeviceState.ts
 *
 * Web binding for the cross-SDK host device-state vtable
 * (rac_hybrid_device_state.h) and the named custom-filter callback table
 * (rac_hybrid_custom_filter.h). Mirrors Swift's `HybridDeviceState.swift` +
 * `HybridCustomFilter.swift` and Kotlin's `DeviceStateProvider` +
 * `CustomFilterPredicate` wiring.
 *
 * All routing LOGIC stays in commons — these helpers only install host
 * callbacks (is_online / battery_percent / is_thermal_throttled) and register
 * named predicates so commons can resolve + invoke them during candidate
 * filtering. The host never pre-filters or toggles router slots.
 *
 * Callbacks cross the WASM boundary as function-table indices
 * (Module.addFunction), exactly like the download/HTTP progress callbacks. The
 * binding targets the flattened `*_from_js` commons wrappers (see
 * HybridWasmModule.ts) so JS never has to know the C struct / ctx layout. When
 * those exports are absent (current Web WASM builds), registration is a
 * graceful no-op returning false — the router still works against the commons
 * optimistic default (always-online, 100%, not-throttled).
 */

import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { RAC_OK } from '../../../Foundation/RACErrors.js';
import {
  getModuleForCapability,
} from '../../../runtime/EmscriptenModule.js';
import type { HybridWasmModule } from './HybridWasmModule.js';

const logger = new SDKLogger('Hybrid.DeviceState');

/**
 * Host-supplied source of the device state the hybrid router needs.
 * Implementations MUST be reentrant: commons may invoke these from request
 * threads. Mirrors Swift's `HybridDeviceStateProvider` /
 * Kotlin's `DeviceStateProvider`.
 */
export interface HybridDeviceStateProvider {
  /** True iff the host has a usable internet connection right now. */
  isOnline(): boolean;
  /** Battery level in [0, 100]; return 100 on hosts without a battery. */
  batteryPercent(): number;
  /** True when the device is currently thermally throttled. */
  isThermalThrottled(): boolean;
}

/** Default browser-shaped provider built from `navigator` facts. `navigator`
 * exposes no battery synchronously, so battery is reported as 100 and thermal
 * as false — matching the commons optimistic default but tracking real
 * online/offline transitions via `navigator.onLine`. */
export function browserDeviceStateProvider(): HybridDeviceStateProvider {
  return {
    isOnline: () =>
      typeof navigator !== 'undefined' && typeof navigator.onLine === 'boolean'
        ? navigator.onLine
        : true,
    batteryPercent: () => 100,
    isThermalThrottled: () => false,
  };
}

function hybridModule(): HybridWasmModule | null {
  return (getModuleForCapability('stt') ??
    getModuleForCapability('commons')) as HybridWasmModule | null;
}

// ── Device-state vtable installer ──────────────────────────────────────────

let installedDeviceStatePtrs: number[] = [];

/** Register `provider` as the host device-state source the router consults on
 * every transcribe. Pass `null` to unregister and fall back to the commons
 * optimistic default. Returns true when the native vtable was installed. */
export function setHybridDeviceStateProvider(
  provider: HybridDeviceStateProvider | null,
): boolean {
  const mod = hybridModule();
  if (!mod || typeof mod.addFunction !== 'function' || typeof mod.removeFunction !== 'function') {
    logger.warning('module missing addFunction/removeFunction; cannot install device-state vtable');
    return false;
  }
  const setFn = mod._rac_hybrid_set_device_state_from_js;
  if (typeof setFn !== 'function') {
    logger.warning(
      'WASM module does not export _rac_hybrid_set_device_state_from_js; ' +
        'device-state filters use the commons optimistic default. See ' +
        'HybridWasmModule.ts BUILD DELTA.',
    );
    return false;
  }

  // Retire any previously installed callbacks AFTER swapping the vtable so no
  // request thread is mid-callback against a freed table slot.
  const previousPtrs = installedDeviceStatePtrs;
  installedDeviceStatePtrs = [];

  if (!provider) {
    setFn(0, 0, 0); // restore default
    for (const ptr of previousPtrs) mod.removeFunction(ptr);
    return true;
  }

  // is_online → 'ip' (returns rac_bool_t/i32, takes user_data pointer);
  // battery_percent → 'ip' (returns i32); is_thermal_throttled → 'ip'.
  const isOnlinePtr = mod.addFunction(() => (provider.isOnline() ? 1 : 0), 'ip');
  const batteryPtr = mod.addFunction(() => provider.batteryPercent() | 0, 'ip');
  const thermalPtr = mod.addFunction(() => (provider.isThermalThrottled() ? 1 : 0), 'ip');

  const rc = setFn(isOnlinePtr, batteryPtr, thermalPtr);
  if (rc !== RAC_OK) {
    mod.removeFunction(isOnlinePtr);
    mod.removeFunction(batteryPtr);
    mod.removeFunction(thermalPtr);
    logger.error(`rac_hybrid_set_device_state_from_js failed: rc=${rc}`);
    return false;
  }
  installedDeviceStatePtrs = [isOnlinePtr, batteryPtr, thermalPtr];
  for (const ptr of previousPtrs) mod.removeFunction(ptr);
  return true;
}

// ── Custom-filter table ────────────────────────────────────────────────────

/** name → function-table index, so each predicate's table slot can be retired
 * on unregister. */
const customFilterPtrs = new Map<string, number>();

/** Register (or replace) a named custom-filter predicate with commons. The
 * predicate is invoked by commons (NOT JS) once per candidate during filtering;
 * it receives the candidate model id. Returns true on success. */
export function registerHybridCustomFilter(
  name: string,
  check: (modelId: string) => boolean,
): boolean {
  if (!name) {
    logger.error('custom-filter name must be non-empty');
    return false;
  }
  const mod = hybridModule();
  if (!mod || typeof mod.addFunction !== 'function' || typeof mod.removeFunction !== 'function') {
    return false;
  }
  const registerFn = mod._rac_hybrid_register_custom_filter_from_js;
  if (typeof registerFn !== 'function' || typeof mod.UTF8ToString !== 'function') {
    logger.warning(
      'WASM module does not export _rac_hybrid_register_custom_filter_from_js; ' +
        'custom filters are ignored. See HybridWasmModule.ts BUILD DELTA.',
    );
    return false;
  }

  // Trampoline: commons passes the candidate model id as a C-string (the
  // flattened from_js wrapper extracts ctx.candidate_model_id), we dispatch to
  // the JS predicate and map the boolean to rac_bool_t. Signature 'ip': returns
  // rac_bool_t/i32, takes the model-id char* pointer.
  const predicatePtr = mod.addFunction((modelIdPtr: number) => {
    const modelId = modelIdPtr ? mod.UTF8ToString!(modelIdPtr) : '';
    return check(modelId) ? 1 : 0;
  }, 'ip');

  const namePtr = allocCString(mod, name);
  try {
    const rc = registerFn(namePtr, predicatePtr);
    if (rc !== RAC_OK) {
      mod.removeFunction(predicatePtr);
      logger.error(`rac_hybrid_register_custom_filter_from_js('${name}') failed: rc=${rc}`);
      return false;
    }
  } finally {
    mod._free?.(namePtr);
  }

  // Replace any prior predicate registered under the same name + retire its slot.
  const previous = customFilterPtrs.get(name);
  if (previous !== undefined) mod.removeFunction(previous);
  customFilterPtrs.set(name, predicatePtr);
  return true;
}

/** Remove a named custom-filter predicate. No-op when not registered. */
export function unregisterHybridCustomFilter(name: string): boolean {
  if (!name) return false;
  const mod = hybridModule();
  if (!mod) return false;
  const unregisterFn = mod._rac_hybrid_unregister_custom_filter;
  if (typeof unregisterFn === 'function') {
    const namePtr = allocCString(mod, name);
    try {
      unregisterFn(namePtr);
    } finally {
      mod._free?.(namePtr);
    }
  }
  const ptr = customFilterPtrs.get(name);
  if (ptr !== undefined && typeof mod.removeFunction === 'function') {
    mod.removeFunction(ptr);
  }
  customFilterPtrs.delete(name);
  return true;
}

function allocCString(mod: HybridWasmModule, value: string): number {
  const len = mod.lengthBytesUTF8!(value) + 1;
  const ptr = mod._malloc!(len);
  mod.stringToUTF8!(value, ptr, len);
  return ptr;
}
