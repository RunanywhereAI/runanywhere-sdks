import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

@visibleForTesting
extension OptionsExtension on Map<String, String> {
  bool get useBackwardCompatibility =>
      this['useBackwardCompatibility'] != 'false';
}

class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  final FlutterSecureStoragePlatform _backwardCompatible;
  final MapStorage _storage;

  FlutterSecureStorageWindows()
      : this._(
          MethodChannelFlutterSecureStorage(),
          DpapiJsonFileMapStorage(),
        );

  FlutterSecureStorageWindows._(
    this._backwardCompatible,
    this._storage,
  );

  /// Registers this plugin.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    if (map.containsKey(key)) {
      return true;
    }

    if (options.useBackwardCompatibility) {
      return _backwardCompatible.containsKey(key: key, options: options);
    }

    return false;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    final initialSize = map.length;
    map.remove(key);
    if (map.length != initialSize) {
      await _storage.save(map, options);
    }

    if (options.useBackwardCompatibility) {
      await _backwardCompatible.delete(key: key, options: options);
    }
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    await _storage.clear(options);

    if (options.useBackwardCompatibility) {
      await _backwardCompatible.deleteAll(options: options);
    }
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);

    var result = map[key];
    if (options.useBackwardCompatibility) {
      if (result == null) {
        final compatible =
            await _backwardCompatible.read(key: key, options: options);
        if (compatible != null) {
          // Write back now, so the value should be retrieved from JSON file next.
          result = map[key] = compatible;
          await _storage.save(map, options);
        }
      }

      // Clear old entry.
      await _backwardCompatible.delete(key: key, options: options);
    }

    return result;
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    if (!options.useBackwardCompatibility) {
      // Just return a map.
      return map;
    }

    final compatible = await _backwardCompatible.readAll(options: options);

    if (compatible.isEmpty) {
      return map;
    }

    for (final entry in compatible.entries) {
      map.putIfAbsent(entry.key, () => entry.value);
    }

    // Write back now, so the value should be retrieved from JSON file next.
    await _storage.save(map, options);

    // Clear old entries.
    await _backwardCompatible.deleteAll(options: options);

    return map;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    map[key] = value;
    await _storage.save(map, options);

    if (options.useBackwardCompatibility) {
      // Clear old entry.
      _backwardCompatible.delete(key: key, options: options);
    }
  }

  // @override
  // Future<bool> isCupertinoProtectedDataAvailable() => Future.value(true);
  //
  // @override
  // Stream<bool> get onCupertinoProtectedDataAvailabilityChanged =>
  //     Stream.value(true);
}

@visibleForTesting
FlutterSecureStorageWindows createFlutterSecureStorageWindows(
  FlutterSecureStoragePlatform backwardCompatible,
  MapStorage mapStorage,
) =>
    FlutterSecureStorageWindows._(backwardCompatible, mapStorage);

@visibleForTesting
abstract class MapStorage {
  FutureOr<Map<String, String>> load(Map<String, String> options);
  FutureOr<void> save(Map<String, String> data, Map<String, String> options);
  FutureOr<void> clear(Map<String, String> options);
}

@visibleForTesting
const String encryptedJsonFileName = 'flutter_secure_storage.dat';

@visibleForTesting
class DpapiJsonFileMapStorage extends MapStorage {
  DpapiJsonFileMapStorage();

  FutureOr<String> _getJsonFilePath() async {
    final appDataDirectory = await getApplicationSupportDirectory();

    return path.canonicalize(
      path.join(
        appDataDirectory.path,
        encryptedJsonFileName,
      ),
    );
  }

