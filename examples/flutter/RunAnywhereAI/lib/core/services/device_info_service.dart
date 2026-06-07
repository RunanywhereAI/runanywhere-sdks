import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:runanywhere_ai/core/models/app_types.dart';

/// DeviceInfoService (mirroring iOS DeviceInfoService.swift)
///
/// Retrieves device model / OS / app version from platform plugins. Chip, NPU
/// and total-memory facts used to come from the SDK's hardware ABI, but that
/// ABI was removed when the routing scorer was retired (the engine router no
/// longer needs a hardware profile). Device-info display is a UI concern, so
/// the example reads what the platform exposes and leaves the rest empty; the
/// UI hides rows with empty values.
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
      String chipName = '';

      if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        modelName = iosInfo.utsname.machine;
        osVersion = iosInfo.systemVersion;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        modelName = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
        // Best-effort chip name from the platform (no SDK hardware probe).
        chipName = androidInfo.hardware;
      } else if (Platform.isMacOS) {
        final macOSInfo = await deviceInfoPlugin.macOsInfo;
        modelName = macOSInfo.model;
        osVersion = 'macOS ${macOSInfo.osRelease}';
      }

      _deviceInfo = SystemDeviceInfo(
        modelName: modelName,
        chipName: chipName,
        totalMemory: 0,
        availableMemory: 0,
        neuralEngineAvailable: false,
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
}
