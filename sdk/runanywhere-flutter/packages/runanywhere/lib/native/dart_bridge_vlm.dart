/// DartBridge+VLM
///
/// Thin generated-proto VLM bridge. Commons lifecycle owns the loaded VLM
/// service; Dart passes app-owned image request bytes and receives generated
/// VLM result/stream protos.
library dart_bridge_vlm;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart' show RacProtoBuffer;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart' show SDKEvent;
import 'package:runanywhere/generated/vlm_options.pb.dart'
    show VLMGenerationRequest, VLMResult, VLMStreamEvent;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

typedef _RacVlmGenerateProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef _RacVlmGenerateProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef _RacVlmStreamEventProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef _RacVlmStreamProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<_RacVlmStreamEventProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef _RacVlmStreamProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<_RacVlmStreamEventProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef _RacVlmCancelLifecycleProtoNative = ffi.Int32 Function(
  ffi.Pointer<RacProtoBuffer>,
);
typedef _RacVlmCancelLifecycleProtoDart = int Function(
  ffi.Pointer<RacProtoBuffer>,
);

/// VLM generated-proto bridge for C++ interop.
class DartBridgeVLM {
  static final DartBridgeVLM shared = DartBridgeVLM._();

  DartBridgeVLM._();

  final _logger = SDKLogger('DartBridge.VLM');

  Future<VLMResult> processImageProto(
    VLMGenerationRequest request,
  ) async {
    final fn = _lookupGenerateProto();
    return DartBridgeProtoUtils.callRequest<VLMResult>(
      request: request,
      invoke: fn,
      decode: VLMResult.fromBuffer,
      symbol: 'rac_vlm_generate_proto',
    );
  }

  Stream<VLMStreamEvent> processImageStreamProto(
    VLMGenerationRequest request,
  ) {
    final controller = StreamController<VLMStreamEvent>(sync: true);

    controller.onListen = () {
      unawaited(_runProcessImageStreamProto(request, controller));
    };
    controller.onCancel = cancel;

    return controller.stream;
  }

  Future<void> _runProcessImageStreamProto(
    VLMGenerationRequest request,
    StreamController<VLMStreamEvent> controller,
  ) async {
    await Future<void>.delayed(Duration.zero);

    final bytes = request.writeToBuffer();
    final requestPtr = DartBridgeProtoUtils.copyBytes(bytes);
    final stateId = _registerVlmStreamCallbackState(controller: controller);
    final userData = calloc<ffi.Int64>()..value = stateId;
    final callback =
        ffi.Pointer.fromFunction<_RacVlmStreamEventProtoCallbackNative>(
      _vlmStreamProtoCallback,
      RAC_FALSE,
    );

    try {
      final fn = _lookupStreamProto();
      final code = fn(
        requestPtr,
        bytes.length,
        callback,
        userData.cast<ffi.Void>(),
      );
      if (code != RacResultCode.success && !controller.isClosed) {
        controller.addError(StateError(
          'rac_vlm_stream_proto failed: ${RacResultCode.getMessage(code)}',
        ));
      }
    } catch (e, st) {
      if (!controller.isClosed) {
        controller.addError(e, st);
      }
    } finally {
      _vlmStreamCallbackStates.remove(stateId);
      calloc.free(requestPtr);
      calloc.free(userData);
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// Cancel lifecycle-owned VLM generation.
  void cancel() {
    final fn = _lookupCancelLifecycleProtoOrNull();
    if (fn == null) {
      _logger.debug('rac_vlm_cancel_lifecycle_proto is unavailable');
      return;
    }

    try {
      DartBridgeProtoUtils.callOut<SDKEvent>(
        invoke: fn,
        decode: SDKEvent.fromBuffer,
        symbol: 'rac_vlm_cancel_lifecycle_proto',
      );
      _logger.debug('VLM lifecycle processing cancelled');
    } catch (e) {
      _logger.error('Failed to cancel lifecycle-owned VLM processing: $e');
    }
  }

  _RacVlmGenerateProtoDart _lookupGenerateProto() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_RacVlmGenerateProtoNative, _RacVlmGenerateProtoDart>(
              'rac_vlm_generate_proto');
    } catch (_) {
      throw UnsupportedError('rac_vlm_generate_proto is unavailable');
    }
  }

  _RacVlmStreamProtoDart _lookupStreamProto() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_RacVlmStreamProtoNative, _RacVlmStreamProtoDart>(
              'rac_vlm_stream_proto');
    } catch (_) {
      throw UnsupportedError('rac_vlm_stream_proto is unavailable');
    }
  }

  _RacVlmCancelLifecycleProtoDart? _lookupCancelLifecycleProtoOrNull() {
    try {
      return PlatformLoader.loadCommons().lookupFunction<
          _RacVlmCancelLifecycleProtoNative,
          _RacVlmCancelLifecycleProtoDart>('rac_vlm_cancel_lifecycle_proto');
    } catch (_) {
      return null;
    }
  }
}

class _VlmStreamCallbackState {
  const _VlmStreamCallbackState({
    required this.controller,
  });

  final StreamController<VLMStreamEvent> controller;
}

final _vlmStreamCallbackStates = <int, _VlmStreamCallbackState>{};
int _nextVlmStreamCallbackStateId = 1;

int _registerVlmStreamCallbackState({
  required StreamController<VLMStreamEvent> controller,
}) {
  final id = _nextVlmStreamCallbackStateId++;
  _vlmStreamCallbackStates[id] = _VlmStreamCallbackState(
    controller: controller,
  );
  return id;
}

@pragma('vm:entry-point')
int _vlmStreamProtoCallback(
  ffi.Pointer<ffi.Uint8> bytesPtr,
  int bytesLen,
  ffi.Pointer<ffi.Void> userData,
) {
  if (userData == ffi.nullptr) return RAC_FALSE;
  final state = _vlmStreamCallbackStates[userData.cast<ffi.Int64>().value];
  if (state == null || state.controller.isClosed) return RAC_FALSE;
  if (bytesPtr == ffi.nullptr || bytesLen <= 0) return RAC_TRUE;

  try {
    final bytes = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
    state.controller.add(VLMStreamEvent.fromBuffer(bytes));
    return RAC_TRUE;
  } catch (e, st) {
    if (!state.controller.isClosed) {
      state.controller.addError(e, st);
    }
    return RAC_FALSE;
  }
}
