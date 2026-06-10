// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart' as download_pb;
import 'package:runanywhere/native/types/basic_types.dart';

/// Download bridge for the stable generated-proto download ABI.
///
/// Commons owns download planning, state, progress, cancel/resume semantics,
/// archive policy, and registry update decisions. Flutter only serializes
/// generated request protos and decodes generated result/progress protos.
class DartBridgeDownload {
  DartBridgeDownload._();

  static final _logger = SDKLogger('DartBridge.Download');
  static final DartBridgeDownload instance = DartBridgeDownload._();

  /// Process-wide broadcast stream of `DownloadProgress` events emitted by
  /// commons via `rac_download_set_progress_proto_callback`. The stream is
  /// lazily registered the first time a subscriber asks for it. Events are
  /// shared across all consumers; per-model filtering happens in the
  /// capability layer.
  static final StreamController<download_pb.DownloadProgress>
      _progressController =
      StreamController<download_pb.DownloadProgress>.broadcast();
  // Kept alive for the process lifetime — the native callback holds a raw
  // pointer to this `NativeCallable` for the duration of the SDK process.
  // ignore: unused_field
  static NativeCallable<RacDownloadProtoProgressCallbackNative>? _callback;
  static bool _registered = false;

  // commons-081: active downloads tracked by (task_id, model_id) so the
  // wake-up listener (_onNativeProgress) can drain authoritative state via
  // rac_download_progress_poll_proto without trusting the racing ring-slot
  // pointer it was handed. Updated by startProto/resumeProto (insert) and
  // cancelProto + terminal-state observation (remove).
  static final Map<String, _ActiveDownload> _activeDownloads =
      <String, _ActiveDownload>{};

  Stream<download_pb.DownloadProgress> get progressStream {
    _ensureProgressCallbackRegistered();
    return _progressController.stream;
  }

  static void _ensureProgressCallbackRegistered() {
    if (_registered) return;

    final setCallback =
        RacNative.bindings.rac_download_set_progress_proto_callback;
    if (setCallback == null) {
      _logger.debug(
        'rac_download_set_progress_proto_callback is unavailable; '
        'falling back to caller-driven polling.',
      );
      _registered = true;
      return;
    }

    try {
      final callable =
          NativeCallable<RacDownloadProtoProgressCallbackNative>.listener(
        _onNativeProgress,
      );
      final code = setCallback(callable.nativeFunction, nullptr);
      if (code != RacResultCode.success) {
        _logger.debug(
          'rac_download_set_progress_proto_callback returned $code',
        );
        callable.close();
      } else {
        _callback = callable;
      }
    } catch (e) {
      _logger.debug('Failed to register download progress callback: $e');
    } finally {
      _registered = true;
    }
  }

  // commons-081: the commons callback hands us a pointer into a 32-slot
  // serialization ring that may have rotated by the time this listener
  // dispatches on the Dart isolate (NativeCallable.listener is async). Under
  // bursty multi-file downloads the bytes may already represent a different
  // emission or be partially overwritten — producing 'invalid tag (zero)'
  // decode errors and silently-dropped progress events. Same shape as the
  // SDKEvent wake-up race documented in dart_bridge_events.dart:193-209.
  //
  // Flutter-only mitigation: treat the pointer args as a wake-up signal and
  // drain the canonical per-task progress via rac_download_progress_poll_proto
  // for every download we are currently tracking. The poll API copies progress
  // out under task->mutex, so the bytes we ultimately emit are race-free
  // regardless of ring slot rotation. Tracked tasks are populated by
  // startProto/resumeProto and pruned on cancel + observed terminal states.
  // A cross-SDK queue ABI (rac_download_progress_poll mirroring
  // rac_sdk_event_poll) would let us drain without per-task bookkeeping but
  // requires a commons change outside this cluster's scope.
  static void _onNativeProgress(
    Pointer<Uint8> bytesPtr,
    int bytesLen,
    Pointer<Void> _,
  ) {
    if (_progressController.isClosed) {
      return;
    }
    // Pointer args intentionally unused — they reference a ring slot that
    // may already be stale. Keep params bound for the typedef-compatible
    // signature.
    if (bytesPtr == nullptr && bytesLen < 0) {
      return; // Unreachable; satisfies analyzer.
    }
    _drainActiveProgress();
  }

