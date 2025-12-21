/// Response payload from device registration endpoint.
///
/// Mirrors iOS `DeviceRegistrationResponse` from RunAnywhere SDK.
class DeviceRegistrationResponse {
  /// The registered device ID (should match the request)
  final String deviceId;

  /// Registration timestamp from server
  final DateTime? registeredAt;

  /// Optional message from server
  final String? message;

  /// Whether this is a new registration or existing device
  final bool isNewDevice;

  const DeviceRegistrationResponse({
    required this.deviceId,
    this.registeredAt,
    this.message,
    this.isNewDevice = true,
  });

  // MARK: - JSON Serialization

  factory DeviceRegistrationResponse.fromJson(Map<String, dynamic> json) {
    return DeviceRegistrationResponse(
      deviceId: json['device_id'] as String? ?? json['deviceId'] as String,
      registeredAt: json['registered_at'] != null
          ? DateTime.tryParse(json['registered_at'] as String)
          : null,
      message: json['message'] as String?,
      isNewDevice: json['is_new_device'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'registered_at': registeredAt?.toIso8601String(),
        'message': message,
        'is_new_device': isNewDevice,
      };

  @override
  String toString() =>
      'DeviceRegistrationResponse(deviceId: $deviceId, isNew: $isNewDevice)';
}
