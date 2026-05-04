import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart' as download_pb;
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// ============================================================================
// C struct — mirrors `rac_download_progress_t` from
// include/rac/infrastructure/download/rac_download.h
// ============================================================================

/// Progress snapshot emitted by the C++ download orchestrator.
final class RacDownloadProgress extends Struct {
  @Int32()
  external int stage; // rac_download_stage_t
  @Int64()
  external int bytesDownloaded;
  @Int64()
  external int totalBytes;
  @Double()
  external double stageProgress;
  @Double()
  external double overallProgress;
  @Int32()
  external int state; // rac_download_state_t
  @Double()
  external double speed;
  @Double()
  external double estimatedTimeRemaining;
  @Int32()
  external int retryAttempt;
  @Int32()
  external int errorCode;
  external Pointer<Utf8> errorMessage;
}

/// Dart-side copy of a native progress snapshot (safe after native memory is freed).
class DownloadProgressSnapshot {
  final int stage;
  final int bytesDownloaded;
  final int totalBytes;
  final double stageProgress;
  final double overallProgress;
  final int state;
  final double speed;
  final double estimatedTimeRemaining;
  final int retryAttempt;
  final int errorCode;
  final String? errorMessage;

  const DownloadProgressSnapshot({
    required this.stage,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.stageProgress,
    required this.overallProgress,
    required this.state,
    required this.speed,
    required this.estimatedTimeRemaining,
    required this.retryAttempt,
    required this.errorCode,
    this.errorMessage,
  });
}

/// Native progress callback signature — `rac_download_progress_callback_fn`.
typedef RacDownloadProgressCallbackNative = Void Function(
    Pointer<RacDownloadProgress>, Pointer<Void>);

/// Native completion callback signature — `rac_download_complete_callback_fn`.
typedef RacDownloadCompleteCallbackNative = Void Function(
    Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Void>);

/// Download bridge for C++ download operations.
/// Matches Swift's `CppBridge+Download.swift`.
class DartBridgeDownload {
  DartBridgeDownload._();

  static final _logger = SDKLogger('DartBridge.Download');
  static final DartBridgeDownload instance = DartBridgeDownload._();

  /// Active download tasks
  final Map<String, _DownloadTask> _activeTasks = {};

  // ===========================================================================
  // Lazy download manager handle (one per process; destroyed at SDK shutdown).
  // ===========================================================================
  static Pointer<Void>? _managerHandle;

  /// Lazily create (and cache) the C++ download manager instance.
  static Pointer<Void> managerHandle() {
    final cached = _managerHandle;
    if (cached != null && cached != nullptr) return cached;

    final lib = PlatformLoader.loadCommons();
    final createFn = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
        int Function(Pointer<Void>,
            Pointer<Pointer<Void>>)>('rac_download_manager_create');

    final outHandle = calloc<Pointer<Void>>();
    try {
      final result = createFn(nullptr, outHandle);
      if (result != RacResultCode.success) {
        throw StateError(
            'rac_download_manager_create failed with code $result');
      }
      _managerHandle = outHandle.value;
      return _managerHandle!;
    } finally {
      calloc.free(outHandle);
    }
  }

