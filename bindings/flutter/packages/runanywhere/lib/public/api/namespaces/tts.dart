// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.tts` — text to speech, including device playback.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/features/tts/services/audio_playback_manager.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/ra_defaults_pool.dart';
import 'package:runanywhere/generated/tts_options.pb.dart'
    show TTSSynthesisRequest;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_audio.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';

/// Text-to-speech synthesis and playback.
class TtsApi {
  /// Bind the namespace. Reach it through `RunAnywhere.tts`.
  TtsApi();

  static const ModelCategory _category =
      ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;

  final AudioPlaybackManager _playback = AudioPlaybackManager();

  /// Synthesize [text] into one audio buffer.
  ///
  /// ```dart
  /// final audio = await RunAnywhere.tts.synthesize('Hello there');
  /// print(audio.durationMs);
  /// ```
  ///
  /// Throws [SDKException] when no voice is loaded or synthesis fails.
  Future<Audio> synthesize(String text, {TtsOptions? options}) async {
    final request = await _request(text, options);
    final output = await DartBridgeTTS.shared.synthesizeLifecycleProtoAsync(
      request,
    );
    return Audio.fromProto(output);
  }

  /// Synthesize [text] and emit audio chunks as they are produced.
  ///
  /// Throws [SDKException] into the consumer when synthesis fails.
  Stream<AudioChunk> synthesizeStream(
    String text, {
    TtsOptions? options,
  }) async* {
    final request = await _request(text, options);
    await for (final event in DartBridgeTTS.shared
        .synthesizeStreamLifecycleProto(request)) {
      if (event.hasError()) {
        throw SDKException.processingFailed(event.error.message);
      }
      if (event.hasOutput()) {
        yield AudioChunk.fromProto(event.output);
      }
    }
  }

  /// Synthesize [text] and play it through the device speaker, returning
  /// immediately with a handle to the in-flight utterance.
  ///
  /// There is no global `tts.stop()`; interrupt playback through the
  /// returned handle.
  ///
  /// Throws [SDKException] never directly — synthesis/playback failure
  /// surfaces on [SpeechHandle.error].
  SpeechHandle speak(String text, {TtsOptions? options}) {
    final handle = SpeechHandle(interruptHandler: stop);
    _latestHandle = handle;
    unawaited(() async {
      try {
        final audio = await synthesize(text, options: options);
        final sampleRate = audio.sampleRate > 0
            ? audio.sampleRate
            : (options?.sampleRate ?? RADefaultsAudioCapture.ttsSampleRateHz);
        final wav = DartBridgeAudio.float32ToWav(
          Uint8List.fromList(audio.data),
          sampleRate,
        );
        if (wav == null || wav.isEmpty) {
          throw SDKException.processingFailed(
            'TTS audio conversion produced no WAV data',
          );
        }
        await _playback.play(wav);
        handle.complete();
      } catch (error) {
        handle.complete(
          error is SDKException
              ? error
              : SDKException.processingFailed('$error'),
        );
      } finally {
        if (identical(_latestHandle, handle)) _latestHandle = null;
      }
    }());
    return handle;
  }

  SpeechHandle? _latestHandle;

  /// Stop playback and any in-flight synthesis.
  ///
  /// Deprecated: use the [SpeechHandle] returned by [speak]. Interrupts the
  /// most recently created handle when one is still active.
  Future<void> stop() async {
    await _playback.stop();
    if (DartBridge.isInitialized) {
      DartBridgeTTS.shared.stopLifecycleProto();
    }
  }

  // --- Beyond the v3 spec -------------------------------------------------

  /// Whether [speak] is currently playing audio. The SDK owns playback, so
  /// this is the only way a UI can follow it.
  Stream<bool> get playbackState => _playback.playingStream;

  /// Playback position of [speak] in `[0.0, 1.0]`.
  Stream<double> get playbackProgress => _playback.progressStream;

  /// Voices the loaded model offers.
  ///
  /// `TTSServiceState.voices` was deleted outright
  /// (idl/tts_options.proto: "use the list-voices verb") — this now calls
  /// the dedicated `rac_tts_component_list_voices_proto` ABI directly.
  ///
  /// Throws [SDKException] when the SDK is not initialized.
  Future<List<Voice>> voices() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final voices = await DartBridgeTTS.shared.listVoicesProto();
    return List<Voice>.unmodifiable(voices.map(Voice.fromProto));
  }

  Future<TTSSynthesisRequest> _request(
    String text,
    TtsOptions? options,
  ) async {
    await ModelGate.ensureLoaded(modelId: null, category: _category);
    final voiceModelId = await ModelGate.currentId(_category);
    if (voiceModelId == null) {
      throw SDKException.componentNotReady('TTS');
    }
    // `metadata` was deleted outright from `TTSSynthesisRequest`
    // (idl/tts_options.proto) — the lifecycle-owned ABI resolves the voice
    // internally.
    return TTSSynthesisRequest(
      text: text,
      options: (options ?? TtsOptions()).toProto(),
    );
  }
}
