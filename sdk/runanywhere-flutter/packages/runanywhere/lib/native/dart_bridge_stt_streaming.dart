// SPDX-License-Identifier: Apache-2.0
//
// Generated-proto STT streaming bridge.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/stt_options.pb.dart'
    show STTOptions, STTPartialResult;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';

class DartBridgeSttStreaming {
  DartBridgeSttStreaming._();

  static ({Stream<STTPartialResult> stream, void Function() onCancel})
      transcribeStream({
    required Uint8List audio,
    required STTOptions options,
  }) {
    final fn = RacNative.bindings.rac_stt_component_transcribe_stream_proto;
    if (fn == null) {
      return (
        stream: Stream<STTPartialResult>.error(SDKException.sttNotAvailable(
          'rac_stt_component_transcribe_stream_proto is unavailable',
        )),
        onCancel: () {},
      );
    }

    final controller = StreamController<STTPartialResult>(sync: false);
    ffi.NativeCallable<RacSttProtoPartialCallbackNative>? callback;

    Future<void> runStream() async {
      final handle = DartBridge.stt.getHandle();
      final optionsBytes = options.writeToBuffer();
      final audioPtr = calloc<ffi.Uint8>(audio.isEmpty ? 1 : audio.length);
      final optionsPtr = DartBridgeProtoUtils.copyBytes(optionsBytes);

      try {
        if (audio.isNotEmpty) {
          audioPtr.asTypedList(audio.length).setAll(0, audio);
        }

        callback =
            ffi.NativeCallable<RacSttProtoPartialCallbackNative>.listener((
          ffi.Pointer<ffi.Uint8> bytesPtr,
          int bytesLen,
          ffi.Pointer<ffi.Void> _,
        ) {
          if (controller.isClosed || bytesPtr == ffi.nullptr || bytesLen <= 0) {
            return;
          }
          try {
            final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
            final partial = STTPartialResult.fromBuffer(copy);
            controller.add(partial);
            if (partial.isFinal) {
              unawaited(controller.close());
            }
          } catch (e, st) {
            controller.addError(e, st);
            unawaited(controller.close());
          }
        });

        final rc = fn(
          handle,
          audioPtr.cast<ffi.Void>(),
          audio.length,
          optionsPtr,
          optionsBytes.length,
          callback!.nativeFunction,
          ffi.nullptr,
        );
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(SDKException.sttNotAvailable(
            'rac_stt_component_transcribe_stream_proto failed: '
            '${RacResultCode.getMessage(rc)}',
          ));
          await controller.close();
        } else if (!controller.isClosed) {
          await controller.close();
        }
      } finally {
        calloc.free(audioPtr);
        calloc.free(optionsPtr);
        callback?.close();
        callback = null;
      }
    }

    void onCancel() {
      callback?.close();
      callback = null;
    }

    unawaited(runStream());
    return (stream: controller.stream, onCancel: onCancel);
  }
}
