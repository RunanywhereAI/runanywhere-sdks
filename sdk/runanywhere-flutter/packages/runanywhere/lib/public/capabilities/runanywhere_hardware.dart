// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_hardware.dart — Hardware Profile capability surface
// (canonical §14 namespace). Mirrors Swift `RunAnywhere.Hardware` and
// the RN/Web `RunAnywhere.hardware.*` namespace.

import 'dart:async' show Future;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'package:runanywhere/core/types/npu_chip.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/dart_bridge_hardware.dart';

/// Hardware profile capability surface.
///
/// Access via `RunAnywhereSDK.instance.hardware`.
class RunAnywhereHardware {
  RunAnywhereHardware._();
  static final RunAnywhereHardware _instance = RunAnywhereHardware._();
  static RunAnywhereHardware get shared => _instance;

  static const _channel = MethodChannel('runanywhere');

  /// Aggregate device profile (chip, NPU presence, recommended accel).
  Future<HardwareProfileResult> getProfile() async {
    final nativeProfile = DartBridgeHardware.getProfile();
    if (nativeProfile != null) return nativeProfile;

    final chip = await _detectChip();
    final hasAccelerator = Platform.isIOS || Platform.isMacOS || chip != null;
    final accel = await _detectAccelerationMode();
    return HardwareProfileResult(
      profile: HardwareProfile(
        chip: chip?.displayName ?? _genericChipLabel(),
        hasNeuralEngine: hasAccelerator,
        accelerationMode: accel,
        platform: _platformLabel(),
      ),
      accelerators: [
        AcceleratorInfo(
          name: accel,
          type: accel == 'ane'
              ? AcceleratorPreference.ACCELERATOR_PREFERENCE_ANE
              : accel == 'gpu'
                  ? AcceleratorPreference.ACCELERATOR_PREFERENCE_GPU
                  : AcceleratorPreference.ACCELERATOR_PREFERENCE_CPU,
          available: true,
        ),
      ],
    );
  }

  /// Detect the device's NPU chipset for Genie model compatibility.
  ///
  /// Returns the chip identifier (e.g. "8elite-gen5") or null if the
  /// device is not Android or doesn't expose a supported Qualcomm SoC.
  Future<String?> getChip() async {
    final chip = await _detectChip();
    return chip?.identifier;
  }

  /// Structured chip enum (NPU types). Returns null for non-Android
  /// targets or unsupported SoCs.
  Future<NPUChip?> getChipEnum() async => _detectChip();

  /// True when the device exposes a neural engine / NPU.
  Future<bool> get hasNeuralEngine async {
    if (Platform.isIOS || Platform.isMacOS) return true;
    return (await _detectChip()) != null;
  }

  /// Recommended acceleration mode (`"ane"`, `"gpu"`, `"cpu"`).
  Future<String> get accelerationMode async => _detectAccelerationMode();

  /// Set the C++ routing preference for future accelerator-aware operations.
  ///
  /// Returns false when the bundled native library does not expose the hardware
  /// ABI yet.
  bool setAcceleratorPreference(AcceleratorPreference preference) =>
      DartBridgeHardware.setAcceleratorPreference(preference);

  // -- internal helpers --------------------------------------------------

  Future<NPUChip?> _detectChip() async {
    if (!Platform.isAndroid) return null;
    try {
      final socModel = await _channel.invokeMethod<String>('getSocModel');
      if (socModel == null || socModel.isEmpty) return null;
      return NPUChip.fromSocModel(socModel);
    } on PlatformException {
      return null;
    }
  }

  Future<String> _detectAccelerationMode() async {
    if (Platform.isIOS || Platform.isMacOS) return 'ane';
    final chip = await _detectChip();
    if (chip != null) return 'gpu';
    return 'cpu';
  }

  String _genericChipLabel() {
    if (Platform.isIOS) return 'Apple Silicon';
    if (Platform.isMacOS) return 'Apple Silicon';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  String _platformLabel() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
