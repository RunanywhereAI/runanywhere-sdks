// SPDX-License-Identifier: Apache-2.0
//
// STT capability backed by commons model lifecycle and lifecycle-owned
// generated-proto transcription.

import 'dart:async';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart'
    show ComponentLifecycleState, SDKComponent;
import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/generated/stt_options_helpers.dart';
import 'package:runanywhere/internal/sdk_event_factories.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';
import 'package:runanywhere/public/events/event_bus.dart';

/// STT (speech-to-text) capability surface.
///
/// Access via `RunAnywhereSDK.instance.stt`. Load/current/unload state is owned
/// by commons lifecycle; one-shot transcription uses the lifecycle-owned
/// generated-proto commons ABI.
class RunAnywhereSTT {
  RunAnywhereSTT._();
  static final RunAnywhereSTT _instance = RunAnywhereSTT._();
  static RunAnywhereSTT get shared => _instance;

  bool _isStreaming = false;

  /// True when commons lifecycle has a ready STT model.
  bool get isLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// True when a streaming transcription session is active.
  bool get isStreaming => _isStreaming;

  /// Stop any active streaming transcription session.
  Future<void> stopStreamingTranscription() async {
    _isStreaming = false;
  }

  /// Currently-loaded STT model ID from commons lifecycle, or null.
  String? get currentModelId {
    final snapshot = _lifecycleSnapshot;
    if (snapshot == null ||
        snapshot.state !=
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ||
        snapshot.modelId.isEmpty) {
      return null;
    }
    return snapshot.modelId;
  }

