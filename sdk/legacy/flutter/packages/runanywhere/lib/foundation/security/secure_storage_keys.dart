/// SecureStorageKeys
///
/// Keychain/secure storage key constants
///
/// Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
/// Reference: sdk/runanywhere-react-native/packages/core/src/Foundation/Security/SecureStorageKeys.ts
///
/// These keys are used for:
/// - iOS: Keychain (survives app reinstalls)
/// - Android: EncryptedSharedPreferences (survives app reinstalls)
class SecureStorageKeys {
  SecureStorageKeys._(); // Prevent instantiation

  // SDK Core
  static const apiKey = 'com.runanywhere.sdk.apiKey';
  static const baseURL = 'com.runanywhere.sdk.baseURL';
  static const environment = 'com.runanywhere.sdk.environment';

  // Device Identity (survives app reinstalls)
  static const deviceUUID = 'com.runanywhere.sdk.device.uuid';
  static const deviceRegistered = 'com.runanywhere.sdk.device.isRegistered';

  // Authentication Tokens
  static const accessToken = 'com.runanywhere.sdk.accessToken';
  static const refreshToken = 'com.runanywhere.sdk.refreshToken';
  static const tokenExpiresAt = 'com.runanywhere.sdk.tokenExpiresAt';

  // User/Org Identity
  static const deviceId = 'com.runanywhere.sdk.deviceId';
  static const userId = 'com.runanywhere.sdk.userId';
  static const organizationId = 'com.runanywhere.sdk.organizationId';
}
