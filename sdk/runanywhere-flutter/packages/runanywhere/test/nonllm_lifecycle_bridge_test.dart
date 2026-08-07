// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart';
import 'package:runanywhere/generated/embeddings_options.pb.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show AudioEncoding;
import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/generated/tts_options.pb.dart';
import 'package:runanywhere/generated/vad_options.pb.dart';
import 'package:runanywhere/native/dart_bridge_diffusion.dart';
import 'package:runanywhere/native/dart_bridge_embeddings.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';

void main() {
  tearDown(() {
    DartBridgeSTT.setTranscribeLifecycleProtoForTesting(null);
    DartBridgeTTS.setSynthesizeLifecycleProtoForTesting(null);
    DartBridgeVAD.setProcessLifecycleProtoForTesting(null);
    DartBridgeDiffusion.setGenerateLifecycleProtoForTesting(null);
    DartBridgeEmbeddings.setEmbedBatchLifecycleProtoForTesting(null);
  });

  test('lifecycle STT bridge forwards generated request and result', () {
    late STTTranscriptionRequest seen;
    DartBridgeSTT.setTranscribeLifecycleProtoForTesting((request) {
      seen = request;
      return STTOutput(text: 'hello', confidence: 0.9);
    });

    final result = DartBridgeSTT.shared.transcribeLifecycleProto(
      STTTranscriptionRequest(
        audio: STTAudioSource(
          audioData: [1, 2, 3, 4],
          encoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
          sampleRate: 16000,
          channels: 1,
        ),
        // `STTOptions.beamSize` was deleted outright (idl/stt_options.
        // proto) — the message trimmed to punctuation/diarization/word-
        // timestamp/silence/language knobs.
        options: STTOptions(enablePunctuation: true),
      ),
    );

    expect(result.text, 'hello');
    expect(seen.audio.audioData, [1, 2, 3, 4]);
    expect(seen.options.enablePunctuation, isTrue);
  });

  test('lifecycle TTS bridge forwards generated request and result', () {
    late TTSSynthesisRequest seen;
    DartBridgeTTS.setSynthesizeLifecycleProtoForTesting((request) {
      seen = request;
      return TTSOutput(audioData: [9, 8], sampleRate: 22050, isFinal: true);
    });

    final result = DartBridgeTTS.shared.synthesizeLifecycleProto(
      TTSSynthesisRequest(
        text: 'speak',
        options: TTSOptions(languageCode: 'en-US'),
      ),
    );

    expect(result.audioData, [9, 8]);
    expect(seen.text, 'speak');
    expect(seen.options.languageCode, 'en-US');
  });

  test('lifecycle VAD bridge forwards generated request and result', () {
    late VADProcessRequest seen;
    DartBridgeVAD.setProcessLifecycleProtoForTesting((request) {
      seen = request;
      // `VADResult.confidence` was renamed `probability` (idl/vad_options.
      // proto).
      return VADResult(isSpeech: true, probability: 0.8, energy: 0.4);
    });

    final result = DartBridgeVAD.shared.processLifecycleProto(
      VADProcessRequest(
        // `VADAudioSource` is a plain message now, not a oneof
        // (idl/vad_options.proto) — `audioData` is unconditional.
        audio: VADAudioSource(
          audioData: [0, 0, 1, 0],
          encoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
          sampleRate: 16000,
          channels: 1,
        ),
        options: VADOptions(activationThreshold: 0.2),
      ),
    );

    expect(result.isSpeech, isTrue);
    expect(seen.audio.audioData, [0, 0, 1, 0]);
    expect(seen.options.activationThreshold, closeTo(0.2, 1e-6));
  });

  test('lifecycle diffusion bridge forwards generated request and result', () {
    late DiffusionGenerationRequest seen;
    DartBridgeDiffusion.setGenerateLifecycleProtoForTesting((request) {
      seen = request;
      // The flat single-image `DiffusionResult` (`image_data`/`image_media_
      // type`) was restructured into `repeated DiffusionImage images`
      // (idl/diffusion_options.proto), each entry carrying its own
      // `data`/`mediaType`.
      return DiffusionResult(
        images: [DiffusionImage(data: [1, 2, 3], mediaType: 'image/png')],
      );
    });

    final result = DartBridgeDiffusion.generateProto(
      DiffusionGenerationRequest(
        modelId: 'sdxl',
        options: DiffusionGenerationOptions(prompt: 'mountain'),
      ),
    );

    expect(result.images.single.data, [1, 2, 3]);
    expect(seen.modelId, 'sdxl');
    expect(seen.options.prompt, 'mountain');
  });

  test('lifecycle embeddings bridge forwards generated request and result', () {
    late EmbeddingsRequest seen;
    DartBridgeEmbeddings.setEmbedBatchLifecycleProtoForTesting((request) {
      seen = request;
      return EmbeddingsResult(dimension: 2, modelId: request.modelId);
    });

    final result = DartBridgeEmbeddings.shared.embedBatch(
      EmbeddingsRequest(texts: ['alpha', 'beta'], modelId: 'embedder'),
    );

    expect(result.dimension, 2);
    expect(result.modelId, 'embedder');
    expect(seen.texts, ['alpha', 'beta']);
  });

  test('STT rejects platform-owned audio sources before FFI', () {
    // `adapter_handle` was deleted from `STTAudioSource`'s oneof
    // (idl/stt_options.proto); `file_uri` is the only non-inline-bytes
    // source left and still requires a platform adapter.
    expect(
      () => DartBridgeSTT.shared.transcribeLifecycleProto(
        STTTranscriptionRequest(
          audio: STTAudioSource(fileUri: 'file:///private/audio.wav'),
        ),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('platform adapter'),
        ),
      ),
    );
  });

  test('VAD rejects empty audio_data before FFI', () {
    // `VADAudioSource` is a plain message now, not a oneof
    // (idl/vad_options.proto): `adapter_handle` is gone, so the only
    // remaining pre-FFI rejection is empty `audio_data`.
    expect(
      () => DartBridgeVAD.shared.processLifecycleProto(
        VADProcessRequest(audio: VADAudioSource()),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
