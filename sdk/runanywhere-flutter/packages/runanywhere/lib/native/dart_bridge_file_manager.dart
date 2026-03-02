// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// Exception Return Constants (must be compile-time constants for FFI)
// =============================================================================

const int _errorDirectoryCreationFailed = -189;
const int _errorDeleteFailed = -187;
const int _errorFileNotFound = -183;
const int _falseReturn = 0;
const int _negativeReturn = -1;

// =============================================================================
// File Manager Bridge
// =============================================================================

/// File manager bridge to C++ rac_file_manager.
/// C++ owns business logic; Dart provides thin I/O callbacks.
/// Matches iOS CppBridge+FileManager.swift / Kotlin CppBridgeFileManager.kt.
class DartBridgeFileManager {
  DartBridgeFileManager._();

  static final _logger = SDKLogger('DartBridge.FileManager');
  static final DartBridgeFileManager instance = DartBridgeFileManager._();

  static bool _isRegistered = false;
  static Pointer<RacFileCallbacksStruct>? _callbacksPtr;

  /// Register file manager callbacks. Call during SDK init.
  static void register() {
    if (_isRegistered) return;

    _callbacksPtr = calloc<RacFileCallbacksStruct>();
    final cb = _callbacksPtr!;

    cb.ref.createDirectory =
        Pointer.fromFunction<RacFmCreateDirectoryNative>(
            _createDirectoryCallback, _errorDirectoryCreationFailed);
    cb.ref.deletePath = Pointer.fromFunction<RacFmDeletePathNative>(
        _deletePathCallback, _errorDeleteFailed);
    cb.ref.listDirectory =
        Pointer.fromFunction<RacFmListDirectoryNative>(
            _listDirectoryCallback, _errorFileNotFound);
    cb.ref.freeEntries = Pointer.fromFunction<RacFmFreeEntriesNative>(
        _freeEntriesCallback);
    cb.ref.pathExists = Pointer.fromFunction<RacFmPathExistsNative>(
        _pathExistsCallback, _falseReturn);
    cb.ref.getFileSize = Pointer.fromFunction<RacFmGetFileSizeNative>(
        _getFileSizeCallback, _negativeReturn);
    cb.ref.getAvailableSpace =
        Pointer.fromFunction<RacFmGetAvailableSpaceNative>(
            _getAvailableSpaceCallback, 0);
    cb.ref.getTotalSpace = Pointer.fromFunction<RacFmGetTotalSpaceNative>(
        _getTotalSpaceCallback, 0);
    cb.ref.userData = nullptr;

    _isRegistered = true;
    _logger.debug('File manager callbacks registered');
  }

  /// Cleanup
  static void unregister() {
    if (_callbacksPtr != null) {
      calloc.free(_callbacksPtr!);
      _callbacksPtr = null;
    }
    _isRegistered = false;
  }

  // =========================================================================
  // Public API
  // =========================================================================

  /// Create directory structure (Models, Cache, Temp, Downloads).
  static bool createDirectoryStructure() {
    final fn = _lookup<Int32 Function(Pointer<RacFileCallbacksStruct>),
        int Function(Pointer<RacFileCallbacksStruct>)>(
        'rac_file_manager_create_directory_structure');
    if (fn == null || _callbacksPtr == null) return false;
    return fn(_callbacksPtr!) == RacResultCode.success;
  }

  /// Calculate directory size recursively.
  static int calculateDirectorySize(String path) {
    final fn = _lookup<
        Int32 Function(
            Pointer<RacFileCallbacksStruct>, Pointer<Utf8>, Pointer<Int64>),
        int Function(Pointer<RacFileCallbacksStruct>, Pointer<Utf8>,
            Pointer<Int64>)>('rac_file_manager_calculate_dir_size');
    if (fn == null || _callbacksPtr == null) return 0;

    final pathPtr = path.toNativeUtf8();
    final sizePtr = calloc<Int64>();
    try {
      fn(_callbacksPtr!, pathPtr, sizePtr);
      return sizePtr.value;
    } finally {
      calloc.free(pathPtr);
      calloc.free(sizePtr);
    }
  }

  /// Get total models storage used.
  static int modelsStorageUsed() {
    final fn = _lookup<
        Int32 Function(Pointer<RacFileCallbacksStruct>, Pointer<Int64>),
        int Function(
            Pointer<RacFileCallbacksStruct>, Pointer<Int64>)>(
        'rac_file_manager_models_storage_used');
    if (fn == null || _callbacksPtr == null) return 0;

    final sizePtr = calloc<Int64>();
    try {
      fn(_callbacksPtr!, sizePtr);
      return sizePtr.value;
    } finally {
      calloc.free(sizePtr);
    }
  }

  /// Clear cache directory.
  static bool clearCache() {
    final fn = _lookup<Int32 Function(Pointer<RacFileCallbacksStruct>),
        int Function(Pointer<RacFileCallbacksStruct>)>(
        'rac_file_manager_clear_cache');
    if (fn == null || _callbacksPtr == null) return false;
    return fn(_callbacksPtr!) == RacResultCode.success;
  }

