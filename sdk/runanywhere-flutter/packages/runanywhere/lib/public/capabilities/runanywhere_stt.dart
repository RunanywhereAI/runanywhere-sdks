// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 STT capability — aligned to Swift + proto. Returns proto STTOutput.

import 'dart:async';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/generated/stt_options_helpers.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_stt_streaming.dart';
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

  bool _isStreaming = false;

  /// True when an STT model is currently loaded.
  bool get isLoaded => DartBridge.stt.isLoaded;

  /// True when a streaming transcription session is active (canonical §4).
  bool get isStreaming => _isStreaming;

  /// Stop any active streaming transcription session (canonical §4).
  Future<void> stopStreamingTranscription() async {
    _isStreaming = false;
    // The native streaming path self-terminates when the stream consumer
    // cancels; this flag is the public-facing gate for the canonical property.
  }

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

      if (model.localPath.isEmpty) {
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
    final opts = _effectiveOptions(options ?? STTOptions());
    final modelId = currentModelId ?? 'unknown';
    final modelInfo =
        await DartBridgeModelRegistry.instance.getProtoModel(modelId);
    final modelName = modelInfo?.name;

    // Audio length estimate: PCM16 at 16kHz mono → bytes / 2 / sampleRate * 1000.
    const sampleRate = 16000;
    final estimatedDurationMs = (audio.length / 2 / sampleRate * 1000).round();

    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      final result = await DartBridge.stt.transcribeProto(audio, opts);
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
      final resultDurationMs =
          result.hasDurationMs() ? result.durationMs.toInt() : 0;
      final audioDurationMs =
          resultDurationMs > 0 ? resultDurationMs : estimatedDurationMs;

      final wordCount = result.text.trim().isEmpty
          ? 0
          : result.text.trim().split(RegExp(r'\s+')).length;
      final language = result.languageCode.isNotEmpty
          ? result.languageCode
          : result.language.name;

      TelemetryService.shared.trackTranscription(
        modelId: modelId,
        modelName: modelName,
        audioDurationMs: audioDurationMs,
        latencyMs: latencyMs,
        wordCount: wordCount,
        confidence: result.confidence,
        language: language,
        isStreaming: false,
      );

      logger.info('Transcription complete: ${result.text.length} chars, '
          'confidence: ${result.confidence}');

      return result;
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

  /// Streaming transcription. Yields a real partial event for every
  /// callback fired by `rac_stt_component_transcribe_stream` and
  /// completes when the C bridge signals `is_final = true`.
  ///
  /// Cancellation: drop the [StreamSubscription] you obtained via
  /// `.listen(...)`. The native callback is automatically detached
  /// once the consumer cancels.
  Stream<STTPartialResult> transcribeStream(
    Uint8List audio, {
    STTOptions? options,
  }) {
    if (!SdkState.shared.isInitialized) {
      return Stream<STTPartialResult>.error(SDKException.notInitialized());
    }
    if (!DartBridge.stt.isLoaded) {
      return Stream<STTPartialResult>.error(SDKException.sttNotAvailable(
        'No STT model loaded. Call loadSTTModel() first.',
      ));
    }

    final opts = _effectiveOptions(options ?? STTOptions());
    final streaming = DartBridgeSttStreaming.transcribeStream(
      audio: audio,
      options: opts,
    );

    _isStreaming = true;

    final controller = StreamController<STTPartialResult>(sync: false);
    final sub = streaming.stream.listen(
      (event) {
        if (controller.isClosed) return;
        controller.add(event);
        if (event.isFinal) {
          unawaited(controller.close());
          _isStreaming = false;
        }
      },
      onError: (Object err, StackTrace stack) {
        if (!controller.isClosed) {
          controller.addError(err, stack);
          unawaited(controller.close());
        }
        _isStreaming = false;
      },
      onDone: () {
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
        _isStreaming = false;
      },
    );

    controller.onCancel = () {
      _isStreaming = false;
      streaming.onCancel();
      unawaited(sub.cancel());
    };

    return controller.stream;
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

  STTOptions _effectiveOptions(STTOptions options) {
    final opts = options.deepCopy();
    if (!opts.hasSampleRate()) {
      opts.sampleRate = 16000;
    }
    if (!opts.hasAudioFormat()) {
      opts.audioFormat = model_pb.AudioFormat.AUDIO_FORMAT_WAV;
    }
    if (!opts.hasEnablePunctuation()) {
      opts.enablePunctuation = true;
    }
    if (!opts.hasEnableWordTimestamps()) {
      opts.enableWordTimestamps = true;
    }
    if (!opts.hasDetectLanguage()) {
      opts.detectLanguage = opts.language == STTLanguage.STT_LANGUAGE_AUTO;
    }
    if (!opts.hasLanguageCode() &&
        opts.language != STTLanguage.STT_LANGUAGE_AUTO) {
      opts.languageCode = opts.language.bcp47 ?? 'en';
    }
    return opts;
  }
}
