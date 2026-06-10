// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/native/types/memory_platform_types.dart';

// =============================================================================
// Exception Return Constants (must be compile-time constants for FFI)
// =============================================================================

/// Exceptional return value for file operations that return Int32
const int _exceptionalReturnInt32 = -183; // RAC_ERROR_FILE_NOT_FOUND

/// Exceptional return value for bool operations
const int _exceptionalReturnFalse = 0;

typedef _SysctlByNameNative =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Void>,
      Pointer<Uint64>,
      Pointer<Void>,
      Uint64,
    );
typedef _SysctlByNameDart =
    int Function(
      Pointer<Utf8>,
      Pointer<Void>,
      Pointer<Uint64>,
      Pointer<Void>,
      int,
    );

typedef _PlatformServiceAvailabilityCallbackNative =
    Int32 Function(Int32 service, Pointer<Void> userData);

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
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ---------------------------------------------------------------------------
  // Platform Services (Foundation Models + System TTS/STT) state
  // ---------------------------------------------------------------------------

  /// Whether platform services availability callback has been registered.
  static bool _servicesRegistered = false;

  /// Persistent pointer for the platform services availability callback.
  static Pointer<NativeFunction<_PlatformServiceAvailabilityCallbackNative>>?
  _servicesAvailabilityCallback;

  static const int _serviceFoundationModels = 1;
  static const int _serviceSystemTts = 2;
  static const int _serviceSystemStt = 3;

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

      // ABI guard (MUST be the first two fields). rac_init rejects the adapter
      // with RAC_ERROR_ABI_VERSION_MISMATCH unless these match the commons
      // build. 1 == RAC_PLATFORM_ADAPTER_ABI_VERSION.
      adapter.ref.abiVersion = 1;
      adapter.ref.structSize = sizeOf<RacPlatformAdapterStruct>();

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

      // Clock — intentionally null. C++ falls back to std::chrono::system_clock
      // in rac_time.cpp. This is the correct design for Dart FFI, not a
      // workaround:
      //   - Pointer.fromFunction trampolines are tied to the registering
      //     isolate and crash (SIGABRT) when invoked from non-Dart threads.
      //   - NativeCallable.listener is one-way/async and cannot return an
      //     Int64 synchronously.
      //   - rac_get_current_time_ms is called from C++ worker threads
      //     (download orchestrator std::thread, OkHttp transport pool) with
      //     no isolate affinity.
      // std::chrono::system_clock yields equivalent ms timestamps to Swift's
      // Foundation Date() callback, so no platform override is needed.
      adapter.ref.nowMs = nullptr;

      // Memory info callback
      adapter.ref.getMemoryInfo =
          Pointer.fromFunction<RacGetMemoryInfoCallbackNative>(
            _platformGetMemoryInfoCallback,
            _exceptionalReturnInt32,
          );

      // HTTP download callbacks — disabled because OkHttp transport vtable
      // handles all HTTP. Pointer.fromFunction trampolines are not safe to
      // call from the C++ worker thread spawned by the download orchestrator.
      adapter.ref.httpDownload = nullptr;
      adapter.ref.httpDownloadCancel = nullptr;
      adapter.ref.extractArchive = nullptr;

      // Directory enumeration — commons uses these from the model-registry
      // refresh path (rescan_local) and the canonical RAModelInfo factory
      // (is_downloaded gating for multi-file artifacts). Both are invoked
      // from the Dart-owned isolate that initiates the corresponding SDK
      // public API call, so Pointer.fromFunction trampolines are safe here
      // (same constraint as file_exists / file_read above). See
      // rac_platform_adapter.h doc-block for cross-SDK status.
      adapter.ref.fileListDirectory =
          Pointer.fromFunction<RacFileListDirectoryCallbackNative>(
            _platformFileListDirectoryCallback,
            _exceptionalReturnInt32,
          );
      adapter.ref.isNonEmptyDirectory =
          Pointer.fromFunction<RacIsNonEmptyDirectoryCallbackNative>(
            _platformIsNonEmptyDirectoryCallback,
            _exceptionalReturnFalse,
          );

      // Vendor ID — intentionally null. Apple-only slot per
      // rac_platform_adapter.h:get_vendor_id; commons calls it from
      // rac_device_get_or_create_persistent_id() only after secure_get
      // misses. Flutter pre-populates the device-id cache in
      // dart_bridge_device.dart::_getOrCreateDeviceId() using
      // device_info_plus (identifierForVendor on iOS, generated UUID on
      // Android) and writes it through secure_set, so the commons chain
      // resolves on the secure_get branch before reaching this slot. A
      // direct FFI trampoline cannot bridge UIDevice.identifierForVendor
      // anyway because Flutter exposes it only via the async
      // device_info_plus MethodChannel, which FFI's synchronous return
      // contract cannot await.
      adapter.ref.getVendorId = nullptr;

      adapter.ref.userData = nullptr;

      // Register with C++
      final setAdapter = lib
          .lookupFunction<
            Int32 Function(Pointer<RacPlatformAdapterStruct>),
            int Function(Pointer<RacPlatformAdapterStruct>)
          >('rac_set_platform_adapter');

      final result = setAdapter(adapter);
      if (result != RacResultCode.success) {
        _logger.error(
          'Failed to register platform adapter',
          metadata: {'error_code': result},
        );
        calloc.free(adapter);
        _adapterPtr = null;
        return;
      }

      _isRegistered = true;
      _logger.debug('Platform adapter registered successfully');

      // Warm the synchronous secure-storage cache that backs secureGet.
      // flutter_secure_storage is async-only, but the FFI secure_get
      // trampoline must return synchronously, so commons reads through the
      // in-memory cache. Kick the load off here (Phase 1 entry) and await it
      // in registerServices() so the cache is populated before any C++
      // secure_get (e.g. rac_device_get_or_create_persistent_id). Without
      // this warm, every cold-start secure_get misses and commons mints a
      // fresh device UUID, breaking device-id continuity.
      unawaited(loadSecureStorageCache());

      // Note: We don't free the adapter here as C++ holds a reference to it
      // It will be valid for the lifetime of the application
    } catch (e, stack) {
      _logger.error(
        'Exception registering platform adapter',
        metadata: {'error': e.toString(), 'stack': stack.toString()},
      );
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

  // ---------------------------------------------------------------------------
  // Platform Services Registration (Foundation Models + System TTS/STT)
  // ---------------------------------------------------------------------------

  /// Whether platform services availability callback has been registered.
  static bool get servicesRegistered => _servicesRegistered;

  /// Register the platform services availability callback with C++.
  /// Matches Swift's `CppBridge.Platform.register()` callback wiring for
  /// Foundation Models / System TTS / System STT availability checks.
  static Future<void> registerServices() async {
    if (_servicesRegistered) return;

    // Guarantee the secure-storage cache is loaded before Phase 2 drives the
    // commons step-list (device registration walks secure_get). register()
    // starts this load; awaiting here closes the race for the async phase.
    await loadSecureStorageCache();

    try {
      final lib = PlatformLoader.loadCommons();

      final registerCallback = lib
          .lookupFunction<
            Int32 Function(
              Pointer<NativeFunction<Int32 Function(Int32, Pointer<Void>)>>,
            ),
            int Function(
              Pointer<NativeFunction<Int32 Function(Int32, Pointer<Void>)>>,
            )
          >('rac_platform_services_register_availability_callback');

      _servicesAvailabilityCallback ??=
          Pointer.fromFunction<_PlatformServiceAvailabilityCallbackNative>(
            _platformServiceAvailabilityCallback,
            _exceptionalReturnFalse,
          );

      final result = registerCallback(_servicesAvailabilityCallback!);
      if (result != RacResultCode.success) {
        _logger.warning(
          'Failed to register platform services availability callback',
          metadata: {'error_code': result},
        );
        return;
      }

      _servicesRegistered = true;
      _logger.debug('Platform services registered');
    } catch (e) {
      // librac_commons.so may not export
      // rac_platform_services_register_availability_callback in some
      // configurations (B-FL-1-002). Log at warning so it's visible in
      // non-debug builds, then mark as registered to avoid retry.
      _logger.warning('Platform services registration not available: $e');
      _servicesRegistered = true;
    }
  }
}

