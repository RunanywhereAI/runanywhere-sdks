import 'dart:typed_data';

import 'package:runanywhere_ai/core/services/keychain_service.dart';

/// KeychainHelper (mirroring iOS KeychainHelper.swift)
///
/// Static utility methods for keychain operations.
class KeychainHelper {
  static const String _service = 'com.runanywhere.RunAnywhereAI';

  KeychainHelper._();

  /// Save a boolean value to keychain
  static Future<void> saveBool({
    required String key,
    required bool data,
  }) async {
    final bytes = Uint8List.fromList([data ? 1 : 0]);
    await saveBytes(key: key, data: bytes);
  }

  /// Save bytes to keychain
  static Future<void> saveBytes({
    required String key,
    required Uint8List data,
  }) async {
    await KeychainService.shared.saveBytes(
      key: _prefixKey(key),
      data: data,
    );
  }

  /// Save string to keychain
  static Future<void> saveString({
    required String key,
    required String data,
  }) async {
    await KeychainService.shared.save(
      key: _prefixKey(key),
      data: data,
    );
  }

  /// Load a boolean value from keychain
  static Future<bool> loadBool(String key, {bool defaultValue = false}) async {
    final data = await loadBytes(key);
    if (data == null || data.isEmpty) {
      return defaultValue;
    }
    return data.first == 1;
  }

  /// Load bytes from keychain
  static Future<Uint8List?> loadBytes(String key) {
    return KeychainService.shared.readBytes(_prefixKey(key));
  }

  /// Load string from keychain
  static Future<String?> loadString(String key) {
    return KeychainService.shared.read(_prefixKey(key));
  }

  /// Delete an item from keychain
  static Future<void> delete(String key) async {
    await KeychainService.shared.delete(_prefixKey(key));
  }

  /// Prefix key with service name for namespacing
  static String _prefixKey(String key) => '${_service}_$key';
}
