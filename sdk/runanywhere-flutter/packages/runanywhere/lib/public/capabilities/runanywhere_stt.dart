// SPDX-License-Identifier: Apache-2.0
//
// STT capability backed by commons model lifecycle and lifecycle-owned
// generated-proto transcription.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/convenience/ra_convenience.dart'
    show STTLanguageWireString;
import 'package:runanywhere/generated/errors.pbenum.dart' show ErrorCode;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// STT (speech-to-text) capability surface.
///
/// Access via `RunAnywhere.stt`. Load/current/unload state is owned
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
    await DartBridge.ensureServicesReady();

    final logger = SDKLogger('RunAnywhere.LoadSTTModel');
    logger.info('Loading STT model: $modelId');

    // C++ commons auto-emits STT model load started/completed/failed events
    // via `stt_component.cpp`; Dart does not re-emit duplicates.
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

      logger.info('STT model loaded: $modelId');
    } catch (e) {
      logger.error('Failed to load STT model: $e');
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

    // C++ commons auto-emits STT model unload started/completed events.
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
  }

  /// Transcribe audio data to a proto [STTOutput].
  Future<STTOutput> transcribe(
    Uint8List audio, [
    STTOptions? options,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();
    return _transcribeAudioData(
      audio,
      options ?? STTOptions(),
    );
  }

  /// Canonical chunk-feed stream-in / stream-out transcription.
  ///
  /// Consumes a `Stream<Uint8List>` of PCM audio chunks and yields
  /// `STTPartialResult` events; the native session owns endpointing and
  /// segmentation. Each partial carries an incremental transcript and an
  /// `isFinal` flag; closing the input stream flushes the final result.
  /// Bridge errors surface as a terminal partial with
  /// `text = "STT stream failed: ..."` and `isFinal = true`.
  ///
  /// Mirrors Swift `RunAnywhere.transcribeStream(audio: AsyncStream<Data>)`
  /// (RunAnywhere+STT.swift:50).
  Stream<STTPartialResult> transcribeStream(
    Stream<Uint8List> audio, {
    STTOptions? options,
  }) {
    // Not-ready contract mirrors Swift (RunAnywhere+STT.swift:56-69): an
    // uninitialized SDK, failed Phase-2 readiness, or missing lifecycle model
    // finishes the stream SILENTLY instead of throwing.
    if (!DartBridge.isInitialized) {
      return const Stream<STTPartialResult>.empty();
    }

    late final StreamController<STTPartialResult> controller;
    controller = StreamController<STTPartialResult>(
      onListen: () async {
        var sawFinal = false;
        try {
          try {
            await DartBridge.ensureServicesReady();
          } catch (_) {
            return; // Silent finish (Swift parity).
          }
          // Streaming sessions are handle-bound: resolve the lifecycle
          // current model and load it onto the bridge component handle
          // (mirrors Swift `prepareStreamingHandle`).
          final current = await RunAnywhereModelLifecycle.shared.current(
            model_pb.CurrentModelRequest(category: _sttCategory),
          );
          if (!current.found) {
            return; // Silent finish (Swift parity).
          }
          final modelId =
              current.modelId.isNotEmpty ? current.modelId : current.model.id;
          final modelPath = current.resolvedPath.isNotEmpty
              ? current.resolvedPath
              : current.model.localPath;
          if (modelId.isEmpty || modelPath.isEmpty) {
            throw SDKException.make(
              code: ErrorCode.ERROR_CODE_NOT_INITIALIZED,
              message: 'Loaded STT model is missing a resolved path',
            );
          }
          DartBridgeSTT.shared.loadModelForStreaming(
            path: modelPath,
            id: modelId,
            name: current.model.name.isNotEmpty ? current.model.name : modelId,
          );

          final partials = DartBridgeSTT.shared.transcribeSessionStream(
            audio,
            _effectiveOptions(options ?? STTOptions()),
          );
          await for (final partial in partials) {
            if (controller.isClosed) break;
            if (partial.isFinal) sawFinal = true;
            controller.add(partial);
          }
          // Swift parity: synthesize a terminal final when the native
          // session closed without one.
          if (!sawFinal && !controller.isClosed) {
            controller.add(STTPartialResult(isFinal: true));
          }
        } catch (e) {
          // Bridge errors surface as a terminal failure partial (Swift
          // RunAnywhere+STT.swift:92-98) — no stream error.
          if (!controller.isClosed) {
            controller.add(STTPartialResult(
              text: 'STT stream failed: $e',
              isFinal: true,
            ));
          }
        } finally {
          unawaited(controller.close());
        }
      },
    );
    return controller.stream;
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
      metadata: <String, String>{'model_id': modelId}.entries,
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
    // Mirrors Swift transcribe() (RunAnywhere+STT.swift:29-30):
    // `.notInitialized` / "STT model not loaded" / component category.
    throw SDKException.make(
      code: ErrorCode.ERROR_CODE_NOT_INITIALIZED,
      message: 'STT model not loaded',
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
      final code = opts.language.wireString;
      opts.languageCode = code.isEmpty ? 'en' : code;
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
