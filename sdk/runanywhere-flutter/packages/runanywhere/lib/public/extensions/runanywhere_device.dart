/// RunAnywhere + Device
///
/// Public API for NPU chip detection.
/// Android only — returns null on iOS and other platforms.
library runanywhere_device;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:runanywhere/core/types/npu_chip.dart';
import 'package:runanywhere/public/runanywhere.dart';

// =============================================================================
// NPU Chip Detection
// =============================================================================

/// Extension methods for NPU chip detection
extension RunAnywhereDevice on RunAnywhere {
  static final _channel = MethodChannel('runanywhere');

  /// Detect the device's NPU chipset for Genie model compatibility.
  ///
  /// Returns the [NPUChip] if the device has a supported Qualcomm SoC,
  /// or null if the device is not Android or does not support NPU inference.
  ///
  /// Example:
  /// ```dart
  /// final chip = await RunAnywhereDevice.getChip();
  /// if (chip != null) {
  ///   final url = chip.downloadUrl('qwen3-4b');
  ///   RunAnywhere.registerModel(id: 'qwen3-4b-npu', name: 'Qwen3 4B NPU', url: url, ...);
  /// }
  /// ```
  static Future<NPUChip?> getChip() async {
    if (!Platform.isAndroid) return null;

    try {
      final socModel = await _channel.invokeMethod<String>('getSocModel');
      if (socModel == null || socModel.isEmpty) return null;
      return NPUChip.fromSocModel(socModel);
    } on PlatformException {
      return null;
    }
  }
}
