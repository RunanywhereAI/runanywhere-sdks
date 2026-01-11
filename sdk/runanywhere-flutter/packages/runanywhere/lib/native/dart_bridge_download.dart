import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Download bridge for C++ download operations.
/// Matches Swift's `CppBridge+Download.swift`.
class DartBridgeDownload {
  DartBridgeDownload._();

  static final _logger = SDKLogger('DartBridge.Download');
  static final DartBridgeDownload instance = DartBridgeDownload._();

  /// Active download tasks
  final Map<String, _DownloadTask> _activeTasks = {};

  /// Start a download via C++
  Future<String?> startDownload({
    required String url,
    required String destinationPath,
    void Function(int downloaded, int total)? onProgress,
    void Function(int result, String? path)? onComplete,
  }) async {
    try {
      final lib = PlatformLoader.load();
      final startFn = lib.lookupFunction<
          Int32 Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<NativeFunction<Void Function(Int64, Int64, Pointer<Void>)>>,
            Pointer<NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>,
          ),
          int Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<NativeFunction<Void Function(Int64, Int64, Pointer<Void>)>>,
            Pointer<NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>,
          )>('rac_http_download');

      final urlPtr = url.toNativeUtf8();
      final destPtr = destinationPath.toNativeUtf8();
      final taskIdPtr = calloc<Pointer<Utf8>>();

      try {
        final result = startFn(
          urlPtr,
          destPtr,
          nullptr, // Progress callback (implement if needed)
          nullptr, // Complete callback (implement if needed)
          nullptr, // User data
          taskIdPtr,
        );

        if (result != RacResultCode.success) {
          _logger.warning('Download start failed', metadata: {'code': result});
          return null;
        }

        final taskId = taskIdPtr.value != nullptr
            ? taskIdPtr.value.toDartString()
            : null;

        if (taskId != null) {
          _activeTasks[taskId] = _DownloadTask(
            url: url,
            destinationPath: destinationPath,
            onProgress: onProgress,
            onComplete: onComplete,
          );
        }

        return taskId;
      } finally {
        calloc.free(urlPtr);
        calloc.free(destPtr);
        calloc.free(taskIdPtr);
      }
    } catch (e) {
      _logger.debug('rac_http_download not available: $e');
      return null;
    }
  }

  /// Cancel a download
  Future<bool> cancelDownload(String taskId) async {
    try {
      final lib = PlatformLoader.load();
      final cancelFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_http_download_cancel');

      final taskIdPtr = taskId.toNativeUtf8();
      try {
        final result = cancelFn(taskIdPtr);
        _activeTasks.remove(taskId);
        return result == RacResultCode.success;
      } finally {
        calloc.free(taskIdPtr);
      }
    } catch (e) {
      _logger.debug('rac_http_download_cancel not available: $e');
      return false;
    }
  }

  /// Get active download count
  int get activeDownloadCount => _activeTasks.length;
}

class _DownloadTask {
  final String url;
  final String destinationPath;
  final void Function(int downloaded, int total)? onProgress;
  final void Function(int result, String? path)? onComplete;

  _DownloadTask({
    required this.url,
    required this.destinationPath,
    this.onProgress,
    this.onComplete,
  });
}
