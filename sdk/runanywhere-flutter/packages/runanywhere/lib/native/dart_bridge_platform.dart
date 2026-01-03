import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Platform adapter bridge for fundamental C++ → Dart operations.
///
/// Provides: logging, file operations, secure storage, clock.
/// Matches Swift's `CppBridge+PlatformAdapter.swift` exactly.
///
/// C++ code cannot directly:
/// - Write to disk
/// - Access secure storage (Keychain/KeyStore)
/// - Get current time
/// - Route logs to native logging system
///
/// This bridge provides those capabilities via C function callbacks.
class DartBridgePlatform {
  DartBridgePlatform._();

  static final _logger = SDKLogger('DartBridge.Platform');

  /// Singleton instance for bridge accessors
  static final DartBridgePlatform instance = DartBridgePlatform._();

  /// Whether the adapter has been registered
  static bool _isRegistered = false;

  /// Secure storage for keychain operations
  // ignore: unused_field
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Register platform adapter with C++.
  /// Must be called FIRST during SDK init (before any C++ operations).
  static void register() {
    if (_isRegistered) {
      _logger.debug('Platform adapter already registered');
      return;
    }

    try {
      final lib = PlatformLoader.load();

      // Create and populate the platform adapter struct
      final adapter = calloc<RacPlatformAdapter>();

      // Logging callback
      adapter.ref.log = Pointer.fromFunction<RacLogCallbackNative>(
        _platformLogCallback,
      );

      // File operations
      adapter.ref.fileExists = Pointer.fromFunction<RacFileExistsCallbackNative>(
        _platformFileExistsCallback,
        0, // Return 0 (false) on exception
      );
      adapter.ref.fileRead = Pointer.fromFunction<RacFileReadCallbackNative>(
        _platformFileReadCallback,
        RacResultCode.errorIO,
      );
      adapter.ref.fileWrite = Pointer.fromFunction<RacFileWriteCallbackNative>(
        _platformFileWriteCallback,
        RacResultCode.errorIO,
      );
      adapter.ref.fileDelete = Pointer.fromFunction<RacFileDeleteCallbackNative>(
        _platformFileDeleteCallback,
        RacResultCode.errorIO,
      );

      // Secure storage (async operations - need special handling)
      adapter.ref.secureGet = Pointer.fromFunction<RacSecureGetCallbackNative>(
        _platformSecureGetCallback,
        RacResultCode.errorIO,
      );
      adapter.ref.secureSet = Pointer.fromFunction<RacSecureSetCallbackNative>(
        _platformSecureSetCallback,
        RacResultCode.errorIO,
      );
      adapter.ref.secureDelete = Pointer.fromFunction<RacSecureDeleteCallbackNative>(
        _platformSecureDeleteCallback,
        RacResultCode.errorIO,
      );

      // Clock
      adapter.ref.nowMs = Pointer.fromFunction<RacNowMsCallbackNative>(
        _platformNowMsCallback,
        0,
      );

      // Memory info (not implemented)
      adapter.ref.getMemoryInfo = Pointer.fromFunction<RacGetMemoryInfoCallbackNative>(
        _platformGetMemoryInfoCallback,
        RacResultCode.errorNotImplemented,
      );

      // Error tracking (Sentry)
      adapter.ref.trackError = Pointer.fromFunction<RacTrackErrorCallbackNative>(
        _platformTrackErrorCallback,
      );

      // Optional callbacks (handled by Dart directly)
      adapter.ref.httpDownload = nullptr;
      adapter.ref.httpDownloadCancel = nullptr;
      adapter.ref.extractArchive = nullptr;
      adapter.ref.userData = nullptr;

      // Register with C++
      final setAdapter = lib.lookupFunction<
          Int32 Function(Pointer<RacPlatformAdapter>),
          int Function(Pointer<RacPlatformAdapter>)>('rac_set_platform_adapter');

      final result = setAdapter(adapter);
      if (result != RacResultCode.success) {
        _logger.error('Failed to register platform adapter', metadata: {
          'error_code': result,
        });
        calloc.free(adapter);
        return;
      }

      _isRegistered = true;
      _logger.debug('Platform adapter registered successfully');

      // Note: We don't free the adapter here as C++ holds a reference to it
      // It will be valid for the lifetime of the application
    } catch (e, stack) {
      _logger.error('Exception registering platform adapter', metadata: {
        'error': e.toString(),
        'stack': stack.toString(),
      });
    }
  }
}

// =============================================================================
// C Callback Functions (must be static top-level functions)
// =============================================================================

/// Logging callback - routes C++ logs to Dart logger
void _platformLogCallback(
  int level,
  Pointer<Utf8> category,
  Pointer<Utf8> message,
  Pointer<Void> userData,
) {
  if (message == nullptr) return;

  final msgString = message.toDartString();
  final categoryString = category != nullptr ? category.toDartString() : 'RAC';

  final logger = SDKLogger(categoryString);

  switch (level) {
    case RacLogLevel.error:
      logger.error(msgString);
      break;
    case RacLogLevel.warning:
      logger.warning(msgString);
      break;
    case RacLogLevel.info:
      logger.info(msgString);
      break;
    case RacLogLevel.debug:
      logger.debug(msgString);
      break;
    case RacLogLevel.trace:
      logger.debug('[TRACE] $msgString');
      break;
    default:
      logger.info(msgString);
      break;
  }
}

