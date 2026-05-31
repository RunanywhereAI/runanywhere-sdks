// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_hardware.dart — Hardware Profile capability surface.
// Mirrors Swift `RunAnywhere.Hardware` and
// the RN/Web `RunAnywhere.hardware.*` namespace.

import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/dart_bridge_hardware.dart';

/// Hardware profile capability surface.
///
/// Access via `RunAnywhere.hardware`.
class RunAnywhereHardware {
  RunAnywhereHardware._();
  static final RunAnywhereHardware _instance = RunAnywhereHardware._();
  static RunAnywhereHardware get shared => _instance;

  /// Aggregate generated hardware profile from commons.
  ///
  /// Mirrors Swift `try RunAnywhere.hardware.getProfile()` — throws
  /// `SDKException` when the hardware ABI is unavailable or commons returns
  /// a non-success result. No silent fallback (Swift parity).
  HardwareProfileResult getProfile() => DartBridgeHardware.getProfile();

  /// Get available accelerators as generated proto data.
  ///
  /// Mirrors Swift `RunAnywhere.hardware.getAccelerators()`.
  List<AcceleratorInfo> getAccelerators() =>
      DartBridgeHardware.getAccelerators();

  /// Set the C++ routing preference for future accelerator-aware operations.
  ///
  /// Mirrors Swift `try RunAnywhere.hardware.setAcceleratorPreference(_:) throws`.
  /// Throws [SDKException] when commons rejects the preference or the hardware
  /// ABI is unavailable.
  void setAcceleratorPreference(AccelerationPreference preference) =>
      DartBridgeHardware.setAccelerationPreference(preference);
}