/// Platform service availability callback (Foundation Models / System TTS/STT).
/// Matches Swift's `CppBridge.Platform.register()` availability replies.
int _platformServiceAvailabilityCallback(int service, Pointer<Void> userData) {
  switch (service) {
    case DartBridgePlatform._serviceFoundationModels:
      return 0;
    case DartBridgePlatform._serviceSystemTts:
    case DartBridgePlatform._serviceSystemStt:
      return 1;
    default:
      return 0;
  }
}

// =============================================================================
// C Callback Functions (must be static top-level functions)
// =============================================================================

/// Maximum byte length to read from a C-owned log buffer.
/// Matches `thread_local char formatted[2048]` in commons/src/core/rac_logger.cpp.
/// Bounding the read prevents `toDartString()` from walking off the end of a
/// freed/unmapped buffer (SIGSEGV) if commons ever stops using the thread_local
/// buffer or if a non-rac_logger_log call site passes a temporary string.
const int _maxLogStringBytes = 2048;

/// Running count of log lines that could not be decoded — typically the
/// signature of a buffer-lifetime race between commons and the async Dart
/// listener trampoline (commons-067). Surfaced through a periodic warning so
/// operators can detect log loss instead of silently dropping it.
int _droppedLogCount = 0;

/// Emit a visibility warning every Nth drop to keep noise bounded.
const int _droppedLogWarnEvery = 32;

