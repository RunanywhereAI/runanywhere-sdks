// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_device.dart — NPU chip detection (Android only).
// Returns null on iOS and other platforms.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:runanywhere/core/types/npu_chip.dart';

/// NPU chip detection helpers.
///
/// Example:
/// ```dart
/// final chip = await RunAnywhereDevice.getChip();
/// if (chip != null) {
///   final url = chip.downloadUrl('qwen3-4b');
///   RunAnywhereSDK.instance.models.register(
///     id: 'qwen3-4b-npu',
///     name: 'Qwen3 4B NPU',
///     url: url,
///     framework: InferenceFramework.genie,
///   );
/// }
/// ```
class RunAnywhereDevice {
  RunAnywhereDevice._();

  static const _channel = MethodChannel('runanywhere');

  /// Detect the device's NPU chipset for Genie model compatibility.
  ///
  /// Returns the [NPUChip] if the device has a supported Qualcomm
  /// SoC, or null if the device is not Android or does not support
  /// NPU inference.
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