/// File exists callback
int _platformFileExistsCallback(
  Pointer<Utf8> path,
  Pointer<Void> userData,
) {
  if (path == nullptr) return 0;

  try {
    final pathString = path.toDartString();
    return File(pathString).existsSync() ? 1 : 0;
  } catch (_) {
    return 0;
  }
}

/// File read callback
int _platformFileReadCallback(
  Pointer<Utf8> path,
  Pointer<Pointer<Void>> outData,
  Pointer<IntPtr> outSize,
  Pointer<Void> userData,
) {
  if (path == nullptr || outData == nullptr || outSize == nullptr) {
    return RacResultCode.errorInvalidParams;
  }

  try {
    final pathString = path.toDartString();
    final file = File(pathString);

    if (!file.existsSync()) {
      return RacResultCode.errorIO; // File not found
    }

    final data = file.readAsBytesSync();

    // Allocate buffer and copy data
    final buffer = calloc<Uint8>(data.length);
    for (var i = 0; i < data.length; i++) {
      buffer[i] = data[i];
    }

    outData.value = buffer.cast<Void>();
    outSize.value = data.length;

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorIO;
  }
}

/// File write callback
int _platformFileWriteCallback(
  Pointer<Utf8> path,
  Pointer<Void> data,
  int size,
  Pointer<Void> userData,
) {
  if (path == nullptr || data == nullptr) {
    return RacResultCode.errorInvalidParams;
  }

  try {
    final pathString = path.toDartString();
    final bytes = data.cast<Uint8>().asTypedList(size);

    final file = File(pathString);
    file.writeAsBytesSync(bytes);

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorIO;
  }
}

/// File delete callback
int _platformFileDeleteCallback(
  Pointer<Utf8> path,
  Pointer<Void> userData,
) {
  if (path == nullptr) {
    return RacResultCode.errorInvalidParams;
  }

  try {
    final pathString = path.toDartString();
    final file = File(pathString);

    if (file.existsSync()) {
      file.deleteSync();
    }

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorIO;
  }
}

/// Secure storage cache for synchronous access
/// Note: flutter_secure_storage is async, so we cache values
final Map<String, String> _secureStorageCache = {};
bool _secureStorageCacheLoaded = false;

/// Load secure storage cache (called during init)
Future<void> loadSecureStorageCache() async {
  if (_secureStorageCacheLoaded) return;

  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    final all = await storage.readAll();
    _secureStorageCache.addAll(all);
    _secureStorageCacheLoaded = true;
  } catch (_) {
    // Ignore errors - cache will be empty
  }
}

/// Secure get callback
int _platformSecureGetCallback(
  Pointer<Utf8> key,
  Pointer<Pointer<Utf8>> outValue,
  Pointer<Void> userData,
) {
  if (key == nullptr || outValue == nullptr) {
    return RacResultCode.errorInvalidParams;
  }

  try {
    final keyString = key.toDartString();
    final value = _secureStorageCache[keyString];

    if (value == null) {
      return RacResultCode.errorIO; // Not found
    }

    // Allocate and copy string
    final cString = value.toNativeUtf8();
    outValue.value = cString;

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorIO;
  }
}

/// Secure set callback
int _platformSecureSetCallback(
  Pointer<Utf8> key,
  Pointer<Utf8> value,
  Pointer<Void> userData,
) {
  if (key == nullptr || value == nullptr) {
    return RacResultCode.errorInvalidParams;
  }

  try {
    final keyString = key.toDartString();
    final valueString = value.toDartString();

    // Update cache immediately for sync access
    _secureStorageCache[keyString] = valueString;

    // Schedule async write (fire and forget)
    _writeSecureStorage(keyString, valueString);

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorIO;
  }
}

/// Async write to secure storage
Future<void> _writeSecureStorage(String key, String value) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    await storage.write(key: key, value: value);
  } catch (_) {
    // Ignore errors - cache is authoritative
  }
}

/// Secure delete callback
int _platformSecureDeleteCallback(
  Pointer<Utf8> key,
  Pointer<Void> userData,
) {
  if (key == nullptr) {
    return RacResultCode.errorInvalidParams;
  }

  try {
    final keyString = key.toDartString();

    // Remove from cache
    _secureStorageCache.remove(keyString);

    // Schedule async delete (fire and forget)
    _deleteSecureStorage(keyString);

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorIO;
  }
}

/// Async delete from secure storage
Future<void> _deleteSecureStorage(String key) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    await storage.delete(key: key);
  } catch (_) {
    // Ignore errors
  }
}

/// Clock callback - returns current time in milliseconds
int _platformNowMsCallback(Pointer<Void> userData) {
  return DateTime.now().millisecondsSinceEpoch;
}

/// Memory info callback - not implemented
int _platformGetMemoryInfoCallback(
  Pointer<Void> outInfo,
  Pointer<Void> userData,
) {
  return RacResultCode.errorNotImplemented;
}

/// Error tracking callback - sends to Sentry
void _platformTrackErrorCallback(
  Pointer<Utf8> errorJson,
  Pointer<Void> userData,
) {
  if (errorJson == nullptr) return;

  try {
    final jsonString = errorJson.toDartString();

    // Log the error for now
    // TODO: Integrate with Sentry when available
    SDKLogger('DartBridge.ErrorTracking').error(
      'C++ error received',
      metadata: {'error_json': jsonString},
    );
  } catch (_) {
    // Ignore errors in error handling
  }
}

/// Log level constants matching rac_log_level_t
abstract class RacLogLevel {
  static const int error = 0;
  static const int warning = 1;
  static const int info = 2;
  static const int debug = 3;
  static const int trace = 4;
}