/// Read up to [_maxLogStringBytes] bytes from a NUL-terminated C string into a
/// Dart String, returning null on any decoding failure. Bounded so that a
/// freed buffer cannot trigger an arbitrarily long memory walk.
String? _safeReadCString(Pointer<Utf8> ptr) {
  if (ptr == nullptr) return null;
  try {
    final bytes = ptr.cast<Uint8>().asTypedList(_maxLogStringBytes);
    var len = 0;
    while (len < _maxLogStringBytes && bytes[len] != 0) {
      len++;
    }
    if (len == 0) return '';
    // `length:` avoids re-walking the buffer (strlen) inside toDartString.
    return ptr.toDartString(length: len);
  } catch (_) {
    return null;
  }
}

/// Logging callback - routes C++ logs to Dart logger.
///
/// Registered as a `NativeCallable.listener` so commons may invoke it from any
/// C++ worker thread (download orchestrator, plugin loader, engine workers)
/// without violating Dart's isolate affinity contract (`Pointer.fromFunction`
/// and `NativeCallable.isolateLocal` both SIGABRT when invoked from a
/// non-Dart-owned thread, see comments on `nowMs` / `httpDownload` above).
///
/// Lifetime contract (commons-067 mitigation):
///   - `message` is normally backed by `thread_local char formatted[2048]` in
///     `rac_logger.cpp::rac_logger_log`, so the pointer stays valid across the
///     listener's async hop on the same C thread.
///   - `category` is passed as a string literal at every commons call site
///     (`RAC_LOG_INFO("LLM", ...)`), so it lives for the binary's lifetime.
///   - The narrow remaining race is the same C thread logging twice before
///     the Dart isolate drains the queued listener invocation; the second log
///     overwrites the thread_local buffer. We bound the read to
///     `_maxLogStringBytes` so we never walk off a freed/unmapped page, and
///     when decode fails we surface a periodic synthetic warning so log loss
///     is observable instead of silent.
///
/// A full ABI-level fix (e.g. requiring commons to copy strings before
/// invoking `adapter->log`, or shipping owned `rac_proto_buffer_t`-style
/// log payloads) is tracked separately — that change touches every SDK.
void _platformLogCallback(
  int level,
  Pointer<Utf8> category,
  Pointer<Utf8> message,
  Pointer<Void> userData,
) {
  if (message == nullptr) return;

  final msgString = _safeReadCString(message);
  if (msgString == null) {
    _droppedLogCount++;
    if (_droppedLogCount % _droppedLogWarnEvery == 1) {
      // Surface via a sentinel logger so operators can grep for it. Using
      // SDKLogger here is safe because we are already on the isolate's
      // event loop (listener callbacks run there) and SDKLogger never re-
      // enters the C platform-adapter log slot.
      SDKLogger('DartBridge.Platform').warning(
        'Dropped C++ log line: buffer-lifetime race with NativeCallable '
        '(total dropped: $_droppedLogCount). See commons-067.',
      );
    }
    return;
  }
  if (msgString.isEmpty) return;

  final categoryString = _safeReadCString(category) ?? 'RAC';
  final logger = SDKLogger(categoryString.isEmpty ? 'RAC' : categoryString);

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
}

