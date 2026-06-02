/**
 * HybridDeviceState.ts
 *
 * React Native binding for the cross-SDK host device-state vtable
 * (rac_hybrid_device_state.h). The hybrid router consults this vtable on every
 * transcribe to evaluate the NETWORK / Battery hard filters.
 *
 * RN cannot call JS synchronously from the commons routing thread (unlike the
 * Kotlin JNI `CallBooleanMethod` / Swift `@convention(c)` paths, which install
 * live callbacks). Instead, the host pushes a device-state SNAPSHOT to native via
 * `hybridSetDeviceState`; the installed native vtable returns those cached values
 * to commons. All routing LOGIC still lives in commons — this only feeds it the
 * values. Push a fresh snapshot before each transcribe and whenever connectivity
 * / battery changes.
 *
 * Mirrors the Kotlin `DeviceStateProvider` + `RACRouter.setDeviceStateProvider`
 * and the Swift `HybridDeviceState` API shape.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKException } from '../../../Foundation/Errors/SDKException';

/**
 * Host-supplied source of the device state the hybrid router needs. Mirror of
 * the Kotlin/Swift provider contract; methods are synchronous because the
 * binding reads a snapshot from them and pushes it to native.
 */
export interface HybridDeviceStateProvider {
  /** True iff the host has a usable internet connection right now. */
  isOnline(): boolean;
  /** Battery level in [0, 100]; return 100 on hosts without a battery. */
  batteryPercent(): number;
  /** True when the device is currently thermally throttled. */
  isThermalThrottled(): boolean;
}

/**
 * Installs / refreshes / clears the cached device-state snapshot that backs the
 * commons device-state vtable. Exactly one snapshot is active process-wide.
 */
export const HybridDeviceState = {
  /**
   * Push a one-off device-state snapshot to native. Installs the commons vtable
   * (once) and updates the cached values it returns to the router.
   */
  async setSnapshot(snapshot: {
    isOnline: boolean;
    batteryPercent: number;
    thermalThrottled: boolean;
  }): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      throw SDKException.nativeModuleUnavailable();
    }
    return requireNativeModule().hybridSetDeviceState(
      snapshot.isOnline,
      snapshot.batteryPercent,
      snapshot.thermalThrottled
    );
  },

  /**
   * Read a snapshot from `provider` and push it to native. Call this before
   * transcribe and whenever device state changes. Pass `null` to detach the
   * vtable and restore the commons optimistic default.
   */
  async setProvider(provider: HybridDeviceStateProvider | null): Promise<boolean> {
    if (provider == null) {
      return this.clear();
    }
    return this.setSnapshot({
      isOnline: provider.isOnline(),
      batteryPercent: provider.batteryPercent(),
      thermalThrottled: provider.isThermalThrottled(),
    });
  },

  /**
   * Detach the host device-state vtable and restore the commons optimistic
   * default (always-online, 100% battery, not-throttled).
   */
  async clear(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    return requireNativeModule().hybridClearDeviceState();
  },
};
