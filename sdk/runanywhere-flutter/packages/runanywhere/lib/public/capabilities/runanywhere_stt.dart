// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 STT capability — aligned to Swift + proto. Returns proto STTOutput.

import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/generated/stt_options_helpers.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_stt.dart'
    show racAudioFormatWav;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// STT (speech-to-text) capability surface.
///
/// Access via `RunAnywhereSDK.instance.stt`. Mirrors Swift's
/// `RunAnywhere+STT.swift`. Returns proto [STTOutput].
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
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadSTTModel');
    logger.info('Loading STT model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKException.modelNotFound('STT model not found: $modelId');
      }

      if (model.localPath == null) {
        throw SDKException.modelNotDownloaded(
          'STT model is not downloaded. Call downloadModel() first.',
        );
      }

      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKException.modelNotFound(
            'Could not resolve STT model file path for: $modelId');
      }

      if (DartBridge.stt.isLoaded) {
        DartBridge.stt.unload();
      }

      logger.debug('Loading STT model via C++ bridge: $resolvedPath');
      await DartBridge.stt.loadModel(resolvedPath, modelId, model.name);

      if (!DartBridge.stt.isLoaded) {
        throw SDKException.sttNotAvailable(
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
      throw SDKException.notInitialized();
    }
    DartBridge.stt.unload();
  }

  /// Transcribe audio data to a proto [STTOutput]. Mirrors Swift's
  /// `transcribe(_ audio:options:)` (the rich variant).
  Future<STTOutput> transcribe(
    Uint8List audio, [
    STTOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!DartBridge.stt.isLoaded) {
      throw SDKException.sttNotAvailable(
        'No STT model loaded. Call loadSTTModel() first.',
      );
    }

    final logger = SDKLogger('RunAnywhere.Transcribe');
    final opts = options ?? STTOptions();
    final modelId = currentModelId ?? 'unknown';
    final modelInfo =
        await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;

    // Audio length estimate: PCM16 at 16kHz mono → bytes / 2 / sampleRate * 1000.
    const sampleRate = 16000;
    final estimatedDurationMs = (audio.length / 2 / sampleRate * 1000).round();

    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      final result = await DartBridge.stt.transcribe(
        audio,
        sampleRate: sampleRate,
        language: opts.language.bcp47 ?? 'en',
        audioFormat: racAudioFormatWav,
        enablePunctuation: opts.hasEnablePunctuation()
            ? opts.enablePunctuation
            : true,
        enableDiarization: opts.enableDiarization,
        maxSpeakers: opts.maxSpeakers,
        enableTimestamps: opts.enableWordTimestamps,
        detectLanguage: opts.language == STTLanguage.STT_LANGUAGE_AUTO,
      );
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
      final audioDurationMs =
          result.durationMs > 0 ? result.durationMs : estimatedDurationMs;

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

      logger.info('Transcription complete: ${result.text.length} chars, '
          'confidence: ${result.confidence}');

      final metadata = TranscriptionMetadata(
        modelId: modelId,
        processingTimeMs: Int64(latencyMs),
        audioLengthMs: Int64(audioDurationMs),
        realTimeFactor: audioDurationMs > 0
            ? latencyMs / audioDurationMs.toDouble()
            : 0.0,
      );

      return STTOutput(
        text: result.text,
        language: STTLanguageBcp47.fromBcp47(result.language),
        confidence: result.confidence,
        metadata: metadata,
      );
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

  /// Streaming transcription. Yields a single final partial then resolves
  /// to the full [STTOutput]. The underlying C bridge currently surfaces
  /// only synchronous results.
  Future<STTOutput> transcribeStream(
    Uint8List audio, {
    STTOptions? options,
    void Function(STTPartialResult partial)? onPartialResult,
  }) async {
    final result = await transcribe(audio, options);
    onPartialResult?.call(STTPartialResult(
      text: result.text,
      isFinal: true,
      stability: result.confidence,
    ));
    return result;
  }

  /// Symmetric with Swift's `processStreamingAudio`. Float32 PCM samples
  /// at 16kHz are forwarded to the synchronous transcribe path.
  Future<void> processStreamingAudio(
    Float32List samples, {
    STTOptions? options,
  }) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!DartBridge.stt.isLoaded) {
      throw SDKException.sttNotAvailable('No STT model loaded.');
    }
    final byteData = ByteData(samples.lengthInBytes);
    for (var i = 0; i < samples.length; i++) {
      byteData.setFloat32(i * 4, samples[i], Endian.little);
    }
    await transcribe(byteData.buffer.asUint8List(), options);
  }

  /// Transcribe a Float32 PCM buffer directly. Mirrors Swift's
  /// `transcribeBuffer`.
  Future<STTOutput> transcribeBuffer(
    Float32List samples, {
    STTOptions? options,
  }) async {
    final byteData = ByteData(samples.lengthInBytes);
    for (var i = 0; i < samples.length; i++) {
      byteData.setFloat32(i * 4, samples[i], Endian.little);
    }
    return transcribe(byteData.buffer.asUint8List(), options);
  }
}
