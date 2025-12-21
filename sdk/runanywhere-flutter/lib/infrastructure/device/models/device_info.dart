import 'dart:async';
import 'dart:io';

import '../services/device_identity.dart';

/// Core device hardware information.
///
/// Mirrors iOS `DeviceInfo` from RunAnywhere SDK.
/// This is embedded in DeviceRegistrationRequest and also available standalone
/// via DeviceRegistrationService.currentDeviceInfo.
class DeviceInfo {
  // MARK: - Device Identity

  /// Persistent device UUID (survives app reinstalls via Keychain)
  final String deviceId;

  // MARK: - Device Hardware

  /// Device model identifier (e.g., "iPhone16,2" for iPhone 15 Pro Max)
  final String modelIdentifier;

  /// User-friendly device name (e.g., "iPhone 15 Pro Max")
  final String modelName;

  /// CPU architecture (e.g., "arm64", "x86_64")
  final String architecture;

  // MARK: - Operating System

  /// Operating system version string (e.g., "17.2")
  final String osVersion;

  /// Platform identifier (e.g., "iOS", "android")
  final String platform;

  // MARK: - Device Classification

  /// Device type for API requests (mobile, tablet, desktop, tv, watch, vr)
  final String deviceType;

  /// Form factor (phone, tablet, laptop, desktop, tv, watch, headset)
  final String formFactor;

  // MARK: - Hardware Specs

  /// Total physical memory in bytes
  final int totalMemory;

  /// Number of processor cores
  final int processorCount;

  // MARK: - Initialization

  const DeviceInfo({
    required this.deviceId,
    required this.modelIdentifier,
    required this.modelName,
    required this.architecture,
    required this.osVersion,
    required this.platform,
    required this.deviceType,
    required this.formFactor,
    required this.totalMemory,
    required this.processorCount,
  });

  // MARK: - JSON Serialization

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'model_identifier': modelIdentifier,
        'model_name': modelName,
        'architecture': architecture,
        'os_version': osVersion,
        'platform': platform,
        'device_type': deviceType,
        'form_factor': formFactor,
        'total_memory': totalMemory,
        'processor_count': processorCount,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String,
      modelIdentifier: json['model_identifier'] as String,
      modelName: json['model_name'] as String,
      architecture: json['architecture'] as String,
      osVersion: json['os_version'] as String,
      platform: json['platform'] as String,
      deviceType: json['device_type'] as String,
      formFactor: json['form_factor'] as String,
      totalMemory: json['total_memory'] as int,
      processorCount: json['processor_count'] as int,
    );
  }

  // MARK: - Computed Properties

  /// Clean OS version (e.g., "17.2" instead of "Version 17.2 (Build 21C52)")
  String get cleanOSVersion {
    final regex = RegExp(r'(\d+\.\d+(?:\.\d+)?)');
    final match = regex.firstMatch(osVersion);
    return match?.group(1) ?? osVersion;
  }

  // MARK: - Current Device Info

  /// Get current device info - called fresh each time.
  /// Note: deviceId is async, so use DeviceInfo.fetchCurrent() for full info.
  static DeviceInfo current(String deviceId) {
    // Architecture
    String architecture;
    if (Platform.isIOS || Platform.isMacOS) {
      // ARM64 on Apple Silicon, x86_64 on Intel
      architecture = 'arm64'; // Assume ARM64 for modern devices
    } else if (Platform.isAndroid) {
      architecture = 'arm64'; // Most Android devices are ARM64
    } else {
      architecture = 'x86_64';
    }

    // Platform and device type
    String platformName;
    String deviceType;
    String formFactor;
    String modelIdentifier;
    String modelName;

    if (Platform.isIOS) {
      platformName = 'iOS';
      deviceType = 'mobile';
      formFactor = 'phone';
      modelIdentifier = 'iPhone'; // Would need platform channel for real value
      modelName = 'iPhone';
    } else if (Platform.isAndroid) {
      platformName = 'android';
      deviceType = 'mobile';
      formFactor = 'phone';
      modelIdentifier = 'Android'; // Would need platform channel for real value
      modelName = 'Android Device';
    } else if (Platform.isMacOS) {
      platformName = 'macOS';
      deviceType = 'desktop';
      formFactor = 'desktop';
      modelIdentifier = 'Mac';
      modelName = 'Mac';
    } else if (Platform.isLinux) {
      platformName = 'linux';
      deviceType = 'desktop';
      formFactor = 'desktop';
      modelIdentifier = 'Linux';
      modelName = 'Linux Device';
    } else if (Platform.isWindows) {
      platformName = 'windows';
      deviceType = 'desktop';
      formFactor = 'desktop';
      modelIdentifier = 'Windows';
      modelName = 'Windows Device';
    } else {
      platformName = 'unknown';
      deviceType = 'unknown';
      formFactor = 'unknown';
      modelIdentifier = 'Unknown';
      modelName = 'Unknown Device';
    }

    return DeviceInfo(
      deviceId: deviceId,
      modelIdentifier: modelIdentifier,
      modelName: modelName,
      architecture: architecture,
      osVersion: Platform.operatingSystemVersion,
      platform: platformName,
      deviceType: deviceType,
      formFactor: formFactor,
      totalMemory: 0, // Would need platform channel
      processorCount: Platform.numberOfProcessors,
    );
  }

  /// Fetch current device info asynchronously (includes persistent deviceId).
  static Future<DeviceInfo> fetchCurrent() async {
    final deviceId = await DeviceIdentity.persistentUUID;
    return current(deviceId);
  }

  @override
  String toString() =>
      'DeviceInfo(deviceId: ${deviceId.substring(0, 8)}..., model: $modelName, platform: $platform)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}
