import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage manager for API keys and sensitive data
class KeychainManager {
  static final KeychainManager shared = KeychainManager._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  KeychainManager._();

  /// Store a value securely
  Future<void> store(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Retrieve a value
  Future<String?> retrieve(String key) async {
    return await _storage.read(key: key);
  }

  /// Delete a value
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Store device UUID
  Future<void> storeDeviceUUID(String deviceId) async {
    await store('com.runanywhere.sdk.device.uuid', deviceId);
  }

  /// Retrieve device UUID
  Future<String?> retrieveDeviceUUID() async {
    return await retrieve('com.runanywhere.sdk.device.uuid');
  }

  /// Store SDK initialization parameters
  Future<void> storeSDKParams({
    required String apiKey,
    required Uri baseURL,
    required String environment,
  }) async {
    await store('com.runanywhere.sdk.apiKey', apiKey);
    await store('com.runanywhere.sdk.baseURL', baseURL.toString());
    await store('com.runanywhere.sdk.environment', environment);
  }

  /// Retrieve SDK initialization parameters
  Future<Map<String, String?>> retrieveSDKParams() async {
    return {
      'apiKey': await retrieve('com.runanywhere.sdk.apiKey'),
      'baseURL': await retrieve('com.runanywhere.sdk.baseURL'),
      'environment': await retrieve('com.runanywhere.sdk.environment'),
    };
  }
}