/// File exists callback
int _platformFileExistsCallback(Pointer<Utf8> path, Pointer<Void> userData) {
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
  Pointer<Size> outSize,
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
int _platformFileDeleteCallback(Pointer<Utf8> path, Pointer<Void> userData) {
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

/// In-flight async cache load, so concurrent callers (register +
/// registerServices) await the same future instead of issuing two readAll()s.
Future<void>? _secureStorageCacheLoad;

/// Pending fire-and-forget persistence operations. [drainPendingSecureWrites]
/// awaits these so a shutdown path can flush before the process exits,
/// otherwise a force-quit between the cache update and the async write would
/// silently drop the last secure_set/secure_delete (e.g. an auth token).
final Set<Future<void>> _pendingSecureWrites = {};

/// Load secure storage cache (called during platform-adapter registration).
/// Idempotent: returns the same in-flight future on concurrent calls and a
/// completed future once loaded.
Future<void> loadSecureStorageCache() {
  return _secureStorageCacheLoad ??= () async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
      final all = await storage.readAll();
      _secureStorageCache.addAll(all);
    } catch (_) {
      // Ignore errors - cache will be empty
    }
  }();
}

/// Await all in-flight secure-storage persistence operations. Callers on the
/// shutdown path should await this so the last secure_set/secure_delete is
/// durably written before the process exits.
Future<void> drainPendingSecureWrites() async {
  while (_pendingSecureWrites.isNotEmpty) {
    await Future.wait(_pendingSecureWrites.toList());
  }
}

/// Track a fire-and-forget persistence future so [drainPendingSecureWrites]
/// can flush it on shutdown, then self-remove once it settles.
void _trackPendingSecureWrite(Future<void> op) {
  late final Future<void> tracked;
  tracked = op.whenComplete(() => _pendingSecureWrites.remove(tracked));
  _pendingSecureWrites.add(tracked);
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
      // Contract: clean miss MUST return RAC_ERROR_FILE_NOT_FOUND so commons
      // (e.g. rac_device_get_or_create_persistent_id) can distinguish a
      // benign cache miss from a real keychain failure. See
      // sdk/runanywhere-commons/include/rac/core/rac_platform_adapter.h.
      return RacResultCode.errorFileNotFound;
    }

    // Allocate and copy string
    final cString = value.toNativeUtf8();
    outValue.value = cString;

    return RacResultCode.success;
  } catch (_) {
    // Contract: real failures MUST NOT collide with the not-found code.
    return RacResultCode.errorSecureStorageFailed;
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

    // Schedule async write; tracked so drainPendingSecureWrites() can flush
    // it on shutdown before a force-quit drops it.
    _trackPendingSecureWrite(_writeSecureStorage(keyString, valueString));

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorStorageError;
  }
}

/// Async write to secure storage. Surfaces failures via a warning so a
/// persist error is observable instead of silently dropped (the in-memory
/// cache stays authoritative for the running process either way).
Future<void> _writeSecureStorage(String key, String value) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    await storage.write(key: key, value: value);
  } catch (e) {
    SDKLogger(
      'DartBridge.Platform',
    ).warning('Secure storage write failed; value held in cache only: $e');
  }
}

/// Secure delete callback
int _platformSecureDeleteCallback(Pointer<Utf8> key, Pointer<Void> userData) {
  if (key == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final keyString = key.toDartString();

    // Remove from cache
    _secureStorageCache.remove(keyString);

    // Schedule async delete; tracked so drainPendingSecureWrites() can flush
    // it on shutdown before a force-quit drops it.
    _trackPendingSecureWrite(_deleteSecureStorage(keyString));

    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorStorageError;
  }
}

/// Async delete from secure storage
Future<void> _deleteSecureStorage(String key) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    await storage.delete(key: key);
  } catch (_) {
    // Ignore errors
  }
}

Map<String, int>? _readProcMemInfo() {
  try {
    final memInfo = <String, int>{};
    final contents = File('/proc/meminfo').readAsLinesSync();

    for (final line in contents) {
      final match = RegExp(r'^([A-Za-z_]+):\s+(\d+)\s+kB$').firstMatch(line);
      if (match == null) {
        continue;
      }

      memInfo[match.group(1)!] = int.parse(match.group(2)!) * 1024;
    }

    return memInfo;
  } catch (_) {
    return null;
  }
}

