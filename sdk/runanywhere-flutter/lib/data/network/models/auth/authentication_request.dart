/// Request model for authentication.
///
/// Matches iOS `AuthenticationRequest` from RunAnywhere SDK.
class AuthenticationRequest {
  final String apiKey;
  final String deviceId;
  final String platform;
  final String sdkVersion;

  const AuthenticationRequest({
    required this.apiKey,
    required this.deviceId,
    required this.platform,
    required this.sdkVersion,
  });

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        'device_id': deviceId,
        'platform': platform,
        'sdk_version': sdkVersion,
      };
}
