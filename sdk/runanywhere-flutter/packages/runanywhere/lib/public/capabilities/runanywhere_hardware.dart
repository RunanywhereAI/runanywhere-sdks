// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_hardware.dart — Hardware Profile capability surface
// (canonical §14 namespace). Mirrors Swift `RunAnywhere.Hardware` and
// the RN/Web `RunAnywhere.hardware.*` namespace.

import 'dart:async' show Future;

import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/dart_bridge_hardware.dart';

/// Hardware profile capability surface.
///
/// Access via `RunAnywhereSDK.instance.hardware`.
class RunAnywhereHardware {
  RunAnywhereHardware._();
  static final RunAnywhereHardware _instance = RunAnywhereHardware._();
  static RunAnywhereHardware get shared => _instance;

  /// Aggregate generated hardware profile from commons.
  Future<HardwareProfileResult> getProfile() async {
    final nativeProfile = DartBridgeHardware.getProfile();
    return nativeProfile ?? HardwareProfileResult();
  }

  /// Set the C++ routing preference for future accelerator-aware operations.
  ///
  /// Returns false when the bundled native library does not expose the hardware
  /// ABI yet.
  bool setAcceleratorPreference(AcceleratorPreference preference) =>
      DartBridgeHardware.setAcceleratorPreference(preference);
}