int _getDarwinPhysicalMemoryBytes() {
  Pointer<Utf8>? namePtr;
  Pointer<Uint64>? outPtr;
  Pointer<Uint64>? sizePtr;

  try {
    final sysctlByName = DynamicLibrary.process()
        .lookupFunction<_SysctlByNameNative, _SysctlByNameDart>('sysctlbyname');

    namePtr = 'hw.memsize'.toNativeUtf8();
    outPtr = calloc<Uint64>();
    sizePtr = calloc<Uint64>()..value = sizeOf<Uint64>();

    final result = sysctlByName(
      namePtr,
      outPtr.cast<Void>(),
      sizePtr,
      nullptr,
      0,
    );
    if (result == 0 && sizePtr.value >= sizeOf<Uint64>()) {
      return outPtr.value;
    }
  } catch (_) {
    // Fall through to the generic RSS-based estimate below.
  } finally {
    if (namePtr != null) {
      calloc.free(namePtr);
    }
    if (outPtr != null) {
      calloc.free(outPtr);
    }
    if (sizePtr != null) {
      calloc.free(sizePtr);
    }
  }

  return 0;
}

int _getTotalMemoryBytes(int usedBytes) {
  if (Platform.isAndroid) {
    final memInfo = _readProcMemInfo();
    final totalBytes = memInfo?['MemTotal'] ?? 0;
    if (totalBytes > 0) {
      return totalBytes;
    }
  }

  if (Platform.isIOS || Platform.isMacOS) {
    final totalBytes = _getDarwinPhysicalMemoryBytes();
    if (totalBytes > 0) {
      return totalBytes;
    }
  }

  final peakBytes = ProcessInfo.maxRss;
  return peakBytes > usedBytes ? peakBytes : usedBytes;
}

int _getAvailableMemoryBytes(int totalBytes, int usedBytes) {
  if (Platform.isAndroid) {
    final memInfo = _readProcMemInfo();
    final availableBytes = memInfo?['MemAvailable'] ?? 0;
    if (availableBytes > 0) {
      return availableBytes > totalBytes ? totalBytes : availableBytes;
    }
  }

  if (totalBytes <= usedBytes) {
    return 0;
  }

  return totalBytes - usedBytes;
}

