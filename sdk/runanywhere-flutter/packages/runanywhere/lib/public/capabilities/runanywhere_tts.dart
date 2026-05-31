// SPDX-License-Identifier: Apache-2.0
//
// TTS capability backed by commons model lifecycle and lifecycle-owned
// generated-proto synthesis.

import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/tts_options.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

/// TTS (text-to-speech) capability surface.
///
/// Access via `RunAnywhere.tts`. Load/current/unload state is owned
/// by commons lifecycle; one-shot synthesis uses the lifecycle-owned
/// generated-proto commons ABI.
class RunAnywhereTTS {
  RunAnywhereTTS._();
  static final RunAnywhereTTS _instance = RunAnywhereTTS._();
  static RunAnywhereTTS get shared => _instance;

  bool _isSpeaking = false;

  /// True when commons lifecycle has a ready TTS voice.
  bool get isLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// Currently-loaded TTS voice ID from commons lifecycle, or null.
  String? get currentVoiceId {
    final snapshot = _lifecycleSnapshot;
    if (snapshot == null ||
        snapshot.state !=
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ||
        snapshot.modelId.isEmpty) {
      return null;
    }
    return snapshot.modelId;
  }

  /// Currently-loaded TTS voice as `ModelInfo`, or null.
  Future<ModelInfo?> currentVoice() async {
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(
        category: _ttsCategory,
        includeModelMetadata: true,
      ),
    );
    if (!current.found || current.modelId.isEmpty || !current.hasModel()) {
      return null;
    }
    return current.model;
  }

  /// Load a TTS voice by ID through commons lifecycle routing.
  Future<void> loadVoice(String voiceId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();

    final logger = SDKLogger('RunAnywhere.LoadTTSVoice');
    logger.info('Loading TTS voice: $voiceId');

    // C++ commons auto-emits TTS voice load started/completed/failed events.
    try {
      final result = await RunAnywhereModelLifecycle.shared.load(
        model_pb.ModelLoadRequest(
          modelId: voiceId,
          category: _ttsCategory,
          forceReload: true,
          validateAvailability: true,
        ),
      );
      if (!result.success) {
        throw SDKException.modelLoadFailed(
          voiceId,
          result.errorMessage.isNotEmpty
              ? result.errorMessage
              : 'TTS lifecycle load failed',
        );
      }

      logger.info('TTS voice loaded: $voiceId');
    } catch (e) {
      logger.error('Failed to load TTS voice: $e');
      rethrow;
    }
  }

  /// Unload the currently-loaded TTS voice through commons lifecycle routing.
  Future<void> unloadVoice() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final voiceId = currentVoiceId ??
        (await RunAnywhereModelLifecycle.shared.current(
          model_pb.CurrentModelRequest(category: _ttsCategory),
        ))
            .modelId;
    if (voiceId.isEmpty) return;

    // C++ commons auto-emits TTS voice unload started/completed events.
    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: voiceId,
        category: _ttsCategory,
      ),
    );
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'TTS lifecycle unload failed',
      );
    }
    _isSpeaking = false;
  }

  /// Synthesize speech from [text]. Returns proto [TTSOutput].
  Future<TTSOutput> synthesize(
    String text, [
    TTSOptions? options,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();
    final voiceId = await _requireLoadedVoiceId();
    final opts = _effectiveOptions(options ?? TTSOptions());
    final request = TTSSynthesisRequest(
      text: opts.enableSsml ? null : text,
      ssml: opts.enableSsml ? text : null,
      options: opts,
      metadata: <String, String>{'voice_id': voiceId}.entries,
    );
    return DartBridgeTTS.shared.synthesizeLifecycleProto(request);
  }

  /// Stream generated [TTSOutput] chunks as they are produced.
  Stream<TTSOutput> synthesizeStream(
    String text, {
    TTSOptions? options,
  }) async* {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final voiceId = await _requireLoadedVoiceId();
    final opts = _effectiveOptions(options ?? TTSOptions());
    final request = TTSSynthesisRequest(
      text: opts.enableSsml ? null : text,
      ssml: opts.enableSsml ? text : null,
      options: opts,
      metadata: <String, String>{'voice_id': voiceId}.entries,
    );
    await for (final event
        in DartBridgeTTS.shared.synthesizeStreamLifecycleProto(request)) {
      if (event.hasOutput()) {
        yield event.output;
      }
    }
  }

  /// Stop in-flight synthesis.
  Future<void> stopSynthesis() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeTTS.shared.stopLifecycleProto();
    _isSpeaking = false;
  }

  /// Synthesize-and-play. Mirrors Swift's `RunAnywhere.speak(_:options:)`.
  Future<TTSSpeakResult> speak(String text, [TTSOptions? options]) async {
    final output = await synthesize(text, options);
    _isSpeaking = true;
    try {
      return TTSSpeakResult(
        audioFormat: output.audioFormat,
        sampleRate: output.sampleRate,
        durationMs: output.durationMs,
        audioSizeBytes: Int64(output.audioData.length),
        metadata: output.metadata,
        timestampMs: output.timestampMs,
      );
    } finally {
      _isSpeaking = false;
    }
  }

  /// True while a `speak()` invocation is in flight.
  bool get isSpeaking => _isSpeaking;

  /// Stop ongoing playback.
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    await stopSynthesis();
  }

  /// List available TTS voice ids from the generated registry surface.
  Future<List<String>> availableVoices() async {
    final result = await RunAnywhereModels.shared.list(
      query: model_pb.ModelQuery(category: _ttsCategory),
    );
    return result.models.models.map((m) => m.id).toList(growable: false);
  }

  Future<String> _requireLoadedVoiceId() async {
    final snapshotVoiceId = currentVoiceId;
    if (snapshotVoiceId != null) {
      return snapshotVoiceId;
    }
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: _ttsCategory),
    );
    if (current.found && current.modelId.isNotEmpty) {
      return current.modelId;
    }
    throw SDKException.ttsNotAvailable(
      'No TTS voice loaded through commons lifecycle. Call loadTTSVoice() first.',
    );
  }

  TTSOptions _effectiveOptions(TTSOptions options) {
    final opts = options.deepCopy();
    if (!opts.hasLanguageCode()) {
      opts.languageCode = 'en-US';
    }
    if (!opts.hasSpeakingRate()) {
      opts.speakingRate = 1.0;
    }
    if (!opts.hasPitch()) {
      opts.pitch = 1.0;
    }
    if (!opts.hasVolume()) {
      opts.volume = 1.0;
    }
    if (!opts.hasAudioFormat()) {
      opts.audioFormat = model_pb.AudioFormat.AUDIO_FORMAT_PCM;
    }
    if (!opts.hasSampleRate()) {
      opts.sampleRate = 22050;
    }
    return opts;
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_TTS,
      );

  static const _ttsCategory =
      model_pb.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
}