  /// Currently-loaded STT model as `ModelInfo`, or null.
  Future<ModelInfo?> currentModel() async {
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(
        category: _sttCategory,
        includeModelMetadata: true,
      ),
    );
    if (!current.found || current.modelId.isEmpty || !current.hasModel()) {
      return null;
    }
    return current.model;
  }

  /// Load an STT model by ID through commons lifecycle routing.
  Future<void> load(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadSTTModel');
    logger.info('Loading STT model: $modelId');

    EventBus.shared.publish(SdkEventFactory.modelLoadStarted(modelId));

    try {
      final result = await RunAnywhereModelLifecycle.shared.load(
        model_pb.ModelLoadRequest(
          modelId: modelId,
          category: _sttCategory,
          forceReload: true,
          validateAvailability: true,
        ),
      );
      if (!result.success) {
        throw SDKException.modelLoadFailed(
          modelId,
          result.errorMessage.isNotEmpty
              ? result.errorMessage
              : 'STT lifecycle load failed',
        );
      }

      EventBus.shared.publish(SdkEventFactory.modelLoadCompleted(modelId));
      logger.info('STT model loaded: $modelId');
    } catch (e) {
      logger.error('Failed to load STT model: $e');
      EventBus.shared.publish(SdkEventFactory.modelLoadFailed(modelId, e));
      rethrow;
    }
  }

  /// Unload the currently-loaded STT model through commons lifecycle routing.
  Future<void> unload() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final modelId = currentModelId ??
        (await RunAnywhereModelLifecycle.shared.current(
          model_pb.CurrentModelRequest(category: _sttCategory),
        ))
            .modelId;
    if (modelId.isEmpty) return;

    EventBus.shared.publish(SdkEventFactory.modelUnloadStarted(modelId));
    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: _sttCategory,
      ),
    );
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'STT lifecycle unload failed',
      );
    }
    _isStreaming = false;
    EventBus.shared.publish(SdkEventFactory.modelUnloadCompleted(modelId));
  }

  /// Transcribe audio data to a proto [STTOutput].
  Future<STTOutput> transcribe(
    Uint8List audio, [
    STTOptions? options,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return _transcribeAudioData(
      audio,
      options ?? STTOptions(),
    );
  }

  /// Streaming transcription.
  Stream<STTPartialResult> transcribeStream(
    Uint8List audio, {
    STTOptions? options,
  }) async* {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await _requireLoadedModelId();
    _effectiveOptions(options ?? STTOptions());
    throw SDKException.featureNotAvailable(
      'Lifecycle-owned STT streaming is unavailable in Flutter. '
      'Use transcribe() for one-shot STT until commons exposes '
      'rac_stt_transcribe_stream_lifecycle_proto.',
    );
  }

  /// Symmetric with Swift's `processStreamingAudio`. Float32 PCM samples
  /// at 16kHz are forwarded to the lifecycle-owned one-shot transcribe path.
  Future<void> processStreamingAudio(
    Float32List samples, {
    STTOptions? options,
  }) async {
    await transcribeBuffer(samples, options: options);
  }

  /// Transcribe a Float32 PCM buffer directly.
  Future<STTOutput> transcribeBuffer(
    Float32List samples, {
    STTOptions? options,
  }) async {
    final byteData = ByteData(samples.lengthInBytes);
    for (var i = 0; i < samples.length; i++) {
      byteData.setFloat32(i * 4, samples[i], Endian.little);
    }
    final opts = _effectiveOptions(options ?? STTOptions());
    opts.audioFormat = model_pb.AudioFormat.AUDIO_FORMAT_PCM;
    return _transcribeAudioData(
      byteData.buffer.asUint8List(),
      opts,
      encoding: STTAudioEncoding.STT_AUDIO_ENCODING_PCM_F32_LE,
      bitsPerSample: 32,
    );
  }

  Future<STTOutput> _transcribeAudioData(
    Uint8List audio,
    STTOptions options, {
    STTAudioEncoding? encoding,
    int? bitsPerSample,
  }) async {
    final modelId = await _requireLoadedModelId();
    final opts = _effectiveOptions(options);
    final sourceEncoding = encoding ?? _encodingForOptions(opts);

    final request = STTTranscriptionRequest(
      audio: STTAudioSource(
        audioData: audio,
        encoding: sourceEncoding,
        audioFormat: opts.audioFormat,
        sampleRate: opts.sampleRate,
        channels: 1,
        bitsPerSample: bitsPerSample ?? _bitsPerSample(sourceEncoding),
      ),
      options: opts,
      metadata: {'model_id': modelId},
    );

    return DartBridgeSTT.shared.transcribeLifecycleProto(request);
  }

  Future<String> _requireLoadedModelId() async {
    final snapshotModelId = currentModelId;
    if (snapshotModelId != null) {
      return snapshotModelId;
    }
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: _sttCategory),
    );
    if (current.found && current.modelId.isNotEmpty) {
      return current.modelId;
    }
    throw SDKException.sttNotAvailable(
      'No STT model loaded through commons lifecycle. Call loadSTTModel() first.',
    );
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

  STTAudioEncoding _encodingForOptions(STTOptions options) {
    switch (options.audioFormat) {
      case model_pb.AudioFormat.AUDIO_FORMAT_PCM:
      case model_pb.AudioFormat.AUDIO_FORMAT_PCM_S16LE:
        return STTAudioEncoding.STT_AUDIO_ENCODING_PCM_S16_LE;
      case model_pb.AudioFormat.AUDIO_FORMAT_UNSPECIFIED:
      case model_pb.AudioFormat.AUDIO_FORMAT_WAV:
      case model_pb.AudioFormat.AUDIO_FORMAT_MP3:
      case model_pb.AudioFormat.AUDIO_FORMAT_OPUS:
      case model_pb.AudioFormat.AUDIO_FORMAT_AAC:
      case model_pb.AudioFormat.AUDIO_FORMAT_FLAC:
      case model_pb.AudioFormat.AUDIO_FORMAT_M4A:
      case model_pb.AudioFormat.AUDIO_FORMAT_OGG:
        return STTAudioEncoding.STT_AUDIO_ENCODING_CONTAINER;
      default:
        return STTAudioEncoding.STT_AUDIO_ENCODING_CONTAINER;
    }
  }

  int _bitsPerSample(STTAudioEncoding encoding) {
    switch (encoding) {
      case STTAudioEncoding.STT_AUDIO_ENCODING_PCM_F32_LE:
        return 32;
      case STTAudioEncoding.STT_AUDIO_ENCODING_PCM_S16_LE:
        return 16;
      case STTAudioEncoding.STT_AUDIO_ENCODING_UNSPECIFIED:
      case STTAudioEncoding.STT_AUDIO_ENCODING_CONTAINER:
        return 0;
      default:
        return 0;
    }
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_STT,
      );

  static const _sttCategory =
      model_pb.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
}
