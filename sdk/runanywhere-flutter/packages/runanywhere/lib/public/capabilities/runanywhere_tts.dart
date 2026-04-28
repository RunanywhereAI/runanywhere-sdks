// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_tts.dart — v4 TTS (text-to-speech) capability.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_tts.dart' show racAudioFormatPcm, racAudioFormatWav;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/generation_types.dart';

/// Map a Dart [AudioFormat] to the C enum int used by the TTS bridge.
int _ttsAudioFormatToC(AudioFormat fmt) {
  switch (fmt) {
    case AudioFormat.wav:
      return racAudioFormatWav;
    case AudioFormat.pcm:
      return racAudioFormatPcm;
    default:
      // PCM is the default for unsupported encodings on the TTS path.
      return racAudioFormatPcm;
  }
}

/// TTS (text-to-speech) capability surface.
///
/// Access via `RunAnywhereSDK.instance.tts`.
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
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadTTSVoice');
    logger.info('Loading TTS voice: $voiceId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: voiceId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == voiceId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('TTS voice not found: $voiceId');
      }

      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'TTS voice is not downloaded. Call downloadModel() first.',
        );
      }

      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKError.modelNotFound(
            'Could not resolve TTS voice path for: $voiceId');
      }

      if (DartBridge.tts.isLoaded) {
        DartBridge.tts.unload();
      }

      logger.debug('Loading TTS voice via C++ bridge: $resolvedPath');
      await DartBridge.tts.loadVoice(resolvedPath, voiceId, model.name);

      if (!DartBridge.tts.isLoaded) {
        throw SDKError.ttsNotAvailable(
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
      throw SDKError.notInitialized();
    }
    DartBridge.tts.unload();
  }

  /// Synthesize speech from text. Rate/pitch/volume default to 1.0/1.0/1.0.
  ///
  /// When [options] is supplied, all other rate/pitch/volume args are
  /// ignored and the [TTSOptions] fields take precedence. Mirrors
  /// Swift's `synthesize(_:options:)`.
  Future<TTSResult> synthesize(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    TTSOptions? options,
  }) async {
    final effectiveOptions = options ??
        TTSOptions(rate: rate, pitch: pitch, volume: volume);
    return _synthesizeWith(text, effectiveOptions);
  }

  Future<TTSResult> _synthesizeWith(String text, TTSOptions options) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!DartBridge.tts.isLoaded) {
      throw SDKError.ttsNotAvailable(
        'No TTS voice loaded. Call loadTTSVoice() first.',
      );
    }

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
        rate: options.rate,
        pitch: options.pitch,
        volume: options.volume,
        language: options.language,
        audioFormat: _ttsAudioFormatToC(options.audioFormat),
        sampleRate: options.sampleRate,
        useSsml: options.useSSML,
        voiceId: options.voice,
      );
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;

      final audioSizeBytes = result.samples.length * 4;

      TelemetryService.shared.trackSynthesis(
        voiceId: voiceId,
        modelName: modelName,
        textLength: text.length,
        audioDurationMs: result.durationMs,
        latencyMs: latencyMs,
        sampleRate: result.sampleRate,
        audioSizeBytes: audioSizeBytes,
      );

      final metadata = TTSSynthesisMetadata(
        voice: voiceId,
        language: options.language,
        processingTime: latencyMs / 1000.0,
        characterCount: text.length,
      );

      logger.info(
          'Synthesis complete: ${result.samples.length} samples, ${result.sampleRate} Hz');
      return TTSResult(
        samples: result.samples,
        sampleRate: result.sampleRate,
        durationMs: result.durationMs,
        format: options.audioFormat,
        metadata: metadata,
        timestamp: DateTime.now(),
      );
    } on SDKError {
      rethrow;
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

  /// Stream synthesis chunks as they are generated. Mirrors Swift's
  /// `synthesizeStream(_:options:onAudioChunk:)`.
  ///
  /// Yields PCM Float32 chunks (~100 ms each) as `Uint8List` byte
  /// buffers. Use [onAudioChunk] for callback-style consumption (the
  /// callback fires once per chunk in addition to the stream).
  Stream<Uint8List> synthesizeStream(
    String text, {
    TTSOptions options = const TTSOptions(),
    void Function(Uint8List chunk)? onAudioChunk,
  }) async* {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }
    if (!DartBridge.tts.isLoaded) {
      throw SDKError.ttsNotAvailable('No TTS voice loaded.');
    }

    await for (final chunk in DartBridge.tts.synthesizeStream(
      text,
      rate: options.rate,
      pitch: options.pitch,
      volume: options.volume,
      language: options.language,
      audioFormat: _ttsAudioFormatToC(options.audioFormat),
      sampleRate: options.sampleRate,
      useSsml: options.useSSML,
      voiceId: options.voice,
    )) {
      // Convert Float32 samples to bytes for transport.
      final bytes = chunk.samples.buffer.asUint8List(
        chunk.samples.offsetInBytes,
        chunk.samples.lengthInBytes,
      );
      onAudioChunk?.call(bytes);
      yield bytes;
    }
  }

  /// Stop in-flight synthesis (no-op if nothing is playing). Mirrors
  /// Swift's `RunAnywhere.stopSynthesis()`.
  Future<void> stopSynthesis() async {
    DartBridge.tts.stop();
  }

  /// Synthesize-and-play: synthesizes audio for [text] then plays it
  /// through the platform audio output. Mirrors Swift's
  /// `RunAnywhere.speak(_:options:)`.
  ///
  /// NOTE: Audio playback is delegated to the host application — Flutter
  /// has no platform audio player baked into the SDK. The caller can
  /// chain this onto their own `audioplayers` / `just_audio` instance
  /// using the returned [TTSResult.samples]. The metadata-only
  /// [TTSSpeakResult] is returned as a parity-shape with Swift.
  Future<TTSSpeakResult> speak(
    String text, {
    TTSOptions options = const TTSOptions(),
  }) async {
    final output = await _synthesizeWith(text, options);
    _isSpeaking = true;
    try {
      // Host app is responsible for actual playback. We surface the
      // samples in the returned result so the caller can route them.
      return TTSSpeakResult.from(output);
    } finally {
      _isSpeaking = false;
    }
  }

  bool _isSpeaking = false;

  /// True while a `speak()` invocation is in flight. Mirrors Swift's
  /// `isSpeaking` getter.
  bool get isSpeaking => _isSpeaking;

  /// Stop ongoing playback initiated by `speak()`. Mirrors Swift's
  /// `stopSpeaking()`.
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    await stopSynthesis();
  }

  /// List available TTS voice ids. Mirrors Swift's `availableTTSVoices`
  /// — convenience wrapper around `models.available()` filtered by the
  /// speech-synthesis category.
  Future<List<String>> availableVoices() async {
    final all = await RunAnywhereModels.shared.available();
    return all
        .where((m) => m.category == ModelCategory.speechSynthesis)
        .map((m) => m.id)
        .toList(growable: false);
  }
}
