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

  static void _onNativeProgress(
    Pointer<Uint8> bytesPtr,
    int bytesLen,
    Pointer<Void> _,
  ) {
    if (_progressController.isClosed || bytesPtr == nullptr || bytesLen <= 0) {
      return;
    }
    try {
      final copy = bytesPtr.asTypedList(bytesLen).toList(growable: false);
      _progressController.add(
        download_pb.DownloadProgress.fromBuffer(copy),
      );
    } catch (e) {
      _logger.debug('Failed to decode DownloadProgress: $e');
    }
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
