// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.vad` — voice activity detection.

import 'dart:async';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart' as model_pb;
import 'package:runanywhere/generated/vad_options.pb.dart'
    show VADAudioSource, VADProcessRequest;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';
import 'package:runanywhere/public/api/types/streams.dart';

/// Voice-activity detection over buffers and live streams.
class VadApi {
  /// Bind the namespace. Reach it through `RunAnywhere.vad`.
  const VadApi();

  /// Decide whether [audio] contains speech.
  ///
  /// ```dart
  /// final r = await RunAnywhere.vad.detect(AudioInput.pcm16(frame));
  /// if (r.isSpeech) startTurn();
  /// ```
  ///
  /// Throws [SDKException] when no detector is available.
  Future<VadResult> detect(AudioInput audio, {VadOptions? options}) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = DartBridgeVAD.shared.processLifecycleProto(
      VADProcessRequest(
        audio: audio.toVadSource(),
        options: (options ?? VadOptions()).toProto(),
      ),
    );
    return VadResult.fromProto(result);
  }

  /// Open a live VAD stream. The format is established once; every frame
  /// pushed afterward carries raw PCM in that format.
  ///
  /// ```dart
  /// final stream = RunAnywhere.vad.openStream(
  ///   const AudioFormatSpec(encoding: AudioEncoding.pcm16, sampleRate: 16000));
  /// stream.events.listen(print);
  /// ```
  ///
  /// Throws [SDKException] when [format] is a container encoding — live
  /// streams take raw PCM only.
  VadStream openStream(AudioFormatSpec format, {VadOptions? options}) {
    if (format.encoding == AudioEncoding.container) {
      throw SDKException.invalidInput(
        'vad.openStream needs raw PCM (pcm16/float32), not a container format',
      );
    }
    final effectiveOptions = options ?? VadOptions();
    final frameController = StreamController<AudioFrame>();
    final eventController = StreamController<VadEvent>();
    var closed = false;

    Future<void> run() async {
      try {
        if (!DartBridge.isInitialized) {
          eventController.add(VadFailed(SDKException.notInitialized()));
          return;
        }
        await DartBridge.ensureServicesReady();
        var wasSpeech = false;
        await for (final frame in frameController.stream) {
          if (eventController.isClosed) return;
          final source = VADAudioSource(
            audioData: frame.samples,
            encoding: format.encoding == AudioEncoding.float32
                ? model_pb.AudioEncoding.AUDIO_ENCODING_PCM_F32_LE
                : model_pb.AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
            sampleRate: format.sampleRate,
            channels: format.channels,
          );
          final result = VadResult.fromProto(
            DartBridgeVAD.shared.processLifecycleProto(
              VADProcessRequest(
                audio: source,
                options: effectiveOptions.toProto(),
              ),
            ),
          );
          if (result.isSpeech != wasSpeech) {
            wasSpeech = result.isSpeech;
            eventController.add(
              result.isSpeech
                  ? VadSpeechStarted(frame.timestampMs)
                  : VadSpeechEnded(frame.timestampMs),
            );
          }
          eventController.add(
            VadActivity(
              isSpeech: result.isSpeech,
              probability: result.probability,
              timestampMs: frame.timestampMs,
            ),
          );
        }
        if (!eventController.isClosed) {
          eventController.add(const VadCompleted());
        }
      } catch (e) {
        if (!eventController.isClosed) {
          eventController.add(
            VadFailed(e is SDKException ? e : SDKException.processingFailed('$e')),
          );
        }
      } finally {
        unawaited(eventController.close());
      }
    }

    unawaited(run());

    return VadStream(
      events: eventController.stream,
      pushHandler: (frame) {
        if (closed) return;
        if (!frameController.isClosed) frameController.add(frame);
      },
      flushHandler: () {
        // Every pushed frame is already processed as it arrives.
      },
      finishHandler: () {
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

  /// Detect speech over a live [audio] chunk stream.
  ///
  /// Forwards into [openStream] when every chunk shares one
  /// [AudioFormatSpec]; a chunk with a different format ends the stream
  /// with a thrown error.
  @Deprecated('Use openStream(format, options) and push AudioFrame values')
  Stream<VadEvent> detectStream(
    Stream<AudioInput> audio, {
    VadOptions? options,
  }) {
    final controller = StreamController<VadEvent>();
    controller.onListen = () {
      unawaited(_pumpDeprecated(controller, audio, options));
    };
    return controller.stream;
  }

  Future<void> _pumpDeprecated(
    StreamController<VadEvent> controller,
    Stream<AudioInput> audio,
    VadOptions? options,
  ) async {
    VadStream? stream;
    AudioFormatSpec? format;
    try {
      await for (final chunk in audio) {
        format ??= chunk.format;
        if (format.encoding == AudioEncoding.container) {
          throw SDKException.invalidInput(
            'vad.detectStream needs raw PCM chunks; decode container audio '
            'before streaming it',
          );
        }
        stream ??= openStream(format, options: options);
        if (chunk.format.encoding != format.encoding ||
            chunk.format.sampleRate != format.sampleRate ||
            chunk.format.channels != format.channels) {
          throw SDKException.invalidInput(
            'vad.detectStream requires every chunk to share one audio format',
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
