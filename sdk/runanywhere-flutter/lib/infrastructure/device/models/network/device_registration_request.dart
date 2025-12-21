import '../device_info.dart';
import '../../../../foundation/configuration/sdk_constants.dart';

/// Request payload for device registration with backend.
///
/// Mirrors iOS `DeviceRegistrationRequest` from RunAnywhere SDK.
/// Used by DeviceRegistrationService for all environments.
class DeviceRegistrationRequest {
  // MARK: - Device Information

  /// Persistent device UUID
  final String deviceId;

  /// Device model identifier
  final String modelIdentifier;

  /// User-friendly device name
  final String modelName;

  /// CPU architecture
  final String architecture;

  /// Operating system version
  final String osVersion;

  /// Platform identifier
  final String platform;

  /// Device type
  final String deviceType;

  /// Form factor
  final String formFactor;

  /// Total memory in bytes
  final int totalMemory;

  /// Number of processor cores
  final int processorCount;

  // MARK: - SDK Information

  /// SDK version
  final String sdkVersion;

  /// SDK platform
  final String sdkPlatform;

  // MARK: - Initialization

  const DeviceRegistrationRequest({
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
    required this.sdkVersion,
    required this.sdkPlatform,
  });

  // MARK: - Factory Methods

  /// Create request from current device info.
  /// Matches iOS DeviceRegistrationRequest.fromCurrentDevice()
  static Future<DeviceRegistrationRequest> fromCurrentDevice() async {
    final deviceInfo = await DeviceInfo.fetchCurrent();

    return DeviceRegistrationRequest(
      deviceId: deviceInfo.deviceId,
      modelIdentifier: deviceInfo.modelIdentifier,
      modelName: deviceInfo.modelName,
      architecture: deviceInfo.architecture,
      osVersion: deviceInfo.osVersion,
      platform: deviceInfo.platform,
      deviceType: deviceInfo.deviceType,
      formFactor: deviceInfo.formFactor,
      totalMemory: deviceInfo.totalMemory,
      processorCount: deviceInfo.processorCount,
      sdkVersion: SDKConstants.version,
      sdkPlatform: SDKConstants.platform,
    );
  }

  /// Create request synchronously with provided device ID.
  static DeviceRegistrationRequest fromDeviceId(String deviceId) {
    final deviceInfo = DeviceInfo.current(deviceId);

    return DeviceRegistrationRequest(
      deviceId: deviceInfo.deviceId,
      modelIdentifier: deviceInfo.modelIdentifier,
      modelName: deviceInfo.modelName,
      architecture: deviceInfo.architecture,
      osVersion: deviceInfo.osVersion,
      platform: deviceInfo.platform,
      deviceType: deviceInfo.deviceType,
      formFactor: deviceInfo.formFactor,
      totalMemory: deviceInfo.totalMemory,
      processorCount: deviceInfo.processorCount,
      sdkVersion: SDKConstants.version,
      sdkPlatform: SDKConstants.platform,
    );
  }

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
        'sdk_version': sdkVersion,
        'sdk_platform': sdkPlatform,
      };

  factory DeviceRegistrationRequest.fromJson(Map<String, dynamic> json) {
    return DeviceRegistrationRequest(
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
      sdkVersion: json['sdk_version'] as String,
      sdkPlatform: json['sdk_platform'] as String,
    );
  }
}
