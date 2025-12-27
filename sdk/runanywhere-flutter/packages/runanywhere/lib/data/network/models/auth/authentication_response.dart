/// Response model for authentication.
///
/// Matches iOS `AuthenticationResponse` from RunAnywhere SDK.
class AuthenticationResponse {
  final String accessToken;
  final String deviceId;
  final int expiresIn;
  final String organizationId;
  final String refreshToken;
  final String tokenType;
  final String? userId;

  const AuthenticationResponse({
    required this.accessToken,
    required this.deviceId,
    required this.expiresIn,
    required this.organizationId,
    required this.refreshToken,
    required this.tokenType,
    this.userId,
  });

  factory AuthenticationResponse.fromJson(Map<String, dynamic> json) {
    return AuthenticationResponse(
      accessToken: json['access_token'] as String,
      deviceId: json['device_id'] as String,
      expiresIn: json['expires_in'] as int,
      organizationId: json['organization_id'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String,
      userId: json['user_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'device_id': deviceId,
        'expires_in': expiresIn,
        'organization_id': organizationId,
        'refresh_token': refreshToken,
        'token_type': tokenType,
        if (userId != null) 'user_id': userId,
      };
}

/// Response model for token refresh (same as AuthenticationResponse).
/// Matches iOS `RefreshTokenResponse` typealias.
typedef RefreshTokenResponse = AuthenticationResponse;
