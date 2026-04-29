// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_hardware.dart — Hardware Profile capability surface
// (canonical §14 namespace). Mirrors Swift `RunAnywhere.Hardware` and
// the RN/Web `RunAnywhere.hardware.*` namespace.
//
// G-C6 / G-B1 note: hardware_profile.proto + `rac_hardware_profile_*`
// C ABI are not yet shipped. We expose the canonical namespace shape
// and synthesize the values from the existing Dart-side device probe
// (`RunAnywhereDevice.getChip()`) plus platform info.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'package:runanywhere/core/types/npu_chip.dart';

/// Hardware profile capability surface.
///
/// Access via `RunAnywhereSDK.instance.hardware`.
class RunAnywhereHardware {
  RunAnywhereHardware._();
  static final RunAnywhereHardware _instance = RunAnywhereHardware._();
  static RunAnywhereHardware get shared => _instance;

  static const _channel = MethodChannel('runanywhere');

  /// Aggregate device profile (chip, NPU presence, recommended accel).
  Future<HardwareProfile> getProfile() async {
    final chip = await _detectChip();
    final hasNPU = chip != null;
    final accel = await _detectAccelerationMode();
    return HardwareProfile(
      chip: chip?.displayName ?? _genericChipLabel(),
      hasNeuralEngine: hasNPU,
      accelerationMode: accel,
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

  /// Recommended acceleration mode (`"NPU"`, `"Neural Engine"`, `"GPU"`,
  /// `"CPU"`). Mirrors the Swift / Web `accelerationMode` getter.
  Future<String> get accelerationMode async => _detectAccelerationMode();

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
    if (Platform.isIOS || Platform.isMacOS) return 'Neural Engine';
    final chip = await _detectChip();
    if (chip != null) return 'NPU';
    return 'CPU';
  }

  String _genericChipLabel() {
    if (Platform.isIOS) return 'Apple Silicon';
    if (Platform.isMacOS) return 'Apple Silicon';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}

/// Hardware profile snapshot returned from `hardware.getProfile()`.
class HardwareProfile {
  final String chip;
  final bool hasNeuralEngine;
  final String accelerationMode;

  const HardwareProfile({
    required this.chip,
    required this.hasNeuralEngine,
    required this.accelerationMode,
  });
}
