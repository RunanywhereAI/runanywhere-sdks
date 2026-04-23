// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_tts.dart — v4 TTS (text-to-speech) capability.

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/generation_types.dart';

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
  Future<TTSResult> synthesize(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
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
        rate: rate,
        pitch: pitch,
        volume: volume,
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

      logger.info(
          'Synthesis complete: ${result.samples.length} samples, ${result.sampleRate} Hz');
      return TTSResult(
        samples: result.samples,
        sampleRate: result.sampleRate,
        durationMs: result.durationMs,
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
}
