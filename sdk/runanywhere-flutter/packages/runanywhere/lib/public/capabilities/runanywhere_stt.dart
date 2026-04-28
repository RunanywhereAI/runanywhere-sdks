// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_stt.dart — v4 STT (speech-to-text) capability.

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
import 'package:runanywhere/native/dart_bridge_stt.dart' show racAudioFormatWav, racAudioFormatPcm, racAudioFormatMp3, racAudioFormatOpus, racAudioFormatAac, racAudioFormatFlac;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/generation_types.dart';

/// Map a Dart [AudioFormat] to the C enum int used by the STT bridge.
int _sttAudioFormatToC(AudioFormat fmt) {
  switch (fmt) {
    case AudioFormat.wav:
      return racAudioFormatWav;
    case AudioFormat.pcm:
      return racAudioFormatPcm;
    case AudioFormat.mp3:
      return racAudioFormatMp3;
    case AudioFormat.opus:
      return racAudioFormatOpus;
    case AudioFormat.flac:
      return racAudioFormatFlac;
    case AudioFormat.m4a:
      return racAudioFormatAac;
  }
}

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
  ///
  /// [options] when supplied controls language detection, format,
  /// timestamps, etc. Mirrors Swift's `transcribeWithOptions`.
  Future<STTResult> transcribeWithResult(
    Uint8List audioData, {
    STTOptions? options,
  }) async {
    return transcribeWithOptions(audioData, options ?? const STTOptions());
  }

  /// Transcribe with explicit [STTOptions]. Mirrors Swift's
  /// `RunAnywhere.transcribeWithOptions(_:options:)`.
  Future<STTResult> transcribeWithOptions(
    Uint8List audioData,
    STTOptions options,
  ) async {
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

    // Duration (PCM16 at 16kHz mono): bytes / 2 / sampleRate * 1000.
    final estimatedDurationMs =
        (audioData.length / 2 / options.sampleRate * 1000).round();

    try {
      final result = await DartBridge.stt.transcribe(
        audioData,
        sampleRate: options.sampleRate,
        language: options.language ?? 'en',
        audioFormat: _sttAudioFormatToC(options.audioFormat),
        enablePunctuation: options.enablePunctuation,
        enableDiarization: options.enableDiarization,
        maxSpeakers: options.maxSpeakers,
        enableTimestamps: options.enableTimestamps,
        detectLanguage: options.detectLanguage,
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

      final metadata = TranscriptionMetadata(
        modelId: modelId,
        processingTime: latencyMs / 1000.0,
        audioLength: audioDurationMs / 1000.0,
      );

      logger.info(
          'Transcription complete: ${result.text.length} chars, confidence: ${result.confidence}');
      return STTResult(
        text: result.text,
        confidence: result.confidence,
        durationMs: audioDurationMs,
        language: result.language,
        metadata: metadata,
        timestamp: DateTime.now(),
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

  /// Streaming transcription with partial-result callbacks.
  ///
  /// Mirrors Swift's `transcribeStream(audioData:options:onPartialResult:)`.
  /// Currently the underlying C bridge does not surface partial events
  /// directly; this implementation wraps the synchronous transcription
  /// and emits a single final partial before returning the [STTResult].
  /// When the C bridge gains a streaming entry point this will switch
  /// over without changing the Dart signature.
  Future<STTResult> transcribeStream(
    Uint8List audioData, {
    STTOptions options = const STTOptions(),
    void Function(STTPartialResult partial)? onPartialResult,
  }) async {
    final result = await transcribeWithOptions(audioData, options);

    // Emit a final partial mirroring Swift's callback shape.
    onPartialResult?.call(STTPartialResult(
      transcript: result.text,
      confidence: result.confidence,
      isFinal: true,
      language: result.language,
      timestamps: result.wordTimestamps,
      alternatives: result.alternatives,
    ));

    return result;
  }

  /// Process audio samples for streaming transcription. Symmetric with
  /// Swift's `processStreamingAudio(_:options:)`.
  ///
  /// [samples] - Float32 PCM samples at the [STTOptions.sampleRate].
  Future<void> processStreamingAudio(
    Float32List samples, {
    STTOptions options = const STTOptions(),
  }) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }
    if (!DartBridge.stt.isLoaded) {
      throw SDKError.sttNotAvailable('No STT model loaded.');
    }
    // Convert Float32List to Uint8List for the C bridge.
    final byteData = ByteData(samples.lengthInBytes);
    for (var i = 0; i < samples.length; i++) {
      byteData.setFloat32(i * 4, samples[i], Endian.little);
    }
    await transcribeWithOptions(
      byteData.buffer.asUint8List(),
      options,
    );
  }

  /// Transcribe a Float32 PCM buffer directly. Symmetric with Swift's
  /// `transcribeBuffer(_:language:)` overload.
  Future<STTResult> transcribeBuffer(
    Float32List samples, {
    String? language,
  }) async {
    final byteData = ByteData(samples.lengthInBytes);
    for (var i = 0; i < samples.length; i++) {
      byteData.setFloat32(i * 4, samples[i], Endian.little);
    }
    final options = STTOptions(
      language: language ?? const STTOptions().language,
      audioFormat: AudioFormat.pcm,
    );
    return transcribeWithOptions(byteData.buffer.asUint8List(), options);
  }
}