  /// Clear temp directory.
  static bool clearTemp() {
    final fn = _lookup<Int32 Function(Pointer<RacFileCallbacksStruct>),
        int Function(Pointer<RacFileCallbacksStruct>)>(
        'rac_file_manager_clear_temp');
    if (fn == null || _callbacksPtr == null) return false;
    return fn(_callbacksPtr!) == RacResultCode.success;
  }

  /// Get cache size.
  static int cacheSize() {
    final fn = _lookup<
        Int32 Function(Pointer<RacFileCallbacksStruct>, Pointer<Int64>),
        int Function(
            Pointer<RacFileCallbacksStruct>, Pointer<Int64>)>(
        'rac_file_manager_cache_size');
    if (fn == null || _callbacksPtr == null) return 0;

    final sizePtr = calloc<Int64>();
    try {
      fn(_callbacksPtr!, sizePtr);
      return sizePtr.value;
    } finally {
      calloc.free(sizePtr);
    }
  }

  /// Delete a model folder.
  static bool deleteModel(String modelId, int framework) {
    final fn = _lookup<
        Int32 Function(
            Pointer<RacFileCallbacksStruct>, Pointer<Utf8>, Int32),
        int Function(Pointer<RacFileCallbacksStruct>, Pointer<Utf8>,
            int)>('rac_file_manager_delete_model');
    if (fn == null || _callbacksPtr == null) return false;

    final modelIdPtr = modelId.toNativeUtf8();
    try {
      return fn(_callbacksPtr!, modelIdPtr, framework) ==
          RacResultCode.success;
    } finally {
      calloc.free(modelIdPtr);
    }
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  static F? _lookup<T extends Function, F extends Function>(String name) {
    try {
      final lib = PlatformLoader.loadCommons();
      return lib.lookupFunction<T, F>(name);
    } catch (e) {
      _logger.debug('$name not available: $e');
      return null;
    }
  }
}

// =============================================================================
// C Callbacks (Platform I/O)
// =============================================================================

int _createDirectoryCallback(
    Pointer<Utf8> path, int recursive, Pointer<Void> userData) {
  try {
    final dir = Directory(path.toDartString());
    if (recursive != 0) {
      dir.createSync(recursive: true);
    } else {
      dir.createSync();
    }
    return RacResultCode.success;
  } catch (_) {
    return _errorDirectoryCreationFailed;
  }
}

int _deletePathCallback(
    Pointer<Utf8> path, int recursive, Pointer<Void> userData) {
  try {
    final pathStr = path.toDartString();
    final type = FileSystemEntity.typeSync(pathStr);
    if (type == FileSystemEntityType.notFound) return RacResultCode.success;

    if (type == FileSystemEntityType.directory) {
      Directory(pathStr).deleteSync(recursive: recursive != 0);
    } else {
      File(pathStr).deleteSync();
    }
    return RacResultCode.success;
  } catch (_) {
    return _errorDeleteFailed;
  }
}

int _listDirectoryCallback(
  Pointer<Utf8> path,
  Pointer<Pointer<Pointer<Utf8>>> outEntries,
  Pointer<Size> outCount,
  Pointer<Void> userData,
) {
  try {
    final dir = Directory(path.toDartString());
    if (!dir.existsSync()) {
      outEntries.value = nullptr;
      outCount.value = 0;
      return _errorFileNotFound;
    }

    final contents = dir.listSync();
    final count = contents.length;

    final entries = calloc<Pointer<Utf8>>(count);
    for (var i = 0; i < count; i++) {
      final name = contents[i].uri.pathSegments.last;
      entries[i] = name.toNativeUtf8();
    }

    outEntries.value = entries;
    outCount.value = count;
    return RacResultCode.success;
  } catch (_) {
    outEntries.value = nullptr;
    outCount.value = 0;
    return _errorFileNotFound;
  }
}

void _freeEntriesCallback(
    Pointer<Pointer<Utf8>> entries, int count, Pointer<Void> userData) {
  if (entries == nullptr) return;
  for (var i = 0; i < count; i++) {
    if (entries[i] != nullptr) {
      calloc.free(entries[i]);
    }
  }
  calloc.free(entries);
}

int _pathExistsCallback(
    Pointer<Utf8> path, Pointer<Int32> outIsDirectory, Pointer<Void> userData) {
  try {
    final pathStr = path.toDartString();
    final type = FileSystemEntity.typeSync(pathStr);
    if (type == FileSystemEntityType.notFound) return RAC_FALSE;

    if (outIsDirectory != nullptr) {
      outIsDirectory.value =
          type == FileSystemEntityType.directory ? RAC_TRUE : RAC_FALSE;
    }
    return RAC_TRUE;
  } catch (_) {
    return RAC_FALSE;
  }
}

int _getFileSizeCallback(Pointer<Utf8> path, Pointer<Void> userData) {
  try {
    final file = File(path.toDartString());
    if (file.existsSync()) {
      return file.lengthSync();
    }
    return -1;
  } catch (_) {
    return -1;
  }
}

int _getAvailableSpaceCallback(Pointer<Void> userData) {
  // Dart doesn't have a direct API for disk space.
  // Return 0 to indicate unknown (C++ will handle gracefully).
  return 0;
}

int _getTotalSpaceCallback(Pointer<Void> userData) {
  return 0;
}
