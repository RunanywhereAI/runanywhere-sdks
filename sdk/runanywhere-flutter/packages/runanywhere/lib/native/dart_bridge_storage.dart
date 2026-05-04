// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/storage_types.pb.dart' as storage_pb;
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Storage bridge for C++ storage operations.
/// Matches Swift's `CppBridge+Storage.swift`.
class DartBridgeStorage {
  DartBridgeStorage._();

  static final _logger = SDKLogger('DartBridge.Storage');
  static final DartBridgeStorage instance = DartBridgeStorage._();

  static Pointer<RacStorageCallbacks>? _callbacksPtr;
  static Pointer<Void>? _analyzerHandle;

  /// Get value from storage
  Future<String?> get(String key) async {
    try {
      final lib = PlatformLoader.load();
      final getFn = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('rac_storage_get');

      final keyPtr = key.toNativeUtf8();
      try {
        final result = getFn(keyPtr);
        if (result == nullptr) return null;
        return result.toDartString();
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_get not available: $e');
      return null;
    }
  }

  /// Set value in storage
  Future<bool> set(String key, String value) async {
    try {
      final lib = PlatformLoader.load();
      final setFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)>('rac_storage_set');

      final keyPtr = key.toNativeUtf8();
      final valuePtr = value.toNativeUtf8();
      try {
        final result = setFn(keyPtr, valuePtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(keyPtr);
        calloc.free(valuePtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_set not available: $e');
      return false;
    }
  }

  /// Delete value from storage
  Future<bool> delete(String key) async {
    try {
      final lib = PlatformLoader.load();
      final deleteFn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_storage_delete');

      final keyPtr = key.toNativeUtf8();
      try {
        final result = deleteFn(keyPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_delete not available: $e');
      return false;
    }
  }

  /// Check if key exists in storage
  Future<bool> exists(String key) async {
    try {
      final lib = PlatformLoader.load();
      final existsFn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_storage_exists');

      final keyPtr = key.toNativeUtf8();
      try {
        return existsFn(keyPtr) != 0;
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_exists not available: $e');
      return false;
    }
  }

  /// Clear all storage
  Future<bool> clear() async {
    try {
      final lib = PlatformLoader.load();
      final clearFn = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_storage_clear');

      final result = clearFn();
      return result == RacResultCode.success;
    } catch (e) {
      _logger.debug('rac_storage_clear not available: $e');
      return false;
    }
  }

  // =========================================================================
  // Stable storage analyzer proto-byte API
  // =========================================================================

  Future<storage_pb.StorageInfoResult> infoProto([
    storage_pb.StorageInfoRequest? request,
  ]) async {
    final result = await _callStorageProto(
      request ?? storage_pb.StorageInfoRequest(),
      RacNative.bindings.rac_storage_analyzer_info_proto,
      storage_pb.StorageInfoResult.fromBuffer,
      'rac_storage_analyzer_info_proto',
    );
    return result ??
        storage_pb.StorageInfoResult(
          success: false,
          errorMessage: 'Storage analyzer info proto API is unavailable',
        );
  }

  Future<storage_pb.StorageAvailabilityResult> availabilityProto(
    storage_pb.StorageAvailabilityRequest request,
  ) async {
    final result = await _callStorageProto(
      request,
      RacNative.bindings.rac_storage_analyzer_availability_proto,
      storage_pb.StorageAvailabilityResult.fromBuffer,
      'rac_storage_analyzer_availability_proto',
    );
    return result ??
        storage_pb.StorageAvailabilityResult(
          success: false,
          errorMessage:
              'Storage analyzer availability proto API is unavailable',
        );
  }

  Future<storage_pb.StorageDeletePlan> deletePlanProto(
    storage_pb.StorageDeletePlanRequest request,
  ) async {
    final result = await _callStorageProto(
      request,
      RacNative.bindings.rac_storage_analyzer_delete_plan_proto,
      storage_pb.StorageDeletePlan.fromBuffer,
      'rac_storage_analyzer_delete_plan_proto',
    );
    return result ??
        storage_pb.StorageDeletePlan(
          errorMessage: 'Storage analyzer delete-plan proto API is unavailable',
        );
  }

  Future<storage_pb.StorageDeleteResult> deleteProto(
    storage_pb.StorageDeleteRequest request,
  ) async {
    final result = await _callStorageProto(
      request,
      RacNative.bindings.rac_storage_analyzer_delete_proto,
      storage_pb.StorageDeleteResult.fromBuffer,
      'rac_storage_analyzer_delete_proto',
    );
    return result ??
        storage_pb.StorageDeleteResult(
          success: false,
          errorMessage: 'Storage analyzer delete proto API is unavailable',
        );
  }

  Future<T?> _callStorageProto<T extends GeneratedMessage>(
    GeneratedMessage request,
    RacStorageProtoDart? fn,
    T Function(List<int>) decode,
    String symbol,
  ) async {
    if (fn == null) return null;

    final analyzer = _ensureAnalyzer();
    final registry = DartBridgeModelRegistry.instance.nativeHandle;
    if (analyzer == null || analyzer == nullptr || registry == null) {
      _logger.debug('$symbol unavailable: analyzer or registry not ready');
      return null;
    }

    final bytes = request.writeToBuffer();
    final requestPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      if (bytes.isNotEmpty) {
        requestPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      bindings.rac_proto_buffer_init(out);
      final code = fn(analyzer, registry, requestPtr, bytes.length, out);
      if (code != RacResultCode.success || out.ref.data == nullptr) {
        final message = out.ref.errorMessage == nullptr
            ? 'code=$code status=${out.ref.status}'
            : out.ref.errorMessage.toDartString();
        _logger.debug('$symbol failed: $message');
        return null;
      }
      final resultBytes =
          out.ref.data.asTypedList(out.ref.size).toList(growable: false);
      return decode(resultBytes);
    } catch (e) {
      _logger.debug('$symbol error: $e');
      return null;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(requestPtr);
      calloc.free(out);
    }
  }

  Pointer<Void>? _ensureAnalyzer() {
    final cached = _analyzerHandle;
    if (cached != null && cached != nullptr) return cached;

    final bindings = RacNative.bindings;
    final createFn = bindings.rac_storage_analyzer_create;
    if (createFn == null) return null;

    _callbacksPtr ??= _createCallbacks();
    final outHandle = calloc<Pointer<Void>>();
    try {
      final code = createFn(_callbacksPtr!, outHandle);
      if (code != RacResultCode.success || outHandle.value == nullptr) {
        _logger.debug('rac_storage_analyzer_create failed: code=$code');
        return null;
      }
      _analyzerHandle = outHandle.value;
      return _analyzerHandle;
    } finally {
      calloc.free(outHandle);
    }
  }

  static Pointer<RacStorageCallbacks> _createCallbacks() {
    final ptr = calloc<RacStorageCallbacks>();
    ptr.ref
      ..calculateDirSize =
          Pointer.fromFunction<RacStorageCalculateDirSizeNative>(
              _calculateDirSize, -1)
      ..getFileSize =
          Pointer.fromFunction<RacStorageGetFileSizeNative>(_getFileSize, -1)
      ..pathExists =
          Pointer.fromFunction<RacStoragePathExistsNative>(_pathExists, 0)
      ..getAvailableSpace =
          Pointer.fromFunction<RacStorageGetSpaceNative>(_getAvailableSpace, 0)
      ..getTotalSpace =
          Pointer.fromFunction<RacStorageGetSpaceNative>(_getTotalSpace, 0)
      ..deletePath =
          Pointer.fromFunction<RacStorageDeletePathNative>(_deletePath, -187)
      ..isModelLoaded =
          Pointer.fromFunction<RacStorageIsModelLoadedNative>(_isModelLoaded, 0)
      ..unloadModel =
          Pointer.fromFunction<RacStorageUnloadModelNative>(_unloadModel, 0)
      ..userData = nullptr;
    return ptr;
  }
}

int _calculateDirSize(Pointer<Utf8> path, Pointer<Void> userData) {
  try {
    final entity = FileSystemEntity.typeSync(path.toDartString());
    if (entity == FileSystemEntityType.file) {
      return File(path.toDartString()).lengthSync();
    }
    if (entity != FileSystemEntityType.directory) return 0;
    var total = 0;
    for (final child
        in Directory(path.toDartString()).listSync(recursive: true)) {
      if (child is File) {
        try {
          total += child.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  } catch (_) {
    return -1;
  }
}

int _getFileSize(Pointer<Utf8> path, Pointer<Void> userData) {
  try {
    final file = File(path.toDartString());
    return file.existsSync() ? file.lengthSync() : -1;
  } catch (_) {
    return -1;
  }
}

int _pathExists(
  Pointer<Utf8> path,
  Pointer<Int32> outIsDirectory,
  Pointer<Void> userData,
) {
  try {
    final type = FileSystemEntity.typeSync(path.toDartString());
    if (type == FileSystemEntityType.notFound) return 0;
    if (outIsDirectory != nullptr) {
      outIsDirectory.value = type == FileSystemEntityType.directory ? 1 : 0;
    }
    return 1;
  } catch (_) {
    return 0;
  }
}

int _getAvailableSpace(Pointer<Void> userData) => 0;

int _getTotalSpace(Pointer<Void> userData) => 0;

int _deletePath(Pointer<Utf8> path, int recursive, Pointer<Void> userData) {
  try {
    final entity = FileSystemEntity.typeSync(path.toDartString());
    if (entity == FileSystemEntityType.notFound) return RacResultCode.success;
    if (entity == FileSystemEntityType.directory) {
      Directory(path.toDartString()).deleteSync(recursive: recursive != 0);
    } else {
      File(path.toDartString()).deleteSync();
    }
    return RacResultCode.success;
  } catch (_) {
    return -187;
  }
}

int _isModelLoaded(
  Pointer<Utf8> modelId,
  Pointer<Int32> outIsLoaded,
  Pointer<Void> userData,
) {
  if (outIsLoaded != nullptr) outIsLoaded.value = 0;
  return RacResultCode.success;
}

int _unloadModel(Pointer<Utf8> modelId, Pointer<Void> userData) =>
    RacResultCode.success;