  @override
  FutureOr<Map<String, String>> load(Map<String, String> options) async {
    final file = File(await _getJsonFilePath());
    if (!(await file.exists())) {
      return {};
    }

    late final Uint8List encryptedText;
    try {
      encryptedText = await file.readAsBytes();
    } on FileSystemException catch (e) {
      // Another process has been deleted a file or parent directory
      // since previous File.exists() call.
      // We can ignore it.
      debugPrint(
        'Reading file has been deleted by another process. $e',
      );
      return {};
    }

    late final String plainText;
    try {
      plainText = using((alloc) {
        final Pointer<Uint8> pEncryptedText = alloc(encryptedText.length);
        pEncryptedText
            .asTypedList(encryptedText.length)
            .setAll(0, encryptedText);

        // Specify size of the struct explicitly.
        final Pointer<CRYPT_INTEGER_BLOB> encryptedTextBlob =
            alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
        encryptedTextBlob.ref.cbData = encryptedText.length;
        encryptedTextBlob.ref.pbData = pEncryptedText;

        // Specify size of the struct explicitly.
        final Pointer<CRYPT_INTEGER_BLOB> plainTextBlob =
            alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
        if (CryptUnprotectData(
              encryptedTextBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
              plainTextBlob,
            ) ==
            0) {
          throw WindowsException(
            GetLastError(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        if (plainTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY,
            message: 'Failure on CryptUnprotectData()',
          );
        }

        try {
          return utf8.decoder.convert(
            plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
          );
        } finally {
          if (plainTextBlob.ref.pbData.address != NULL) {
            if (LocalFree(plainTextBlob.ref.pbData).address != NULL) {
              debugPrint(
                'load: Failed to LocalFree with: 0x${GetLastError().toHexString(32)}',
              );
            }
          }
        }
      });
    } on FormatException catch (e) {
      // A file content should be malformed.
      debugPrint(
        'Failed to decrypt data: $e Delete corrupt file: ${file.path}',
      );
      await file.delete();
      rethrow;
    } on WindowsException catch (e) {
      // A file content should be malformed.
      debugPrint(
        'Failed to decrypt data: $e Delete corrupt file: ${file.path}',
      );
      await file.delete();
      rethrow;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(plainText);
    } on FormatException catch (e) {
      // A file content should be malformed.
      debugPrint(
        'Failed to parse JSON: $e Delete corrupt file: ${file.path}',
      );
      await file.delete();
      rethrow;
    }

    if (decoded is! Map) {
      debugPrint(
        'Failed to parse JSON: Not an object. Delete corrupt file: ${file.path}',
      );
      await file.delete();
      throw const FormatException('JSON is not an object.');
    }

    return {
      for (final e
          in decoded.entries.where((x) => x.key is String && x.value is String))
        e.key as String: e.value as String,
    };
  }

  @override
  FutureOr<void> save(
    Map<String, String> data,
    Map<String, String> options,
  ) async {
    final file = File(await _getJsonFilePath());
    final json = jsonEncode(data);
    final plainText = utf8.encode(json);

    await using<FutureOr<void>>((alloc) async {
      final Pointer<Uint8> pPlainText = alloc(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      // Specify size of the struct explicitly.
      final Pointer<CRYPT_INTEGER_BLOB> plainTextBlob =
          alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
      plainTextBlob.ref.cbData = plainText.length;
      plainTextBlob.ref.pbData = pPlainText;

      // Specify size of the struct explicitly.
      final Pointer<CRYPT_INTEGER_BLOB> encryptedTextBlob =
          alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
      if (CryptProtectData(
            plainTextBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            encryptedTextBlob,
          ) ==
          0) {
        throw WindowsException(
          GetLastError(),
          message: 'Failure on CryptProtectData()',
        );
      }

      if (encryptedTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          ERROR_OUTOFMEMORY,
          message: 'Failure on CryptProtectData()',
        );
      }

      try {
        final encryptedText = encryptedTextBlob.ref.pbData
            .asTypedList(encryptedTextBlob.ref.cbData);

        // Loop to handle race condition.
        while (true) {
          try {
            await (await file.create(recursive: true))
                .writeAsBytes(encryptedText, flush: true);
            // If success, finish loop.
            break;
          } on FileSystemException catch (e) {
            // Another process has been deleted a file or parent directory
            // since previous File.create() call.
            // We will retry writing.
            debugPrint(
              'Reading file has been deleted by another process. $e',
            );
          }
        }
      } finally {
        if (encryptedTextBlob.ref.pbData.address != NULL) {
          if (LocalFree(encryptedTextBlob.ref.pbData).address != NULL) {
            debugPrint(
              'save: Failed to LocalFree with: 0x${GetLastError().toHexString(32)}',
            );
          }
        }
      }
    });
  }

  @override
  FutureOr<void> clear(Map<String, String> options) async {
    final file = File(await _getJsonFilePath());
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException catch (e) {
        // Another process has been deleted a file or parent directory
        // since previous File.exists() call.
        // We can ignore it.
        debugPrint(
          'Deleting file has been deleted by another process. $e',
        );
      }
    }
  }
}
