// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.stt` — speech to text.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/stt_options.pb.dart'
    show STTTranscriptionRequest;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';
import 'package:runanywhere/public/api/types/streams.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// Speech-to-text transcription.
class SttApi {
  /// Bind the namespace. Reach it through `RunAnywhere.stt`.
  const SttApi();

  static const ModelCategory _category =
      ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;

  /// Transcribe a complete [audio] buffer.
  ///
  /// ```dart
  /// final t = await RunAnywhere.stt.transcribe(AudioInput.wav(bytes));
  /// print(t.text);
  /// ```
  ///
  /// Throws [SDKException] when no speech model is loaded or transcription
  /// fails.
  Future<Transcription> transcribe(
    AudioInput audio, {
    SttOptions? options,
  }) async {
    await ModelGate.ensureLoaded(modelId: null, category: _category);
    final modelId = await ModelGate.currentId(_category);
    if (modelId == null) {
      throw SDKException.componentNotReady('STT');
    }
    final result = await DartBridgeSTT.shared.transcribeLifecycleProtoAsync(
      STTTranscriptionRequest(
        audio: audio.toSttSource(),
        options: (options ?? SttOptions()).toProto(),
        metadata: <String, String>{'model_id': modelId}.entries,
      ),
    );
    return Transcription.fromProto(result);
  }

  /// Open a live transcription stream. The format is established once;
  /// every frame pushed afterward carries raw PCM in that format.
  ///
  /// ```dart
  /// final stream = await RunAnywhere.stt.openStream(
  ///   const AudioFormatSpec(encoding: AudioEncoding.pcm16, sampleRate: 16000));
  /// stream.events.listen(print);
  /// ```
  ///
  /// Throws [SDKException] when [format] is a container encoding (live
  /// streams take raw PCM only), no STT model is loaded, or the native
  /// streaming session cannot start.
  Future<SttStream> openStream(
    AudioFormatSpec format, {
    SttOptions? options,
  }) async {
    if (format.encoding == AudioEncoding.container) {
      throw SDKException.invalidInput(
        'stt.openStream needs raw PCM (pcm16/float32), not a container format',
      );
    }
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: _category),
    );
    if (!current.found) {
      throw SDKException.componentNotReady('STT');
    }
    final modelId = current.modelId.isNotEmpty
        ? current.modelId
        : current.model.id;
    final modelPath = current.resolvedPath.isNotEmpty
        ? current.resolvedPath
        : current.model.localPath;
    if (modelId.isEmpty || modelPath.isEmpty) {
      throw SDKException.modelLoadFailed(
        modelId,
        'Loaded STT model is missing a resolved path',
      );
    }
    DartBridgeSTT.shared.loadModelForStreaming(
      path: modelPath,
      id: modelId,
      name: current.model.name.isNotEmpty ? current.model.name : modelId,
    );

    final requestId = 'stt-${DateTime.now().microsecondsSinceEpoch}';
    final frameController = StreamController<Uint8List>();
    final eventController = StreamController<TranscriptionEvent>();
    var announcedStarted = false;
    var finished = false;
    var closed = false;

    void announceStarted() {
      if (announcedStarted) return;
      announcedStarted = true;
      if (!eventController.isClosed) {
        eventController.add(TranscriptionStarted(requestId));
      }
    }

    Future<void> runSession() async {
      var sawTerminal = false;
      try {
        final partials = DartBridgeSTT.shared.transcribeSessionStream(
          frameController.stream,
          (options ?? SttOptions()).toProto(),
        );
        await for (final partial in partials) {
          if (eventController.isClosed) return;
          if (partial.isFinal) {
            sawTerminal = true;
            // `STTPartialResult.final_output` (a full `STTOutput`) was
            // deleted outright, along with `segment_index`/`confidence`/
            // `stability`/etc (idl/stt_options.proto) — `text` is the only
            // content field left on a final partial.
            eventController.add(
              TranscriptionFinal(Transcription(text: partial.text)),
            );
            eventController.add(const TranscriptionCompleted());
            break;
          }
          eventController.add(TranscriptionPartial(partial.text));
        }
        // Never fabricate a settled transcript: a session that ends
        // without a final result reports it honestly instead of
        // synthesizing an empty `TranscriptionFinal`.
        if (!sawTerminal && !eventController.isClosed) {
          eventController.add(
            TranscriptionFailed(
              SDKException.processingFailed(
                'Transcription stream ended before a final result',
              ),
            ),
          );
        }
      } catch (e) {
        if (!eventController.isClosed) {
          eventController.add(
            TranscriptionFailed(
              e is SDKException ? e : SDKException.processingFailed('$e'),
            ),
          );
        }
      } finally {
        unawaited(eventController.close());
      }
    }

    unawaited(runSession());

    return SttStream(
      events: eventController.stream,
      pushHandler: (frame) {
        if (closed || finished) return;
        announceStarted();
        if (!frameController.isClosed) frameController.add(frame.samples);
      },
      flushHandler: () {
        // Frames are fed to the native session as they arrive.
      },
      finishHandler: () {
        if (finished || closed) return;
        finished = true;
        announceStarted();
        unawaited(frameController.close());
      },
      closeHandler: () async {
        if (closed) return;
        closed = true;
        unawaited(frameController.close());
        await eventController.close();
      },
    );
  }

  /// Transcribe a live [audio] chunk stream, emitting partials then a final.
  ///
  /// Forwards into [openStream] when every chunk shares one
  /// [AudioFormatSpec]; a chunk with a different format ends the stream
  /// with a thrown error.
  @Deprecated('Use openStream(format, options) and push AudioFrame values')
  Stream<TranscriptionEvent> transcribeStream(
    Stream<AudioInput> audio, {
    SttOptions? options,
  }) {
    final controller = StreamController<TranscriptionEvent>();
    controller.onListen = () {
      unawaited(_pumpDeprecated(controller, audio, options));
    };
    return controller.stream;
  }

  /// Readiness, loaded model, and language coverage of the STT component.
  ///
  /// Throws [SDKException] when the SDK is not initialized.
  Future<SttState> state() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return SttState.fromProto(DartBridgeSTT.shared.stateLifecycleProto());
  }

  Future<void> _pumpDeprecated(
    StreamController<TranscriptionEvent> controller,
    Stream<AudioInput> audio,
    SttOptions? options,
  ) async {
    SttStream? stream;
    AudioFormatSpec? format;
    try {
      await for (final chunk in audio) {
        format ??= chunk.format;
        if (format.encoding == AudioEncoding.container) {
          throw SDKException.invalidInput(
            'stt.transcribeStream needs raw PCM chunks; decode container '
            'audio before streaming it',
          );
        }
        stream ??= await openStream(format, options: options);
        if (chunk.format.encoding != format.encoding ||
            chunk.format.sampleRate != format.sampleRate ||
            chunk.format.channels != format.channels) {
          throw SDKException.invalidInput(
            'stt.transcribeStream requires every chunk to share one audio format',
          );
        }
        stream.pushFrame(
          AudioFrame(samples: chunk.bytes, sampleCount: chunk.bytes.length),
        );
      }
      final opened = stream;
      if (opened == null) return;
      opened.finish();
      await for (final event in opened.events) {
        if (controller.isClosed) break;
        controller.add(event);
      }
    } catch (error, stack) {
      if (!controller.isClosed) {
        controller.addError(
          error is SDKException
              ? error
              : SDKException.processingFailed('$error'),
          stack,
        );
      }
    } finally {
      unawaited(stream?.close());
      await controller.close();
    }
  }
}
