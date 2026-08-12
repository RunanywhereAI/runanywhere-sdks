// SPDX-License-Identifier: Apache-2.0
//
// hybrid_device_state.dart — public contract + installer for the cross-SDK host
// device-state vtable (rac/router/hybrid/rac_hybrid_device_state.h). The hybrid
// router consults this vtable on every transcribe() to evaluate the NETWORK /
// Battery hard filters; it is NOT passed in the per-request routing context.
//
// All routing LOGIC stays in commons — this file only installs three host
// callbacks (is_online / battery_percent / is_thermal_throttled). Mirrors the
// Kotlin DeviceStateProvider + RACRouter.setDeviceStateProvider and the Swift
// HybridDeviceStateProvider + HybridDeviceState installer.

import 'package:runanywhere/native/dart_bridge_hybrid_stt.dart';

/// Host-supplied source of the device state the hybrid router needs.
///
/// Implementations MUST be thread-safe / reentrant: commons may invoke these
/// from multiple request threads concurrently (see the @warning in
/// rac_hybrid_device_state.h).
abstract class HybridDeviceStateProvider {
  /// True iff the host has a usable internet connection right now.
  bool isOnline();

  /// Battery level in `[0, 100]`; return 100 on hosts without a battery.
  int batteryPercent();

  /// True when the device is currently thermally throttled.
  bool isThermalThrottled();
}

/// Installs / clears the device-state vtable in commons.
///
/// Exactly one provider is active process-wide (the C ABI holds a single
/// vtable). Re-registering replaces the previous provider. Access via
/// `RunAnywhere.hybrid.setDeviceStateProvider(...)`.
class HybridDeviceState {
  HybridDeviceState._();

  /// Shared installer.
  static final HybridDeviceState instance = HybridDeviceState._();

  HybridDeviceStateProvider? _provider;

  /// Register [provider] as the host device-state source the router consults on
  /// every transcribe. Pass `null` to unregister and fall back to the commons
  /// optimistic default (always-online, 100% battery, not-throttled).
  ///
  /// Returns true when the native vtable swap succeeded.
  bool setProvider(HybridDeviceStateProvider? provider) {
    if (provider == null) {
      return clear();
    }
    _provider = provider;
    final rc = DartBridgeHybridStt.instance.setDeviceStateProvider((
      isOnline: provider.isOnline,
      batteryPercent: provider.batteryPercent,
      isThermalThrottled: provider.isThermalThrottled,
    ));
    return rc == 0;
  }

  /// Detach the host provider and restore the commons default vtable. Returns
  /// true when the native call succeeded.
  bool clear() {
    _provider = null;
    return DartBridgeHybridStt.instance.clearDeviceStateProvider() == 0;
  }

  /// The currently-installed provider, or null when the commons default is
  /// active.
  HybridDeviceStateProvider? get provider => _provider;
}
