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

  /// Transcribe a live [audio] chunk stream, emitting partials then a final.
  ///
  /// Throws [SDKException] into the consumer when the session cannot start.
  Stream<TranscriptionEvent> transcribeStream(
    Stream<AudioInput> audio, {
    SttOptions? options,
  }) {
    final controller = StreamController<TranscriptionEvent>();
    controller.onListen = () {
      unawaited(_pump(controller, audio, options));
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

  Future<void> _pump(
    StreamController<TranscriptionEvent> controller,
    Stream<AudioInput> audio,
    SttOptions? options,
  ) async {
    try {
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

      controller.add(const TranscriptionStarted());
      var sawFinal = false;
      final partials = DartBridgeSTT.shared.transcribeSessionStream(
        audio.map((chunk) => Uint8List.fromList(chunk.bytes)),
        (options ?? SttOptions()).toProto(),
      );
      await for (final partial in partials) {
        if (controller.isClosed) break;
        if (partial.isFinal) {
          sawFinal = true;
          controller.add(
            TranscriptionFinal(
              partial.hasFinalOutput()
                  ? Transcription.fromProto(partial.finalOutput)
                  : Transcription(text: partial.text),
            ),
          );
        } else {
          controller.add(TranscriptionPartial(partial.text));
        }
      }
      if (!sawFinal && !controller.isClosed) {
        controller.add(const TranscriptionFinal(Transcription(text: '')));
      }
    } catch (error, stack) {
      controller.addError(
        error is SDKException ? error : SDKException.processingFailed('$error'),
        stack,
      );
    } finally {
      await controller.close();
    }
  }
}
