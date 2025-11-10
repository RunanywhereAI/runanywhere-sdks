import '../network/services/api_client.dart';

/// Authentication Service
class AuthenticationService {
  final APIClient apiClient;

  AuthenticationService({required this.apiClient});

  /// Register device
  Future<DeviceRegistration> registerDevice() async {
    // TODO: Implement device registration
    throw UnimplementedError();
  }
}

/// Device Registration Response
class DeviceRegistration {
  final String deviceId;

  DeviceRegistration({required this.deviceId});
}

