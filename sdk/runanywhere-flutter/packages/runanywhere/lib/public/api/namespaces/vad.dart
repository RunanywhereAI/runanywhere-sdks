// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.vad` — voice activity detection.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/vad_options.pb.dart'
    show VADProcessRequest;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';

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

  /// Detect speech over a live [audio] chunk stream.
  ///
  /// Throws [SDKException] into the consumer when the detector fails.
  Stream<VadResult> detectStream(
    Stream<AudioInput> audio, {
    VadOptions? options,
  }) async* {
    await for (final chunk in audio) {
      yield await detect(chunk, options: options);
    }
  }
}
