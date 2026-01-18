// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// Exception Return Constants (must be compile-time constants for FFI)
// =============================================================================

/// Exceptional return value for file operations that return Int32
const int _exceptionalReturnInt32 = -183; // RAC_ERROR_FILE_NOT_FOUND

/// Exceptional return value for bool operations
const int _exceptionalReturnFalse = 0;

/// Exceptional return value for int64 operations
const int _exceptionalReturnInt64 = 0;

// =============================================================================
// Platform Adapter Bridge
// =============================================================================

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

  /// Pointer to the adapter struct (must persist for C++ to call)
  static Pointer<RacPlatformAdapterStruct>? _adapterPtr;

  /// Thread-safe logger callback using NativeCallable.listener
  /// This callback can be invoked from ANY thread/isolate and posts to our event loop
  /// CRITICAL: Must be kept alive to prevent garbage collection
  static NativeCallable<RacLogCallbackNative>? _loggerCallable;

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
      final lib = PlatformLoader.loadCommons();

      // Allocate the platform adapter struct
      _adapterPtr = calloc<RacPlatformAdapterStruct>();
      final adapter = _adapterPtr!;

      // Logging callback - MUST use NativeCallable.listener for thread safety
      // This allows C++ to call the logger from any thread (including background
      // threads used by LLM generation) without crashing with:
      // "Cannot invoke native callback from a different isolate"
      _loggerCallable = NativeCallable<RacLogCallbackNative>.listener(
        _platformLogCallback,
      );
      adapter.ref.log = _loggerCallable!.nativeFunction;

      // File operations
      adapter.ref.fileExists =
          Pointer.fromFunction<RacFileExistsCallbackNative>(
        _platformFileExistsCallback,
        _exceptionalReturnFalse,
      );
      adapter.ref.fileRead = Pointer.fromFunction<RacFileReadCallbackNative>(
        _platformFileReadCallback,
        _exceptionalReturnInt32,
      );
      adapter.ref.fileWrite = Pointer.fromFunction<RacFileWriteCallbackNative>(
        _platformFileWriteCallback,
        _exceptionalReturnInt32,
      );
      adapter.ref.fileDelete =
          Pointer.fromFunction<RacFileDeleteCallbackNative>(
        _platformFileDeleteCallback,
        _exceptionalReturnInt32,
      );

      // Secure storage (async operations - need special handling)
      adapter.ref.secureGet = Pointer.fromFunction<RacSecureGetCallbackNative>(
        _platformSecureGetCallback,
        _exceptionalReturnInt32,
      );
      adapter.ref.secureSet = Pointer.fromFunction<RacSecureSetCallbackNative>(
        _platformSecureSetCallback,
        _exceptionalReturnInt32,
      );
      adapter.ref.secureDelete =
          Pointer.fromFunction<RacSecureDeleteCallbackNative>(
        _platformSecureDeleteCallback,
        _exceptionalReturnInt32,
      );

      // Clock - returns int64, use 0 as exceptional return
      adapter.ref.nowMs = Pointer.fromFunction<RacNowMsCallbackNative>(
        _platformNowMsCallback,
        _exceptionalReturnInt64,
      );

      // Memory info callback - returns errorNotImplemented (platform-specific)
      adapter.ref.getMemoryInfo =
          Pointer.fromFunction<RacGetMemoryInfoCallbackNative>(
        _platformGetMemoryInfoCallback,
        _exceptionalReturnInt32,
      );

      // Error tracking (Sentry)
      adapter.ref.trackError =
          Pointer.fromFunction<RacTrackErrorCallbackNative>(
        _platformTrackErrorCallback,
      );

      // Optional callbacks (handled by Dart directly)
      adapter.ref.httpDownload = nullptr;
      adapter.ref.httpDownloadCancel = nullptr;
      adapter.ref.extractArchive = nullptr;
      adapter.ref.userData = nullptr;

      // Register with C++
      final setAdapter = lib.lookupFunction<
          Int32 Function(Pointer<RacPlatformAdapterStruct>),
          int Function(
              Pointer<RacPlatformAdapterStruct>)>('rac_set_platform_adapter');

      final result = setAdapter(adapter);
      if (result != RacResultCode.success) {
        _logger.error('Failed to register platform adapter', metadata: {
          'error_code': result,
        });
        calloc.free(adapter);
        _adapterPtr = null;
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

  /// Unregister platform adapter (called during shutdown).
  static void unregister() {
    if (!_isRegistered) return;

    // Note: We can't actually unregister from C++ since it holds a pointer
    // Just mark as unregistered
    _isRegistered = false;

    // Close the logger callable to release resources
    // Note: Only do this during true shutdown - C++ may still try to log
    // We keep it alive during normal operation
    // _loggerCallable?.close();
    // _loggerCallable = null;

    // Don't free _adapterPtr - C++ may still reference it
    // It will be cleaned up on process exit
  }

  /// Check if the adapter is registered.
  static bool get isRegistered => _isRegistered;
}

