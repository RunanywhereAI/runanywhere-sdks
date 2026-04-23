// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_stt.dart — v4 STT (speech-to-text) capability.

import 'dart:typed_data';

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

/// STT (speech-to-text) capability surface.
///
/// Access via `RunAnywhereSDK.instance.stt`.
class RunAnywhereSTT {
  RunAnywhereSTT._();
  static final RunAnywhereSTT _instance = RunAnywhereSTT._();
  static RunAnywhereSTT get shared => _instance;

  /// True when an STT model is currently loaded.
  bool get isLoaded => DartBridge.stt.isLoaded;

  /// Currently-loaded STT model ID, or null.
  String? get currentModelId => DartBridge.stt.currentModelId;

  /// Currently-loaded STT model as `ModelInfo`, or null.
  Future<ModelInfo?> currentModel() async {
    final modelId = currentModelId;
    if (modelId == null) return null;
    final models = await RunAnywhereModels.shared.available();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );
  }

  /// Load an STT model by ID.
  Future<void> load(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadSTTModel');
    logger.info('Loading STT model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('STT model not found: $modelId');
      }

      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'STT model is not downloaded. Call downloadModel() first.',
        );
      }

      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKError.modelNotFound(
            'Could not resolve STT model file path for: $modelId');
      }

      if (DartBridge.stt.isLoaded) {
        DartBridge.stt.unload();
      }

      logger.debug('Loading STT model via C++ bridge: $resolvedPath');
      await DartBridge.stt.loadModel(resolvedPath, modelId, model.name);

      if (!DartBridge.stt.isLoaded) {
        throw SDKError.sttNotAvailable(
          'STT model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;

      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'stt',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
      logger.info('STT model loaded: ${model.name}');
    } catch (e) {
      logger.error('Failed to load STT model: $e');
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'stt',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'stt_model_load_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Unload the currently-loaded STT model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }
    DartBridge.stt.unload();
  }

  /// Transcribe audio data to text. Expects PCM16 at 16kHz mono.
  Future<String> transcribe(Uint8List audioData) async {
    final result = await transcribeWithResult(audioData);
    return result.text;
  }

  /// Transcribe audio data with detailed result (confidence, language, ...).
  Future<STTResult> transcribeWithResult(Uint8List audioData) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!DartBridge.stt.isLoaded) {
      throw SDKError.sttNotAvailable(
        'No STT model loaded. Call loadSTTModel() first.',
      );
    }

    final logger = SDKLogger('RunAnywhere.Transcribe');
    logger.debug('Transcribing ${audioData.length} bytes with details...');
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final modelId = currentModelId ?? 'unknown';

    final modelInfo =
        await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;

    // Duration (PCM16 at 16kHz mono): bytes / 2 / 16000 * 1000 == bytes/32
    final calculatedDurationMs = (audioData.length / 32).round();

    try {
      final result = await DartBridge.stt.transcribe(audioData);
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;

      final audioDurationMs =
          result.durationMs > 0 ? result.durationMs : calculatedDurationMs;

      final wordCount = result.text.trim().isEmpty
          ? 0
          : result.text.trim().split(RegExp(r'\s+')).length;

      TelemetryService.shared.trackTranscription(
        modelId: modelId,
        modelName: modelName,
        audioDurationMs: audioDurationMs,
        latencyMs: latencyMs,
        wordCount: wordCount,
        confidence: result.confidence,
        language: result.language,
        isStreaming: false,
      );

      logger.info(
          'Transcription complete: ${result.text.length} chars, confidence: ${result.confidence}');
      return STTResult(
        text: result.text,
        confidence: result.confidence,
        durationMs: audioDurationMs,
        language: result.language,
      );
    } on SDKError {
      rethrow;
    } catch (e) {
      TelemetryService.shared.trackError(
        errorCode: 'transcription_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      logger.error('Transcription failed: $e');
      rethrow;
    }
  }
}
