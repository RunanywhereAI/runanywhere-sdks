//
//  HybridDeviceState.swift
//  RunAnywhere
//
//  Swift binding for the cross-SDK host device-state vtable
//  (rac_hybrid_device_state.h). The hybrid router consults this vtable on
//  every transcribe() to evaluate the NETWORK / Battery hard filters; it is
//  NOT passed in the per-request routing context.
//
//  All routing LOGIC stays in commons — this file only installs three host
//  callbacks (is_online / battery_percent / is_thermal_throttled) and owns the
//  lifetime of the boxed provider so commons can call back into Swift safely.
//
//  Mirrors the Kotlin DeviceStateProvider + RACRouter.setDeviceStateProvider
//  vtable wiring, using the SDK's standard Swift↔C callback-boxing convention
//  (Unmanaged.passRetained → user_data → fromOpaque, OSAllocatedUnfairLock for
//  the install slot, per AGENTS.md NSLock is forbidden).
//

import CRACommons
import Foundation
import os

// MARK: - Provider contract

/// Host-supplied source of the device state the hybrid router needs.
///
/// Implementations MUST be thread-safe / reentrant: commons may invoke these
/// from multiple request threads concurrently (see the @warning in
/// rac_hybrid_device_state.h).
///
/// Class-bound by design: providers are long-lived stateful hosts (battery /
/// network monitors) retained once in the C user_data box; reference semantics
/// match the Kotlin DeviceStateProvider interface.
public protocol HybridDeviceStateProvider: AnyObject, Sendable {  // swiftlint:disable:this avoid_any_object
    /// True iff the host has a usable internet connection right now.
    func isOnline() -> Bool
    /// Battery level in `[0, 100]`; return 100 on hosts without a battery.
    func batteryPercent() -> Int32
    /// True when the device is currently thermally throttled.
    func isThermalThrottled() -> Bool
}

// MARK: - Vtable installer

/// Installs / clears the device-state vtable in commons.
///
/// Exactly one provider is active process-wide (the C ABI holds a single
/// vtable). Re-registering replaces the previous provider; the old box is
/// released only AFTER `rac_hybrid_set_device_state(nil)`-style detach so no
/// request thread is mid-callback against freed storage.
public enum HybridDeviceState {

    private static let logger = SDKLogger(category: "Hybrid.DeviceState")

    /// Retained box for the currently-installed provider. `nil` when the
    /// optimistic commons default (always-online, 100%, not-throttled) is
    /// active. Guarded by `OSAllocatedUnfairLock` per AGENTS.md.
    private static let installed =
        OSAllocatedUnfairLock<Unmanaged<ProviderBox>?>(initialState: nil)

    /// Register `provider` as the host device-state source the router consults
    /// on every transcribe. Pass `nil` to unregister and fall back to the
    /// commons optimistic default.
    ///
    /// Thread-safe; the native vtable swap is atomic.
    @discardableResult
    public static func setProvider(_ provider: HybridDeviceStateProvider?) -> Bool {
        guard let provider else {
            return clear()
        }

        let box = ProviderBox(provider)
        let retained = Unmanaged.passRetained(box)

        var ops = rac_hybrid_device_state_ops_t()
        ops.is_online = { userData in
            ProviderBox.unwrap(userData)?.provider.isOnline() ?? true
        }
        ops.battery_percent = { userData in
            ProviderBox.unwrap(userData)?.provider.batteryPercent() ?? 100
        }
        ops.is_thermal_throttled = { userData in
            ProviderBox.unwrap(userData)?.provider.isThermalThrottled() ?? false
        }
        ops.user_data = retained.toOpaque()

        let rc = rac_hybrid_set_device_state(&ops)
        guard rc == RAC_SUCCESS else {
            // Install failed — drop the retain we optimistically took so the
            // box doesn't leak.
            retained.release()
            logger.error("rac_hybrid_set_device_state failed: rc=\(rc)")
            return false
        }

        // Swap in the new box and retire the previous one. Commons has already
        // copied the ops struct (including the new user_data) into its own
        // storage, so the old box is no longer reachable from a fresh callback;
        // release it.
        let previous: Unmanaged<ProviderBox>? = installed.withLock { slot in
            let old = slot
            slot = retained
            return old
        }
        previous?.release()
        return true
    }

    /// Detach the host provider and restore the commons default vtable.
    @discardableResult
    public static func clear() -> Bool {
        let rc = rac_hybrid_set_device_state(nil)
        // Per the rac_hybrid_device_state.h contract, the nil-set guarantees no
        // request thread is mid-callback once it returns, so the previously
        // installed box is safe to release here.
        let previous: Unmanaged<ProviderBox>? = installed.withLock { slot in
            let old = slot
            slot = nil
            return old
        }
        previous?.release()
        if rc != RAC_SUCCESS {
            logger.error("rac_hybrid_set_device_state(nil) failed: rc=\(rc)")
            return false
        }
        return true
    }

    /// Heap box carrying the provider across the C `user_data` pointer. A
    /// dedicated class (rather than passing the provider directly) keeps the
    /// `Unmanaged` retain/release bookkeeping in one place.
    ///
    /// `@unchecked Sendable`: the box is immutable and wraps an already-Sendable
    /// `HybridDeviceStateProvider`, so storing its `Unmanaged` handle in the
    /// `OSAllocatedUnfairLock` slot is safe across isolation domains.
    private final class ProviderBox: @unchecked Sendable {
        let provider: HybridDeviceStateProvider
        init(_ provider: HybridDeviceStateProvider) { self.provider = provider }

        /// Resolve the box from a C `user_data` pointer without consuming a
        /// retain (the callback borrows; ownership stays with `installed`).
        static func unwrap(_ userData: UnsafeMutableRawPointer?) -> ProviderBox? {
            guard let userData else { return nil }
            return Unmanaged<ProviderBox>.fromOpaque(userData).takeUnretainedValue()
        }
    }
}
