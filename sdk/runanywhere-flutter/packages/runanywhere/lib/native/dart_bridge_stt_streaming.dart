// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_stt_streaming.dart — FFI helpers for streaming STT
// (`rac_stt_component_transcribe_stream`). Public capability code
// calls into this bridge so `lib/public/capabilities/runanywhere_stt.dart`
// stays free of `dart:ffi` imports (canonical §15 type-discipline).

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart'
    show racAudioFormatWav, RacSttOptionsStruct;
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// Native callback type for `rac_stt_component_transcribe_stream`.
typedef SttStreamCallback = Void Function(
  Pointer<Void>, // text pointer (caller casts to Pointer<Utf8>)
  Int32, // isFinal flag (1 = final, 0 = partial)
  Pointer<Void>, // user_data (unused)
);

/// Native function signature for `rac_stt_component_transcribe_stream`.
typedef SttTranscribeStreamFn = Int32 Function(
  Pointer<Void>, // handle
  Pointer<Void>, // audio data
  IntPtr, // audio length (size_t on all platforms)
  Pointer<Void>, // options struct
  Pointer<Void>, // callback function pointer
  Pointer<Void>, // user_data
);

/// Plain-data option payload accepted by [DartBridgeSttStreaming]; no
/// `dart:ffi` types so capability code can construct it freely.
class SttStreamingOptions {
  SttStreamingOptions({
    required this.languageBcp47,
    required this.detectLanguage,
    required this.enablePunctuation,
    required this.enableDiarization,
    required this.maxSpeakers,
    required this.enableTimestamps,
    this.sampleRate = 16000,
  });
  final String languageBcp47;
  final bool detectLanguage;
  final bool enablePunctuation;
  final bool enableDiarization;
  final int maxSpeakers;
  final bool enableTimestamps;
  final int sampleRate;
}

/// Plain partial-result event surfaced to the capability layer.
class SttStreamingEvent {
  SttStreamingEvent({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}

/// FFI bridge to the STT streaming C ABI.
class DartBridgeSttStreaming {
  DartBridgeSttStreaming._();

  /// Run a streaming transcription. Emits an [SttStreamingEvent] per
  /// callback fired by `rac_stt_component_transcribe_stream` and
  /// terminates the stream once `isFinal == true`.
  ///
  /// The returned record exposes the event stream plus an `onCancel`
  /// hook the caller can wire into a `StreamController.onCancel`.
  static ({Stream<SttStreamingEvent> stream, void Function() onCancel})
      transcribeStream({
    required Uint8List audio,
    required SttStreamingOptions options,
  }) {
    final controller = StreamController<SttStreamingEvent>(sync: false);
    final receivePort = ReceivePort();
    NativeCallable<SttStreamCallback>? callable;

    Future<void> runStream() async {
      final handle = DartBridge.stt.getHandle();
      final lib = PlatformLoader.loadCommons();

      final fn = lib
          .lookup<NativeFunction<SttTranscribeStreamFn>>(
              'rac_stt_component_transcribe_stream')
          .asFunction<
              int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>,
                  Pointer<Void>, Pointer<Void>)>();

      final dataPtr = calloc<Uint8>(audio.length);
      final optsPtr = calloc<RacSttOptionsStruct>();
      Pointer<Utf8>? langPtr;

      try {
        dataPtr.asTypedList(audio.length).setAll(0, audio);

        langPtr = options.languageBcp47.toNativeUtf8();

        optsPtr.ref.language = langPtr;
        optsPtr.ref.detectLanguage =
            options.detectLanguage ? RAC_TRUE : RAC_FALSE;
        optsPtr.ref.enablePunctuation =
            options.enablePunctuation ? RAC_TRUE : RAC_FALSE;
        optsPtr.ref.enableDiarization =
            options.enableDiarization ? RAC_TRUE : RAC_FALSE;
        optsPtr.ref.maxSpeakers = options.maxSpeakers;
        optsPtr.ref.enableTimestamps =
            options.enableTimestamps ? RAC_TRUE : RAC_FALSE;
        optsPtr.ref.audioFormat = racAudioFormatWav;
        optsPtr.ref.sampleRate = options.sampleRate;

        final sendPort = receivePort.sendPort;
        callable = NativeCallable<SttStreamCallback>.isolateLocal(
          (Pointer<Void> rawPtr, int isFinal, Pointer<Void> _) {
            final textPtr = rawPtr.cast<Utf8>();
            final text = textPtr == nullptr ? '' : textPtr.toDartString();
            sendPort.send([text, isFinal == RAC_TRUE]);
          },
        );

        receivePort.listen((dynamic msg) {
          if (controller.isClosed) return;
          final list = msg as List<dynamic>;
          final text = list[0] as String;
          final isFinal = list[1] as bool;
          controller.add(SttStreamingEvent(text: text, isFinal: isFinal));
          if (isFinal) {
            unawaited(controller.close());
            receivePort.close();
            callable?.close();
            callable = null;
          }
        });

        final rc = fn(
          handle.cast<Void>(),
          dataPtr.cast<Void>(),
          audio.length,
          optsPtr.cast<Void>(),
          callable!.nativeFunction.cast<Void>(),
          nullptr,
        );

        if (rc != RAC_SUCCESS) {
          if (!controller.isClosed) {
            controller.addError(SDKException.sttNotAvailable(
              'rac_stt_component_transcribe_stream failed: '
              '${RacResultCode.getMessage(rc)}',
            ));
            await controller.close();
          }
          receivePort.close();
          callable?.close();
          callable = null;
        }
      } finally {
        calloc.free(dataPtr);
        calloc.free(optsPtr);
        if (langPtr != null) calloc.free(langPtr);
      }
    }

    void onCancel() {
      receivePort.close();
      callable?.close();
      callable = null;
    }

    // Kick off the native call without awaiting; events flow through
    // the receivePort listener registered inside runStream.
    unawaited(runStream());
    return (stream: controller.stream, onCancel: onCancel);
  }
}
