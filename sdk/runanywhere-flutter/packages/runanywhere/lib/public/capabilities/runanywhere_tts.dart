// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 TTS capability — aligned to Swift + proto. Returns proto TTSOutput.

import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/features/tts/system_tts_service.dart' as sys_tts;
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

/// Sentinel voice ID for the platform's built-in System TTS engine
/// (iOS AVSpeechSynthesizer, Android android.speech.tts.TextToSpeech).
/// Registered as a pseudo-model with no download URL; routed through
/// [sys_tts.SystemTTSService] (flutter_tts) instead of the C++ bridge.
const String _systemTtsVoiceId = 'system-tts';

/// TTS (text-to-speech) capability surface.
///
/// Access via `RunAnywhereSDK.instance.tts`. Mirrors Swift's
/// `RunAnywhere+TTS.swift`. Returns proto [TTSOutput].
class RunAnywhereTTS {
  RunAnywhereTTS._();
  static final RunAnywhereTTS _instance = RunAnywhereTTS._();
  static RunAnywhereTTS get shared => _instance;

  /// Lazy-initialized System TTS service (flutter_tts wrapper). Created on
  /// first use of the `system-tts` pseudo-voice; cleaned up on unload.
  sys_tts.SystemTTSService? _systemTts;
  bool _systemTtsLoaded = false;

  /// True when a TTS voice is currently loaded.
  bool get isLoaded => _systemTtsLoaded || DartBridge.tts.isLoaded;

  /// Currently-loaded TTS voice ID, or null.
  String? get currentVoiceId =>
      _systemTtsLoaded ? _systemTtsVoiceId : DartBridge.tts.currentVoiceId;

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
      // System TTS short-circuit: route to platform engine (AVSpeechSynthesizer
      // on iOS, android.speech.tts.TextToSpeech on Android) via flutter_tts.
      // The pseudo-model has no download URL / localPath, so it must bypass
      // the C++ voice-load path that expects an on-disk model file.
      if (voiceId == _systemTtsVoiceId) {
        await _loadSystemTTS();

        final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
        TelemetryService.shared.trackModelLoad(
          modelId: voiceId,
          modelType: 'tts',
          success: true,
          loadTimeMs: loadTimeMs,
        );
        EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: voiceId));
        logger.info('TTS voice loaded: System TTS');
        return;
      }

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

      // Unload any prior voice (native OR system) before loading the next.
      await _unloadCurrent();

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
    await _unloadCurrent();
  }

  /// Internal: unload whichever voice is currently active (system or native).
  Future<void> _unloadCurrent() async {
    if (_systemTtsLoaded) {
      await _systemTts?.cleanup();
      _systemTtsLoaded = false;
    }
    if (DartBridge.tts.isLoaded) {
      DartBridge.tts.unload();
    }
  }

  /// Internal: initialize / re-initialize the System TTS service. Unloads any
  /// native voice first so the two paths never claim to be loaded at once.
  Future<void> _loadSystemTTS() async {
    await _unloadCurrent();
    _systemTts ??= sys_tts.SystemTTSService();
    await _systemTts!.initialize();
    _systemTtsLoaded = true;
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
    if (!isLoaded) {
      throw SDKException.ttsNotAvailable(
        'No TTS voice loaded. Call loadTTSVoice() first.',
      );
    }

    final opts = options ?? TTSOptions();
    final logger = SDKLogger('RunAnywhere.Synthesize');
    logger.debug(
        'Synthesizing: "${text.substring(0, text.length.clamp(0, 50))}..."');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // System TTS short-circuit: flutter_tts plays audio directly through the
    // platform engine and does not expose raw PCM samples. We return an empty
    // audio buffer with accurate timing metadata so callers can drive UI
    // state; the actual audible output is produced by the platform engine.
    if (_systemTtsLoaded) {
      return _synthesizeSystemTTS(text, opts, logger, startTime);
    }

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
    if (!isLoaded) {
      throw SDKException.ttsNotAvailable('No TTS voice loaded.');
    }
    final opts = options ?? TTSOptions();

    // System TTS does not expose per-chunk PCM; plays through the platform
    // engine and returns no samples. Emit a single empty chunk after playback
    // completes so stream consumers can terminate cleanly.
    if (_systemTtsLoaded) {
      final output = await synthesize(text, opts);
      final bytes = Uint8List.fromList(output.audioData);
      onAudioChunk?.call(bytes);
      yield bytes;
      return;
    }

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
    if (_systemTtsLoaded) {
      await _systemTts?.stop();
      return;
    }
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

  /// Internal: synthesize via the platform's System TTS engine. flutter_tts
  /// plays audio directly (no PCM samples exposed), so we return an empty
  /// [TTSOutput] with accurate timing metadata. Callers that auto-play PCM
  /// should treat an empty `audioData` as "already playing via platform".
  Future<TTSOutput> _synthesizeSystemTTS(
    String text,
    TTSOptions opts,
    SDKLogger logger,
    int startTime,
  ) async {
    const voiceId = _systemTtsVoiceId;
    try {
      final service = _systemTts;
      if (service == null) {
        throw SDKException.ttsNotAvailable('System TTS not initialized.');
      }

      await service.synthesize(sys_tts.TTSInput(
        text: text,
        voiceId: opts.hasVoice() && opts.voice.isNotEmpty
            ? opts.voice
            : 'system',
        rate: opts.hasSpeakingRate() ? opts.speakingRate : 1.0,
        pitch: opts.hasPitch() ? opts.pitch : 1.0,
      ));

      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;

      TelemetryService.shared.trackSynthesis(
        voiceId: voiceId,
        modelName: 'System TTS',
        textLength: text.length,
        audioDurationMs: latencyMs,
        latencyMs: latencyMs,
        sampleRate: 22050,
        audioSizeBytes: 0,
      );

      logger.info('System TTS synthesis complete (${latencyMs}ms wall-clock)');

      return TTSOutput(
        audioData: Uint8List(0),
        audioFormat: pb_models.AudioFormat.AUDIO_FORMAT_PCM,
        sampleRate: 22050,
        durationMs: Int64(latencyMs),
        metadata: TTSSynthesisMetadata(
          voiceId: voiceId,
          processingTimeMs: Int64(latencyMs),
          characterCount: text.length,
          audioDurationMs: Int64(latencyMs),
        ),
        timestampMs: Int64(DateTime.now().millisecondsSinceEpoch),
      );
    } catch (e) {
      TelemetryService.shared.trackError(
        errorCode: 'synthesis_failed',
        errorMessage: e.toString(),
        context: {'voice_id': voiceId, 'text_length': text.length},
      );
      logger.error('System TTS synthesis failed: $e');
      rethrow;
    }
  }
}