// =============================================================================
// C Callback Functions (must be static top-level functions)
// =============================================================================

/// Logging callback - routes C++ logs to Dart logger
/// 
/// NOTE: This callback is registered with NativeCallable.listener for thread safety.
/// It runs asynchronously on the main isolate's event loop, which means by the time
/// it executes, the C++ log message memory may have been freed. We handle this by
/// catching any UTF-8 decoding errors gracefully.
void _platformLogCallback(
  int level,
  Pointer<Utf8> category,
  Pointer<Utf8> message,
  Pointer<Void> userData,
) {
  if (message == nullptr) return;

  try {
    // Try to decode the message - may fail if memory was freed
    final msgString = message.toDartString();
    if (msgString.isEmpty) return;
    
    final categoryString = category != nullptr ? category.toDartString() : 'RAC';

    final logger = SDKLogger(categoryString);

    switch (level) {
      case RacLogLevel.error:
      case RacLogLevel.fatal:
        logger.error(msgString);
      case RacLogLevel.warning:
        logger.warning(msgString);
      case RacLogLevel.info:
        logger.info(msgString);
      case RacLogLevel.debug:
        logger.debug(msgString);
      case RacLogLevel.trace:
        logger.debug('[TRACE] $msgString');
      default:
        logger.info(msgString);
    }
  } catch (e) {
    // Silently ignore invalid UTF-8 or freed memory errors
    // This can happen because NativeCallable.listener runs asynchronously
    // and the C++ log message buffer may have been freed by then
  }
}

/// File exists callback
int _platformFileExistsCallback(
  Pointer<Utf8> path,
  Pointer<Void> userData,
) {
  if (path == nullptr) return RAC_FALSE;

  try {
    final pathString = path.toDartString();
    return File(pathString).existsSync() ? RAC_TRUE : RAC_FALSE;
  } catch (_) {
    return RAC_FALSE;
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
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final pathString = path.toDartString();
    final file = File(pathString);

    if (!file.existsSync()) {
      return RacResultCode.errorFileNotFound;
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
    return RacResultCode.errorFileReadFailed;
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
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final pathString = path.toDartString();
    final bytes = data.cast<Uint8>().asTypedList(size);

    final file = File(pathString);
    file.writeAsBytesSync(bytes);

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorFileWriteFailed;
  }
}

/// File delete callback
int _platformFileDeleteCallback(
  Pointer<Utf8> path,
  Pointer<Void> userData,
) {
  if (path == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final pathString = path.toDartString();
    final file = File(pathString);

    if (file.existsSync()) {
      file.deleteSync();
    }

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorDeleteFailed;
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
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final keyString = key.toDartString();
    final value = _secureStorageCache[keyString];

    if (value == null) {
      return RacResultCode.errorFileNotFound; // Not found
    }

    // Allocate and copy string
    final cString = value.toNativeUtf8();
    outValue.value = cString;

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorStorageError;
  }
}

/// Secure set callback
int _platformSecureSetCallback(
  Pointer<Utf8> key,
  Pointer<Utf8> value,
  Pointer<Void> userData,
) {
  if (key == nullptr || value == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final keyString = key.toDartString();
    final valueString = value.toDartString();

    // Update cache immediately for sync access
    _secureStorageCache[keyString] = valueString;

    // Schedule async write (fire and forget)
    unawaited(_writeSecureStorage(keyString, valueString));

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorStorageError;
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
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final keyString = key.toDartString();

    // Remove from cache
    _secureStorageCache.remove(keyString);

    // Schedule async delete (fire and forget)
    unawaited(_deleteSecureStorage(keyString));

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorStorageError;
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

/// Memory info callback - returns errorNotImplemented.
/// Memory info requires platform-specific APIs (iOS: mach_task_info, Android: ActivityManager).
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

    // Log the error from C++ layer
    // Note: For production, integrate with crash reporting (e.g., Sentry, Firebase Crashlytics)
    SDKLogger('DartBridge.ErrorTracking').error(
      'C++ error received',
      metadata: {'error_json': jsonString},
    );
  } catch (_) {
    // Ignore errors in error handling
  }
}