  static void _drainActiveProgress() {
    final poll = RacNative.bindings.rac_download_progress_poll_proto;
    if (poll == null) {
      return;
    }
    final snapshot = _activeDownloads.values.toList(growable: false);
    for (final entry in snapshot) {
      final progress = _pollProgress(entry, poll);
      if (progress == null) {
        continue;
      }
      _progressController.add(progress);
      final state = progress.state;
      if (state == download_pb.DownloadState.DOWNLOAD_STATE_COMPLETED ||
          state == download_pb.DownloadState.DOWNLOAD_STATE_FAILED ||
          state == download_pb.DownloadState.DOWNLOAD_STATE_CANCELLED) {
        _activeDownloads.remove(entry.key);
      }
    }
  }

  static download_pb.DownloadProgress? _pollProgress(
    _ActiveDownload entry,
    RacDownloadProtoDart poll,
  ) {
    final request = download_pb.DownloadSubscribeRequest(
      modelId: entry.modelId,
      taskId: entry.taskId,
    );
    final bytes = request.writeToBuffer();
    final requestPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      if (bytes.isNotEmpty) {
        requestPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      bindings.rac_proto_buffer_init(out);
      final code = poll(requestPtr, bytes.length, out);
      if (code != RacResultCode.success ||
          out.ref.status != RacResultCode.success) {
        if (code == RacResultCode.errorNotFound) {
          // Task already purged in commons (e.g. cleanup_terminal_tasks ran)
          // — drop our tracking entry so we stop polling for it.
          _activeDownloads.remove(entry.key);
        }
        return null;
      }
      if (out.ref.data == nullptr || out.ref.size == 0) {
        return null;
      }
      final resultBytes =
          out.ref.data.asTypedList(out.ref.size).toList(growable: false);
      return download_pb.DownloadProgress.fromBuffer(resultBytes);
    } catch (e) {
      _logger.debug('rac_download_progress_poll_proto drain error: $e');
      return null;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(requestPtr);
      calloc.free(out);
    }
  }

  static String _activeKey(String taskId, String modelId) =>
      '$taskId $modelId';

  static void _trackActive(String taskId, String modelId) {
    if (taskId.isEmpty && modelId.isEmpty) {
      return;
    }
    final key = _activeKey(taskId, modelId);
    _activeDownloads[key] = _ActiveDownload(key, taskId, modelId);
  }

  static void _untrackActive(String taskId, String modelId) {
    if (taskId.isEmpty && modelId.isEmpty) {
      return;
    }
    _activeDownloads.remove(_activeKey(taskId, modelId));
  }

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
    // commons-081: subscribe before commons starts emitting so the wake-up
    // listener never misses the first burst of a freshly-started download.
    _ensureProgressCallbackRegistered();
    final result = await _callDownloadProto(
      request,
      RacNative.bindings.rac_download_start_proto,
      download_pb.DownloadStartResult.fromBuffer,
      'rac_download_start_proto',
    );
    if (result != null && result.accepted) {
      _trackActive(result.taskId, result.modelId);
    }
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
    // commons-081: stop polling the cancelled task even if commons still has
    // residual progress events queued — capability layer relies on the
    // terminal-state emission, which the per-task poll also serves.
    _untrackActive(request.taskId, request.modelId);
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
    _ensureProgressCallbackRegistered();
    final result = await _callDownloadProto(
      request,
      RacNative.bindings.rac_download_resume_proto,
      download_pb.DownloadResumeResult.fromBuffer,
      'rac_download_resume_proto',
    );
    if (result != null && result.accepted) {
      _trackActive(result.taskId, result.modelId);
    }
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
      if (code != RacResultCode.success ||
          out.ref.status != RacResultCode.success) {
        if (logNotFound || code != RacResultCode.errorNotFound) {
          final message = out.ref.errorMessage == nullptr
              ? 'code=$code status=${out.ref.status}'
              : out.ref.errorMessage.toDartString();
          _logger.debug('$symbol failed: $message');
        }
        return null;
      }
      if (out.ref.data == nullptr || out.ref.size == 0) {
        return decode(const <int>[]);
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
}

class _ActiveDownload {
  const _ActiveDownload(this.key, this.taskId, this.modelId);
  final String key;
  final String taskId;
  final String modelId;
}
