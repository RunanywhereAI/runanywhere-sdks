import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:runanywhere/runanywhere.dart';

import 'package:runanywhere_ai/core/models/app_types.dart';

/// DeviceInfoService (mirroring iOS DeviceInfoService.swift)
///
/// Retrieves device information (model, OS version) and delegates chip,
/// neural-engine, and memory facts to `RunAnywhere.hardware.getProfile()`.
/// The SDK's hardware ABI is the single source of truth; example code must
/// not reimplement chip/NPU heuristics (AGENTS.md Business Logic Layering).
class DeviceInfoService extends ChangeNotifier {
  static final DeviceInfoService shared = DeviceInfoService._();

  DeviceInfoService._() {
    unawaited(refreshDeviceInfo());
  }

  SystemDeviceInfo? _deviceInfo;
  bool _isLoading = false;

  SystemDeviceInfo? get deviceInfo => _deviceInfo;
  bool get isLoading => _isLoading;

  Future<void> refreshDeviceInfo() async {
    _isLoading = true;
    notifyListeners();

    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      String modelName = '';
      String osVersion = '';

      if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        modelName = iosInfo.utsname.machine;
        osVersion = iosInfo.systemVersion;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        modelName = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isMacOS) {
        final macOSInfo = await deviceInfoPlugin.macOsInfo;
        modelName = macOSInfo.model;
        osVersion = 'macOS ${macOSInfo.osRelease}';
      }

      // Hardware facts come from the commons hardware ABI via the SDK so new
      // chips/NPUs are picked up without an example release. When the native
      // probe is unavailable (debug builds without commons, simulator drift),
      // fall back to empty values so the UI can hide the rows gracefully.
      final profile = await _tryGetHardwareProfile();

      _deviceInfo = SystemDeviceInfo(
        modelName: modelName,
        chipName: profile?.chip ?? '',
        totalMemory: profile?.totalMemoryBytes.toInt() ?? 0,
        availableMemory: 0,
        neuralEngineAvailable: profile?.hasNeuralEngine ?? false,
        osVersion: osVersion,
        appVersion: packageInfo.version,
      );
    } catch (e) {
      debugPrint('Error getting device info: $e');
      _deviceInfo = const SystemDeviceInfo(
        modelName: 'Unknown',
        chipName: 'Unknown',
        osVersion: 'Unknown',
        appVersion: '1.0.0',
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<HardwareProfile?> _tryGetHardwareProfile() async {
    try {
      final result = await RunAnywhere.hardware.getProfile();
      return result.hasProfile() ? result.profile : null;
    } catch (e) {
      debugPrint('Hardware profile unavailable: $e');
      return null;
    }
  }
}
