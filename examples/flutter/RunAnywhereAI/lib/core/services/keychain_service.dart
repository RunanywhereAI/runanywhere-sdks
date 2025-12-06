import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// KeychainService (mirroring iOS KeychainService.swift)
///
/// Provides secure storage for sensitive data using platform-specific
/// secure storage (iOS Keychain, Android Keystore).
class KeychainService {
  static final KeychainService shared = KeychainService._();

  KeychainService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Save string data to keychain
  Future<void> save({required String key, required String data}) async {
    try {
      await _storage.write(key: key, value: data);
    } catch (e) {
      throw KeychainError.saveFailed;
    }
  }

  /// Save bytes to keychain (encoded as base64)
  Future<void> saveBytes({required String key, required Uint8List data}) async {
    try {
      final base64 = String.fromCharCodes(data);
      await _storage.write(key: key, value: base64);
    } catch (e) {
      throw KeychainError.saveFailed;
    }
  }

  /// Read string data from keychain
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      return null;
    }
  }

  /// Read bytes from keychain
  Future<Uint8List?> readBytes(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value == null) return null;
      return Uint8List.fromList(value.codeUnits);
    } catch (e) {
      return null;
    }
  }

  /// Delete data from keychain
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw KeychainError.deleteFailed;
    }
  }

  /// Check if a key exists in keychain
  Future<bool> containsKey(String key) async {
    return await _storage.containsKey(key: key);
  }

  /// Delete all data from keychain
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}

/// Keychain error types
enum KeychainError implements Exception {
  saveFailed,
  deleteFailed,
}
