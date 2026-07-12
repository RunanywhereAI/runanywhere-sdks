// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

typedef _SecureStoreNative =
    Int32 Function(Pointer<Utf8> key, Pointer<Utf8> value);
typedef _SecureStoreDart = int Function(Pointer<Utf8> key, Pointer<Utf8> value);
typedef _SecureRetrieveNative =
    Int32 Function(
      Pointer<Utf8> key,
      Pointer<Utf8> outValue,
      IntPtr bufferSize,
    );
typedef _SecureRetrieveDart =
    int Function(Pointer<Utf8> key, Pointer<Utf8> outValue, int bufferSize);
typedef _SecureDeleteNative = Int32 Function(Pointer<Utf8> key);
typedef _SecureDeleteDart = int Function(Pointer<Utf8> key);

/// Result of a synchronous secure-storage read.
final class SecureStorageReadResult {
  const SecureStorageReadResult(this.status, this.value);

  final int status;
  final String? value;
}

/// Platform-owned synchronous secure storage used by C callback vtables.
///
/// Dart plugin storage APIs are asynchronous and cannot truthfully satisfy a
/// synchronous FFI callback. The Flutter plugin therefore exports
/// small native helpers backed by Keychain on Apple and Android Keystore plus
/// atomic no-backup ciphertext files on Android. Every mutation is complete
/// before these methods return success.
final class DartBridgeSecureStorage {
  DartBridgeSecureStorage._(DynamicLibrary library)
    : _store = library.lookupFunction<_SecureStoreNative, _SecureStoreDart>(
        'ra_flutter_secure_storage_store',
      ),
      _retrieve = library
          .lookupFunction<_SecureRetrieveNative, _SecureRetrieveDart>(
            'ra_flutter_secure_storage_retrieve',
          ),
      _delete = library.lookupFunction<_SecureDeleteNative, _SecureDeleteDart>(
        'ra_flutter_secure_storage_delete',
      );

  static const int maxValueBytes = 2048;
  static DartBridgeSecureStorage? _instance;

  final _SecureStoreDart _store;
  final _SecureRetrieveDart _retrieve;
  final _SecureDeleteDart _delete;

  static DartBridgeSecureStorage get instance =>
      _instance ??= DartBridgeSecureStorage._(_loadPlatformLibrary());

  static DynamicLibrary _loadPlatformLibrary() {
    if (Platform.isAndroid) {
      final helpers = PlatformLoader.tryLoadFlutterNativePortHelpers();
      if (helpers == null) {
        throw StateError('Flutter native secure-storage helpers are missing');
      }
      return helpers;
    }

    if (Platform.isIOS) {
      for (final library in <DynamicLibrary>[
        DynamicLibrary.process(),
        DynamicLibrary.executable(),
      ]) {
        try {
          library.lookup<Void>('ra_flutter_secure_storage_store');
          return library;
        } catch (_) {
          // Try the next image. Xcode debug builds may place plugin objects in
          // Runner.debug.dylib rather than the launcher executable.
        }
      }
      throw StateError('Flutter Keychain helper symbols are missing');
    }

    throw UnsupportedError(
      'RunAnywhere Flutter secure storage supports Android and iOS only',
    );
  }

  int storePointers(Pointer<Utf8> key, Pointer<Utf8> value) =>
      _store(key, value);

  int retrievePointers(
    Pointer<Utf8> key,
    Pointer<Utf8> outValue,
    int bufferSize,
  ) => _retrieve(key, outValue, bufferSize);

  int deletePointer(Pointer<Utf8> key) => _delete(key);

  void store(String key, String value) {
    final keyPointer = key.toNativeUtf8();
    final valuePointer = value.toNativeUtf8();
    try {
      SDKException.throwIfError(_store(keyPointer, valuePointer));
    } finally {
      calloc.free(valuePointer);
      calloc.free(keyPointer);
    }
  }

  SecureStorageReadResult retrieve(String key) {
    final keyPointer = key.toNativeUtf8();
    final outValue = calloc<Uint8>(maxValueBytes).cast<Utf8>();
    try {
      final status = _retrieve(keyPointer, outValue, maxValueBytes);
      if (status > 0) {
        return SecureStorageReadResult(status, outValue.toDartString());
      }
      return SecureStorageReadResult(status, null);
    } finally {
      calloc.free(outValue);
      calloc.free(keyPointer);
    }
  }

  void delete(String key) {
    final keyPointer = key.toNativeUtf8();
    try {
      SDKException.throwIfError(_delete(keyPointer));
    } finally {
      calloc.free(keyPointer);
    }
  }

  /// Return null only for a canonical clean miss; propagate every real error.
  String? retrieveIfExists(String key) {
    final result = retrieve(key);
    if (result.status > 0) return result.value;
    if (result.status == RacResultCode.errorFileNotFound) return null;
    SDKException.throwIfError(result.status);
    throw StateError('Secure-storage read returned an invalid status');
  }
}