/// Memory info callback - returns best-effort process and device RAM metrics.
int _platformGetMemoryInfoCallback(
  Pointer<Void> outInfo,
  Pointer<Void> userData,
) {
  if (outInfo == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  final usedBytes = ProcessInfo.currentRss;
  final totalBytes = _getTotalMemoryBytes(usedBytes);
  final availableBytes = _getAvailableMemoryBytes(totalBytes, usedBytes);
  final memoryInfo = outInfo.cast<RacMemoryInfoStruct>().ref;

  memoryInfo.totalBytes = totalBytes;
  memoryInfo.availableBytes = availableBytes;
  memoryInfo.usedBytes = usedBytes;

  return RacResultCode.success;
}

// =============================================================================
// DIRECTORY ENUMERATION (Platform Adapter)
// =============================================================================

/// `rac_file_list_directory_fn` — enumerate directory entries into the
/// caller-provided array. Implements the two-call semantics documented on
/// the C typedef: pass `outEntries == NULL` to query capacity, then call
/// again with an allocated array.
///
/// Truncation contract (per `rac_directory_entry_t::name`): entries whose
/// UTF-8 byte length (+ NUL) exceeds [RAC_DIRECTORY_ENTRY_NAME_MAX] MUST be
/// skipped, not truncated, to avoid producing half-names that alias other
/// artifacts. We emit a RAC_LOG_WARN-equivalent log line via SDKLogger so
/// operators can detect skips.
int _platformFileListDirectoryCallback(
  Pointer<Utf8> dirPath,
  Pointer<Void> outEntries,
  Pointer<Size> inOutCount,
  Pointer<Void> userData,
) {
  if (dirPath == nullptr || inOutCount == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final pathString = dirPath.toDartString();
    final dir = Directory(pathString);
    if (!dir.existsSync()) {
      return RacResultCode.errorFileNotFound;
    }

    // Collect entries up front so capacity and fill calls observe the same
    // snapshot. `listSync` is synchronous, hidden entries (.* / .. / .) are
    // already filtered by dart:io for FileSystemEntity.
    final entries = dir.listSync(followLinks: false);

    // Filter out oversized names per the truncation contract; track skips.
    final retained = <_DartDirectoryEntry>[];
    var skipped = 0;
    for (final entity in entries) {
      final basename = entity.path.split(Platform.pathSeparator).last;
      final encoded = utf8.encode(basename);
      // +1 for NUL terminator must fit in the inline name buffer.
      if (encoded.length + 1 > RAC_DIRECTORY_ENTRY_NAME_MAX) {
        skipped++;
        continue;
      }
      final isDir = entity is Directory;
      var sizeBytes = 0;
      if (entity is File) {
        try {
          sizeBytes = entity.lengthSync();
        } catch (_) {
          sizeBytes = 0;
        }
      }
      retained.add(_DartDirectoryEntry(encoded, isDir, sizeBytes));
    }

    if (skipped > 0) {
      SDKLogger('PlatformAdapter').warning(
        'Skipped $skipped directory entries in $pathString: name longer '
        'than $RAC_DIRECTORY_ENTRY_NAME_MAX bytes (truncation contract).',
      );
    }

    if (outEntries == nullptr) {
      // Capacity query: write total entry count, do not touch entries array.
      inOutCount.value = retained.length;
      return RacResultCode.success;
    }

    final capacity = inOutCount.value;
    final count = capacity < retained.length ? capacity : retained.length;
    final entriesPtr = outEntries.cast<RacDirectoryEntryStruct>();
    for (var i = 0; i < count; i++) {
      final entry = retained[i];
      final slot = (entriesPtr + i).ref;
      // Copy NUL-terminated UTF-8 into the inline name buffer; remaining
      // bytes were zero-initialized by the caller's `calloc` / `memset`,
      // but we still write the NUL explicitly to be defensive.
      for (var j = 0; j < entry.utf8Name.length; j++) {
        slot.name[j] = entry.utf8Name[j];
      }
      slot.name[entry.utf8Name.length] = 0;
      slot.isDir = entry.isDir ? RAC_TRUE : RAC_FALSE;
      slot.sizeBytes = entry.sizeBytes;
    }
    inOutCount.value = count;
    return RacResultCode.success;
  } catch (e) {
    SDKLogger('PlatformAdapter').warning('file_list_directory failed: $e');
    return RacResultCode.errorFileReadFailed;
  }
}

/// `is_non_empty_directory` — RAC_TRUE iff `path` is a directory containing
/// at least one entry. Used by `rac_model_info_make_proto` to compute the
/// `is_downloaded` field for directory-based (multi-file) artifacts without
/// forcing the SDK to enumerate the directory itself.
int _platformIsNonEmptyDirectoryCallback(
  Pointer<Utf8> path,
  Pointer<Void> userData,
) {
  if (path == nullptr) {
    return RAC_FALSE;
  }
  try {
    final pathString = path.toDartString();
    final dir = Directory(pathString);
    if (!dir.existsSync()) {
      return RAC_FALSE;
    }
    // Cheap probe: `listSync` returns an empty list for empty directories
    // and dart:io filters `.` / `..`. We short-circuit on the first entry
    // by using an iterator-style listing.
    final iterator = dir.listSync(followLinks: false).iterator;
    return iterator.moveNext() ? RAC_TRUE : RAC_FALSE;
  } catch (_) {
    return RAC_FALSE;
  }
}

class _DartDirectoryEntry {
  _DartDirectoryEntry(this.utf8Name, this.isDir, this.sizeBytes);
  final List<int> utf8Name;
  final bool isDir;
  final int sizeBytes;
}

// =============================================================================
// HTTP DOWNLOAD (Platform Adapter)
// =============================================================================

int _httpDownloadCounter = 0;

// ignore: unused_element
int _platformHttpDownloadCallback(
  Pointer<Utf8> url,
  Pointer<Utf8> destinationPath,
  Pointer<NativeFunction<RacHttpProgressCallbackNative>> progressCallback,
  Pointer<NativeFunction<RacHttpCompleteCallbackNative>> completeCallback,
  Pointer<Void> callbackUserData,
  Pointer<Pointer<Utf8>> outTaskId,
  Pointer<Void> userData,
) {
  try {
    if (url == nullptr || destinationPath == nullptr || outTaskId == nullptr) {
      return RacResultCode.errorInvalidParameter;
    }

    final urlString = url.toDartString();
    final destinationString = destinationPath.toDartString();
    if (urlString.isEmpty || destinationString.isEmpty) {
      return RacResultCode.errorInvalidParameter;
    }

    final taskId = 'http_${_httpDownloadCounter++}';
    outTaskId.value = taskId.toNativeUtf8();

    final progressAddress = progressCallback == nullptr
        ? 0
        : progressCallback.address;
    final completeAddress = completeCallback == nullptr
        ? 0
        : completeCallback.address;
    final userDataAddress = callbackUserData.address;

    unawaited(
      Isolate.spawn(_httpDownloadIsolateEntry, <dynamic>[
        urlString,
        destinationString,
        progressAddress,
        completeAddress,
        userDataAddress,
      ]),
    );
    return RacResultCode.success;
  } catch (_) {
    return RacResultCode.errorDownloadFailed;
  }
}

// ignore: unused_element
int _platformHttpDownloadCancelCallback(
  Pointer<Utf8> taskId,
  Pointer<Void> userData,
) {
  return RacResultCode.errorNotSupported;
}

Future<void> _performHttpDownloadIsolate(
  String url,
  String destinationPath,
  void Function(int, int, Pointer<Void>)? progressCallback,
  void Function(int, Pointer<Utf8>, Pointer<Void>)? completeCallback,
  Pointer<Void> callbackUserData,
) async {
  var result = RacResultCode.errorDownloadFailed;
  String? finalPath;
  File? tempFile;
  HttpClient? client;

  try {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      result = RacResultCode.errorInvalidParameter;
      return;
    }

    client = HttpClient();
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      result = RacResultCode.errorDownloadFailed;
      return;
    }

    final totalBytes = response.contentLength > 0 ? response.contentLength : 0;
    final destFile = File(destinationPath);
    await destFile.parent.create(recursive: true);
    final temp = File('${destFile.path}.part');
    tempFile = temp;
    if (await temp.exists()) {
      await temp.delete();
    }

    final sink = temp.openWrite();
    var downloaded = 0;
    var lastReported = 0;
    const reportThreshold = 256 * 1024;

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (progressCallback != null &&
            downloaded - lastReported >= reportThreshold) {
          progressCallback(downloaded, totalBytes, callbackUserData);
          lastReported = downloaded;
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (await temp.exists()) {
      if (await destFile.exists()) {
        await destFile.delete();
      }
      try {
        await temp.rename(destFile.path);
      } catch (_) {
        await temp.copy(destFile.path);
        await temp.delete();
      }
    }

    if (progressCallback != null) {
      progressCallback(downloaded, totalBytes, callbackUserData);
    }

    finalPath = destFile.path;
    result = RacResultCode.success;
  } catch (_) {
    result = RacResultCode.errorDownloadFailed;
  } finally {
    client?.close(force: true);

    if (result != RacResultCode.success && tempFile != null) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore cleanup errors
      }
    }

    if (completeCallback != null) {
      if (finalPath != null) {
        final pathPtr = finalPath.toNativeUtf8();
        completeCallback(result, pathPtr, callbackUserData);
        calloc.free(pathPtr);
      } else {
        completeCallback(result, nullptr, callbackUserData);
      }
    }
  }
}

// ignore: avoid_void_async - required signature for Isolate.spawn entry point
void _httpDownloadIsolateEntry(List<dynamic> args) async {
  final url = args[0] as String;
  final destinationPath = args[1] as String;
  final progressAddress = args[2] as int;
  final completeAddress = args[3] as int;
  final userDataAddress = args[4] as int;

  final progressCallback = progressAddress == 0
      ? null
      : Pointer<NativeFunction<RacHttpProgressCallbackNative>>.fromAddress(
          progressAddress,
        ).asFunction<void Function(int, int, Pointer<Void>)>();
  final completeCallback = completeAddress == 0
      ? null
      : Pointer<NativeFunction<RacHttpCompleteCallbackNative>>.fromAddress(
          completeAddress,
        ).asFunction<void Function(int, Pointer<Utf8>, Pointer<Void>)>();
  final userDataPtr = Pointer<Void>.fromAddress(userDataAddress);

  await _performHttpDownloadIsolate(
    url,
    destinationPath,
    progressCallback,
    completeCallback,
    userDataPtr,
  );
}
