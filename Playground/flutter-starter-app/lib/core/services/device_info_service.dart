import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:runanywhere_ai/core/models/app_types.dart';

/// DeviceInfoService (mirroring iOS DeviceInfoService.swift)
///
/// Retrieves device information (model, chip, memory, OS version, Neural Engine availability).
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
      String chipName = '';
      int totalMemory = 0;
      int availableMemory = 0;
      bool neuralEngineAvailable = false;
      String osVersion = '';

      if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        modelName = iosInfo.utsname.machine;
        chipName = _getChipNameFromModel(modelName);
        osVersion = iosInfo.systemVersion;
        neuralEngineAvailable = _checkNeuralEngineAvailability(modelName);
        // TODO: Get actual memory info via native channel
        totalMemory = 4 * 1024 * 1024 * 1024; // Placeholder: 4GB
        availableMemory = 2 * 1024 * 1024 * 1024; // Placeholder: 2GB
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        modelName = '${androidInfo.manufacturer} ${androidInfo.model}';
        chipName = androidInfo.hardware;
        osVersion = 'Android ${androidInfo.version.release}';
        // TODO: Get actual memory info via native channel
        totalMemory = 4 * 1024 * 1024 * 1024; // Placeholder
        availableMemory = 2 * 1024 * 1024 * 1024; // Placeholder
        neuralEngineAvailable = true; // Android devices generally have NPU
      } else if (Platform.isMacOS) {
        final macOSInfo = await deviceInfoPlugin.macOsInfo;
        modelName = macOSInfo.model;
        chipName = _getChipNameFromModel(modelName);
        osVersion = 'macOS ${macOSInfo.osRelease}';
        totalMemory = macOSInfo.memorySize;
        availableMemory = totalMemory ~/ 2; // Estimate
        neuralEngineAvailable = modelName.contains('arm64') ||
            chipName.contains('Apple') ||
            chipName.contains('M1') ||
            chipName.contains('M2') ||
            chipName.contains('M3') ||
            chipName.contains('M4');
      }

      _deviceInfo = SystemDeviceInfo(
        modelName: modelName,
        chipName: chipName,
        totalMemory: totalMemory,
        availableMemory: availableMemory,
        neuralEngineAvailable: neuralEngineAvailable,
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

  String _getChipNameFromModel(String modelName) {
    // iOS device chip detection
    if (modelName.contains('iPhone')) {
      if (modelName.contains('iPhone17')) return 'A18 Pro';
      if (modelName.contains('iPhone16')) return 'A17 Pro';
      if (modelName.contains('iPhone15')) return 'A16 Bionic';
      if (modelName.contains('iPhone14')) return 'A15 Bionic';
      if (modelName.contains('iPhone13')) return 'A15 Bionic';
      if (modelName.contains('iPhone12')) return 'A14 Bionic';
      return 'Apple Silicon';
    }

    // Mac chip detection
    if (modelName.contains('Mac')) {
      if (modelName.contains('arm64')) return 'Apple Silicon';
      return 'Intel';
    }

    return 'Unknown';
  }

  bool _checkNeuralEngineAvailability(String modelName) {
    // Neural Engine available on A11+ chips (iPhone 8 and later)
    if (modelName.contains('iPhone')) {
      final match = RegExp(r'iPhone(\d+)').firstMatch(modelName);
      if (match != null) {
        final version = int.tryParse(match.group(1) ?? '0') ?? 0;
        return version >= 10; // iPhone 8 = iPhone10
      }
    }
    return true; // Assume available for modern devices
  }
}
