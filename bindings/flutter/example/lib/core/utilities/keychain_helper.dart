import 'dart:typed_data';

import 'package:runanywhere_ai/core/services/keychain_service.dart';

/// KeychainHelper (mirroring iOS KeychainHelper.swift)
///
/// Static utility methods for keychain operations.
class KeychainHelper {
  KeychainHelper._();

  /// Save a boolean value to keychain
  static Future<void> saveBool({
    required String key,
    required bool data,
  }) async {
    final bytes = Uint8List.fromList([data ? 1 : 0]);
    await KeychainService.shared.saveBytes(key: key, data: bytes);
  }

  /// Save string to keychain
  static Future<void> saveString({
    required String key,
    required String data,
  }) async {
    await KeychainService.shared.save(key: key, data: data);
  }

  /// Load a boolean value from keychain
  static Future<bool> loadBool(String key, {bool defaultValue = false}) async {
    final data = await KeychainService.shared.readBytes(key);
    if (data == null || data.isEmpty) {
      return defaultValue;
    }
    return data.first == 1;
  }

  /// Load string from keychain
  static Future<String?> loadString(String key) {
    return KeychainService.shared.read(key);
  }

  /// Delete an item from keychain
  static Future<void> delete(String key) async {
    await KeychainService.shared.delete(key);
  }
}
