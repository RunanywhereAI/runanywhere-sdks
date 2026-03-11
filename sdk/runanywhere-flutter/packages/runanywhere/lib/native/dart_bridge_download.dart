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

  // ===========================================================================
  // Download Orchestrator Utilities (from rac_download_orchestrator.h)
  // ===========================================================================

  /// Find the actual model path after extraction.
  ///
  /// Consolidates duplicated Dart logic for scanning extracted directories.
  /// Uses C++ `rac_find_model_path_after_extraction()` which handles:
  /// - Finding .gguf, .onnx, .ort, .bin files
  /// - Nested directories (e.g., sherpa-onnx archives)
  /// - Single-file-nested pattern
  /// - Directory-based models (ONNX)
  ///
  /// [structure]: C++ archive structure constant (99 = unknown/auto-detect)
  /// [framework]: C++ inference framework constant (from RacInferenceFramework)
  /// [format]: C++ model format constant (from RacModelFormat)
  static String? findModelPathAfterExtraction({
    required String extractedDir,
    required int structure,
    required int framework,
    required int format,
  }) {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(
              Pointer<Utf8>, Int32, Int32, Int32, Pointer<Utf8>, IntPtr),
          int Function(Pointer<Utf8>, int, int, int, Pointer<Utf8>,
              int)>('rac_find_model_path_after_extraction');

      final dirPtr = extractedDir.toNativeUtf8();
      final outPath = calloc<Uint8>(4096);

      try {
        final result = fn(
            dirPtr, structure, framework, format, outPath.cast<Utf8>(), 4096);
        if (result != RacResultCode.success) return null;
        return outPath.cast<Utf8>().toDartString();
      } finally {
        calloc.free(dirPtr);
        calloc.free(outPath);
      }
    } catch (e) {
      _logger.debug('rac_find_model_path_after_extraction not available: $e');
      return null;
    }
  }

  /// Check if a download URL requires extraction.
  ///
  /// Wraps C++ `rac_download_requires_extraction()` which checks URL suffix
  /// for archive extensions (.tar.gz, .tar.bz2, .tar.xz, .zip).
  static bool downloadRequiresExtraction(String url) {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_download_requires_extraction');

      final urlPtr = url.toNativeUtf8();
      try {
        return fn(urlPtr) == RAC_TRUE;
      } finally {
        calloc.free(urlPtr);
      }
    } catch (e) {
      _logger.debug('rac_download_requires_extraction not available: $e');
      return false;
    }
  }

  /// Compute the download destination path for a model.
  ///
  /// Wraps C++ `rac_download_compute_destination()`.
  /// Returns the destination path and whether extraction is needed,
  /// or null if the computation fails.
  static ({String path, bool needsExtraction})? computeDownloadDestination({
    required String modelId,
    required String downloadUrl,
    required int framework,
    required int format,
  }) {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32, Int32,
              Pointer<Utf8>, IntPtr, Pointer<Int32>),
          int Function(Pointer<Utf8>, Pointer<Utf8>, int, int, Pointer<Utf8>,
              int, Pointer<Int32>)>('rac_download_compute_destination');

      final modelIdPtr = modelId.toNativeUtf8();
      final urlPtr = downloadUrl.toNativeUtf8();
      final outPath = calloc<Uint8>(4096);
      final outNeedsExtraction = calloc<Int32>();

      try {
        final result = fn(modelIdPtr, urlPtr, framework, format,
            outPath.cast<Utf8>(), 4096, outNeedsExtraction);
        if (result != RacResultCode.success) return null;
        return (
          path: outPath.cast<Utf8>().toDartString(),
          needsExtraction: outNeedsExtraction.value == RAC_TRUE,
        );
      } finally {
        calloc.free(modelIdPtr);
        calloc.free(urlPtr);
        calloc.free(outPath);
        calloc.free(outNeedsExtraction);
      }
    } catch (e) {
      _logger.debug('rac_download_compute_destination not available: $e');
      return null;
    }
  }
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
