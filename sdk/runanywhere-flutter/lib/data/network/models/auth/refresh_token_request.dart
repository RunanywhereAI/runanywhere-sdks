/// Request model for token refresh.
///
/// Matches iOS `RefreshTokenRequest` from RunAnywhere SDK.
class RefreshTokenRequest {
  final String deviceId;
  final String refreshToken;

  const RefreshTokenRequest({
    required this.deviceId,
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'refresh_token': refreshToken,
      };
}