  /// Invoke `rac_download_orchestrate` — C++ drives the entire state machine
  /// (path resolution, extraction, archive cleanup, registry update).
  ///
  /// `progressCallback` is the pointer from a `NativeCallable.listener`, which
  /// marshals callbacks onto the Dart isolate. `userData` is the Dart port /
  /// context pointer forwarded verbatim.
  ///
  /// Returns the C-owned `task_id` string on success, or `null` on failure.
  /// The returned pointer must be freed with `rac_free`.
  static String? orchestrateDownload({
    required String modelId,
    required String downloadUrl,
    required int framework,
    required int format,
    required int archiveStructure,
    required Pointer<NativeFunction<RacDownloadProgressCallbackNative>>
        progressCallback,
    required Pointer<NativeFunction<RacDownloadCompleteCallbackNative>>
        completeCallback,
    required Pointer<Void> userData,
  }) {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Int32,
            Int32,
            Int32,
            Pointer<NativeFunction<RacDownloadProgressCallbackNative>>,
            Pointer<NativeFunction<RacDownloadCompleteCallbackNative>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>),
        int Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            int,
            int,
            int,
            Pointer<NativeFunction<RacDownloadProgressCallbackNative>>,
            Pointer<NativeFunction<RacDownloadCompleteCallbackNative>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>)>('rac_download_orchestrate');

    final handle = managerHandle();
    final modelIdPtr = modelId.toNativeUtf8();
    final urlPtr = downloadUrl.toNativeUtf8();
    final taskIdPtr = calloc<Pointer<Utf8>>();

    try {
      final code = fn(
        handle,
        modelIdPtr,
        urlPtr,
        framework,
        format,
        archiveStructure,
        progressCallback,
        completeCallback,
        userData,
        taskIdPtr,
      );

      if (code != RacResultCode.success) {
        _logger.error(
          'rac_download_orchestrate failed',
          metadata: {'code': code, 'model': modelId},
        );
        return null;
      }
      final tid = taskIdPtr.value;
      return tid == nullptr ? null : tid.toDartString();
    } finally {
      calloc.free(modelIdPtr);
      calloc.free(urlPtr);
      calloc.free(taskIdPtr);
    }
  }

  /// Poll progress for a running download task.
  /// Returns null if the task doesn't exist or the symbol isn't available.
  static DownloadProgressSnapshot? getProgress(String taskId) {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
              Int32 Function(
                  Pointer<Void>, Pointer<Utf8>, Pointer<RacDownloadProgress>),
              int Function(
                  Pointer<Void>, Pointer<Utf8>, Pointer<RacDownloadProgress>)>(
          'rac_download_manager_get_progress');

      final handle = managerHandle();
      final tidPtr = taskId.toNativeUtf8();
      final progressPtr = calloc<RacDownloadProgress>();
      try {
        final code = fn(handle, tidPtr, progressPtr);
        if (code != RacResultCode.success) return null;
        final ref = progressPtr.ref;
        return DownloadProgressSnapshot(
          stage: ref.stage,
          bytesDownloaded: ref.bytesDownloaded,
          totalBytes: ref.totalBytes,
          stageProgress: ref.stageProgress,
          overallProgress: ref.overallProgress,
          state: ref.state,
          speed: ref.speed,
          estimatedTimeRemaining: ref.estimatedTimeRemaining,
          retryAttempt: ref.retryAttempt,
          errorCode: ref.errorCode,
          errorMessage: ref.errorMessage != nullptr
              ? ref.errorMessage.toDartString()
              : null,
        );
      } finally {
        calloc.free(tidPtr);
        calloc.free(progressPtr);
      }
    } catch (e) {
      _logger.debug('rac_download_manager_get_progress not available: $e');
      return null;
    }
  }

  /// Cancel an in-flight orchestrated download by task id.
  static bool cancelOrchestratedDownload(String taskId) {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(
              Pointer<Void>, Pointer<Utf8>)>('rac_download_manager_cancel');

      final handle = managerHandle();
      final tidPtr = taskId.toNativeUtf8();
      try {
        return fn(handle, tidPtr) == RacResultCode.success;
      } finally {
        calloc.free(tidPtr);
      }
    } catch (e) {
      _logger.debug('rac_download_manager_cancel not available: $e');
      return false;
    }
  }

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
            Pointer<
                NativeFunction<
                    Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>,
          ),
          int Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<NativeFunction<Void Function(Int64, Int64, Pointer<Void>)>>,
            Pointer<
                NativeFunction<
                    Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
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

        final taskId =
            taskIdPtr.value != nullptr ? taskIdPtr.value.toDartString() : null;

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
      final cancelFn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
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
  // Stable download proto-byte API
  // ===========================================================================

  Future<download_pb.DownloadPlanResult> planProto(
    download_pb.DownloadPlanRequest request,
  ) async {
    final result = await _callDownloadProto(
      request,
      RacNative.bindings.rac_download_plan_proto,
      download_pb.DownloadPlanResult.fromBuffer,
      'rac_download_plan_proto',
    );
    return result ??
        download_pb.DownloadPlanResult(
          canStart: false,
          errorMessage: 'Download plan proto API is unavailable',
        );
  }

  Future<download_pb.DownloadStartResult> startProto(
    download_pb.DownloadStartRequest request,
  ) async {
    final result = await _callDownloadProto(
      request,
      RacNative.bindings.rac_download_start_proto,
      download_pb.DownloadStartResult.fromBuffer,
      'rac_download_start_proto',
    );
    return result ??
        download_pb.DownloadStartResult(
          accepted: false,
          modelId: request.modelId,
          errorMessage: 'Download start proto API is unavailable',
        );
  }

  Future<download_pb.DownloadCancelResult> cancelProto(
    download_pb.DownloadCancelRequest request,
  ) async {
    final result = await _callDownloadProto(
      request,
      RacNative.bindings.rac_download_cancel_proto,
      download_pb.DownloadCancelResult.fromBuffer,
      'rac_download_cancel_proto',
    );
    return result ??
        download_pb.DownloadCancelResult(
          success: false,
          taskId: request.taskId,
          modelId: request.modelId,
          errorMessage: 'Download cancel proto API is unavailable',
        );
  }

  Future<download_pb.DownloadResumeResult> resumeProto(
    download_pb.DownloadResumeRequest request,
  ) async {
    final result = await _callDownloadProto(
      request,
      RacNative.bindings.rac_download_resume_proto,
      download_pb.DownloadResumeResult.fromBuffer,
      'rac_download_resume_proto',
    );
    return result ??
        download_pb.DownloadResumeResult(
          accepted: false,
          taskId: request.taskId,
          modelId: request.modelId,
          errorMessage: 'Download resume proto API is unavailable',
        );
  }

  Future<download_pb.DownloadProgress?> pollProgressProto(
    download_pb.DownloadSubscribeRequest request,
  ) {
    return _callDownloadProto(
      request,
      RacNative.bindings.rac_download_progress_poll_proto,
      download_pb.DownloadProgress.fromBuffer,
      'rac_download_progress_poll_proto',
      logNotFound: false,
    );
  }

  Future<T?> _callDownloadProto<T extends GeneratedMessage>(
    GeneratedMessage request,
    RacDownloadProtoDart? fn,
    T Function(List<int>) decode,
    String symbol, {
    bool logNotFound = true,
  }) async {
    if (fn == null) return null;

    final bytes = request.writeToBuffer();
    final requestPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      if (bytes.isNotEmpty) {
        requestPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      bindings.rac_proto_buffer_init(out);
      final code = fn(requestPtr, bytes.length, out);
      if (code != RacResultCode.success || out.ref.data == nullptr) {
        if (logNotFound || code != RacResultCode.errorNotFound) {
          final message = out.ref.errorMessage == nullptr
              ? 'code=$code status=${out.ref.status}'
              : out.ref.errorMessage.toDartString();
          _logger.debug('$symbol failed: $message');
        }
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
