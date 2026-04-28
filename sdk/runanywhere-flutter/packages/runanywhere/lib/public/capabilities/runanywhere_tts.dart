// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 TTS capability — aligned to Swift + proto. Returns proto TTSOutput.

import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart' as pb_models;
import 'package:runanywhere/generated/tts_options.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_tts.dart' show racAudioFormatPcm;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// TTS (text-to-speech) capability surface.
///
/// Access via `RunAnywhereSDK.instance.tts`. Mirrors Swift's
/// `RunAnywhere+TTS.swift`. Returns proto [TTSOutput].
class RunAnywhereTTS {
  RunAnywhereTTS._();
  static final RunAnywhereTTS _instance = RunAnywhereTTS._();
  static RunAnywhereTTS get shared => _instance;

  /// True when a TTS voice is currently loaded.
  bool get isLoaded => DartBridge.tts.isLoaded;

  /// Currently-loaded TTS voice ID, or null.
  String? get currentVoiceId => DartBridge.tts.currentVoiceId;

  /// Currently-loaded TTS voice as `ModelInfo`, or null.
  Future<ModelInfo?> currentVoice() async {
    final voiceId = currentVoiceId;
    if (voiceId == null) return null;
    final models = await RunAnywhereModels.shared.available();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == voiceId,
          orElse: () => null,
        );
  }

  /// Load a TTS voice by ID.
  Future<void> loadVoice(String voiceId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadTTSVoice');
    logger.info('Loading TTS voice: $voiceId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: voiceId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == voiceId).firstOrNull;

      if (model == null) {
        throw SDKException.modelNotFound('TTS voice not found: $voiceId');
      }

      if (model.localPath == null) {
        throw SDKException.modelNotDownloaded(
          'TTS voice is not downloaded. Call downloadModel() first.',
        );
      }

      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKException.modelNotFound(
            'Could not resolve TTS voice path for: $voiceId');
      }

      if (DartBridge.tts.isLoaded) {
        DartBridge.tts.unload();
      }

      logger.debug('Loading TTS voice via C++ bridge: $resolvedPath');
      await DartBridge.tts.loadVoice(resolvedPath, voiceId, model.name);

      if (!DartBridge.tts.isLoaded) {
        throw SDKException.ttsNotAvailable(
          'TTS voice failed to load - voice may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;

      TelemetryService.shared.trackModelLoad(
        modelId: voiceId,
        modelType: 'tts',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: voiceId));
      logger.info('TTS voice loaded: ${model.name}');
    } catch (e) {
      logger.error('Failed to load TTS voice: $e');
      TelemetryService.shared.trackModelLoad(
        modelId: voiceId,
        modelType: 'tts',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'tts_voice_load_failed',
        errorMessage: e.toString(),
        context: {'voice_id': voiceId},
      );
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: voiceId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Unload the currently-loaded TTS voice.
  Future<void> unloadVoice() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridge.tts.unload();
  }

  /// Synthesize speech from [text]. Returns proto [TTSOutput] with PCM
  /// float samples encoded as bytes in `audioData`. Mirrors Swift's
  /// `synthesize(_:options:)`.
  Future<TTSOutput> synthesize(
    String text, [
    TTSOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!DartBridge.tts.isLoaded) {
      throw SDKException.ttsNotAvailable(
        'No TTS voice loaded. Call loadTTSVoice() first.',
      );
    }

    final opts = options ?? TTSOptions();
    final logger = SDKLogger('RunAnywhere.Synthesize');
    logger.debug(
        'Synthesizing: "${text.substring(0, text.length.clamp(0, 50))}..."');
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final voiceId = currentVoiceId ?? 'unknown';

    final modelInfo =
        await DartBridgeModelRegistry.instance.getPublicModel(voiceId);
    final modelName = modelInfo?.name;

    try {
      final result = await DartBridge.tts.synthesize(
        text,
        rate: opts.hasSpeakingRate() ? opts.speakingRate : 1.0,
        pitch: opts.hasPitch() ? opts.pitch : 1.0,
        volume: opts.hasVolume() ? opts.volume : 1.0,
        language: opts.hasLanguageCode() ? opts.languageCode : 'en-US',
        audioFormat: racAudioFormatPcm,
        sampleRate: 22050,
        useSsml: opts.enableSsml,
        voiceId: opts.hasVoice() ? opts.voice : null,
      );
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
      final audioBytes = Uint8List.view(result.samples.buffer);

      TelemetryService.shared.trackSynthesis(
        voiceId: voiceId,
        modelName: modelName,
        textLength: text.length,
        audioDurationMs: result.durationMs,
        latencyMs: latencyMs,
        sampleRate: result.sampleRate,
        audioSizeBytes: audioBytes.length,
      );

      final metadata = TTSSynthesisMetadata(
        voiceId: voiceId,
        processingTimeMs: Int64(latencyMs),
        characterCount: text.length,
        audioDurationMs: Int64(result.durationMs),
      );

      logger.info(
          'Synthesis complete: ${result.samples.length} samples, ${result.sampleRate} Hz');
      return TTSOutput(
        audioData: audioBytes,
        audioFormat: pb_models.AudioFormat.AUDIO_FORMAT_PCM,
        sampleRate: result.sampleRate,
        durationMs: Int64(result.durationMs),
        metadata: metadata,
        timestampMs: Int64(DateTime.now().millisecondsSinceEpoch),
      );
    } catch (e) {
      TelemetryService.shared.trackError(
        errorCode: 'synthesis_failed',
        errorMessage: e.toString(),
        context: {'voice_id': voiceId, 'text_length': text.length},
      );
      logger.error('Synthesis failed: $e');
      rethrow;
    }
  }

  /// Stream synthesis chunks as they are generated. Yields raw byte
  /// buffers (PCM Float32 samples encoded as bytes).
  Stream<Uint8List> synthesizeStream(
    String text, {
    TTSOptions? options,
    void Function(Uint8List chunk)? onAudioChunk,
  }) async* {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!DartBridge.tts.isLoaded) {
      throw SDKException.ttsNotAvailable('No TTS voice loaded.');
    }
    final opts = options ?? TTSOptions();

    await for (final chunk in DartBridge.tts.synthesizeStream(
      text,
      rate: opts.hasSpeakingRate() ? opts.speakingRate : 1.0,
      pitch: opts.hasPitch() ? opts.pitch : 1.0,
      volume: opts.hasVolume() ? opts.volume : 1.0,
      language: opts.hasLanguageCode() ? opts.languageCode : 'en-US',
      audioFormat: racAudioFormatPcm,
      sampleRate: 22050,
      useSsml: opts.enableSsml,
      voiceId: opts.hasVoice() ? opts.voice : null,
    )) {
      final bytes = chunk.samples.buffer.asUint8List(
        chunk.samples.offsetInBytes,
        chunk.samples.lengthInBytes,
      );
      onAudioChunk?.call(bytes);
      yield bytes;
    }
  }

  /// Stop in-flight synthesis (no-op if nothing is playing).
  Future<void> stopSynthesis() async {
    DartBridge.tts.stop();
  }

  /// Synthesize-and-play. Mirrors Swift's `RunAnywhere.speak(_:options:)`.
  /// Returns proto [TTSSpeakResult] (metadata-only view).
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

  bool _isSpeaking = false;

  /// True while a `speak()` invocation is in flight.
  bool get isSpeaking => _isSpeaking;

  /// Stop ongoing playback.
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    await stopSynthesis();
  }

  /// List available TTS voice ids.
  Future<List<String>> availableVoices() async {
    final all = await RunAnywhereModels.shared.available();
    return all
        .where((m) => m.category == ModelCategory.speechSynthesis)
        .map((m) => m.id)
        .toList(growable: false);
  }
}
