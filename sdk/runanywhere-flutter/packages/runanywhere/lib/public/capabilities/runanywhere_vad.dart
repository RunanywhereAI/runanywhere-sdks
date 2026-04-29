// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_vad.dart — v4 VAD (voice activity detection) capability.
//
// Mirrors Swift's `RunAnywhere+VAD.swift` extension. Public surface:
//   initializeVAD([config])
//   isReady
//   detectSpeech(samples)
//   start() / stop() / cleanup()
//   loadModel(id) / unloadModel() / isModelLoaded / currentModelId
//   setSpeechActivityCallback / setAudioBufferCallback
//   activityStream — Dart-idiomatic replacement for the Swift callbacks.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/features/vad/vad_configuration.dart' show VADComponentConfig;
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/vad_options.pb.dart'
    show VADOptions, VADResult, VADStatistics;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart' as bridge
    show VADActivityEvent, VADSpeechStartedEvent, VADSpeechEndedEvent;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

/// Speech-activity event lifecycle. Mirrors Swift's
/// `SpeechActivityEvent` enum (`.started` / `.ended`).
enum SpeechActivityEvent {
  started,
  ended,
}


/// Voice Activity Detection (VAD) capability surface.
///
/// Access via `RunAnywhereSDK.instance.vad`. Mirrors Swift's
/// `RunAnywhere+VAD.swift` extension functions.
class RunAnywhereVAD {
  RunAnywhereVAD._() {
    // Bridge the bridge-level [VADActivityEvent] stream to the public
    // [SpeechActivityEvent] stream + invoke any registered callbacks.
    _bridgeSubscription = DartBridge.vad.activityStream.listen((event) {
      if (event is bridge.VADSpeechStartedEvent) {
        _speechActivityCallback?.call(SpeechActivityEvent.started);
        _activityController.add(SpeechActivityEvent.started);
      } else if (event is bridge.VADSpeechEndedEvent) {
        _speechActivityCallback?.call(SpeechActivityEvent.ended);
        _activityController.add(SpeechActivityEvent.ended);
      }
    });
  }

  static final RunAnywhereVAD _instance = RunAnywhereVAD._();
  static RunAnywhereVAD get shared => _instance;

  final _logger = SDKLogger('RunAnywhere.VAD');

  // Public broadcast stream for speech activity changes.
  final _activityController = StreamController<SpeechActivityEvent>.broadcast();

  // Stored audio-buffer + speech-activity + statistics callbacks.
  void Function(SpeechActivityEvent event)? _speechActivityCallback;
  void Function(Float32List samples)? _audioBufferCallback;
  void Function(VADStatistics stats)? _statisticsCallback;

  // Running statistics counters (updated on every detectSpeech call).
  int _speechEventCount = 0;
  double _totalAudioMs = 0.0;
  int _speechFrames = 0;
  int _totalFrames = 0;

  late final StreamSubscription<bridge.VADActivityEvent> _bridgeSubscription;

  // VAD model state — independent from the energy-based VAD process.
  String? _loadedModelId;
  ModelInfo? _loadedModel;

  // ---------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------

  /// Initialize VAD with default configuration. Mirrors Swift's
  /// `initializeVAD()`.
  Future<void> initializeVAD([VADComponentConfig? config]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (config != null) {
      config.validate();
      // Push energy-threshold configuration through the bridge.
      DartBridge.vad.energyThreshold = config.energyThreshold;
    }
    await DartBridge.vad.initialize();
    _logger.info('VAD initialized');
  }

  /// True once `initializeVAD` has succeeded and the C++ component is
  /// live. Mirrors Swift's `isVADReady`.
  bool get isReady => DartBridge.vad.isInitialized;

  // ---------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------

  /// Detect whether speech is present in [samples]. Mirrors Swift's
  /// `detectSpeech(in: [Float])` overload.
  Future<bool> detectSpeech(Float32List samples) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = DartBridge.vad.process(samples);
    // Estimate audio duration from sample count at 16kHz.
    _totalAudioMs += samples.length / 16.0;
    // Forward to audio-buffer callback for parity with Swift.
    _audioBufferCallback?.call(samples);
    _emitStatistics(result.isSpeech);
    return result.isSpeech;
  }

  /// Detect voice activity, returning a proto [VADResult]. Canonical
  /// cross-SDK signature accepts raw PCM16 bytes (Uint8List) and
  /// converts to Float32 samples for the energy-based detector.
  /// Mirrors Swift's `detectVoiceActivity(_:options:)`.
  Future<VADResult> detectVoiceActivity(
    Uint8List audio, [
    VADOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final samples = _pcm16ToFloat32(audio);
    final result = DartBridge.vad.process(samples);
    _totalAudioMs += audio.length / 32.0; // PCM-16 at 16kHz: 2 bytes * 16000 = 32000 bytes/s
    _audioBufferCallback?.call(samples);
    _emitStatistics(result.isSpeech);
    return VADResult(
      isSpeech: result.isSpeech,
      confidence: result.speechProbability,
      energy: result.energy,
      durationMs: 0,
    );
  }

  /// Detect voice activity from Float32 PCM samples (internal / advanced).
  Future<VADResult> detectVoiceActivityFloat(
    Float32List audio, [
    VADOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = DartBridge.vad.process(audio);
    _audioBufferCallback?.call(audio);
    return VADResult(
      isSpeech: result.isSpeech,
      confidence: result.speechProbability,
      energy: result.energy,
      durationMs: 0,
    );
  }

  static Float32List _pcm16ToFloat32(Uint8List pcm16) {
    final samples = Float32List(pcm16.length ~/ 2);
    final byteData = ByteData.sublistView(pcm16);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  // ---------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------

  /// Start VAD processing. Mirrors Swift's `startVAD()`.
  Future<void> startVAD() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridge.vad.start();
  }

  /// Stop VAD processing. Mirrors Swift's `stopVAD()`.
  Future<void> stopVAD() async {
    DartBridge.vad.stop();
  }

  /// Reset VAD state.
  void reset() {
    DartBridge.vad.reset();
  }

  /// Tear down all VAD state (frees C++ resources). Mirrors Swift's
  /// `cleanupVAD()`.
  Future<void> cleanupVAD() async {
    DartBridge.vad.cleanup();
    _speechActivityCallback = null;
    _audioBufferCallback = null;
  }

  // ---------------------------------------------------------------------
  // Callbacks (Dart-idiomatic + Swift parity)
  // ---------------------------------------------------------------------

  /// Stream of speech activity transitions (started / ended). Each
  /// emission is also forwarded to the registered
  /// `setSpeechActivityCallback` listener if any.
  Stream<SpeechActivityEvent> get activityStream =>
      _activityController.stream;

  /// Register a single callback for speech activity events. Mirrors
  /// Swift's `setVADSpeechActivityCallback(_:)`.
  void setSpeechActivityCallback(
    void Function(SpeechActivityEvent event)? callback,
  ) {
    _speechActivityCallback = callback;
  }

  /// Register a single callback for raw audio buffers. Mirrors Swift's
  /// `setVADAudioBufferCallback(_:)`. The callback fires once per
  /// `detectSpeech` invocation.
  void setAudioBufferCallback(
    void Function(Float32List samples)? callback,
  ) {
    _audioBufferCallback = callback;
  }

  /// Register a single callback for VAD statistics (canonical §6).
  /// The callback fires on every [detectSpeech] / [detectVoiceActivity] call
  /// with an updated [VADStatistics] snapshot.
  void setStatisticsCallback(
    void Function(VADStatistics stats)? callback,
  ) {
    _statisticsCallback = callback;
  }

  /// Stream VAD results from a continuous audio byte stream (canonical §6).
  ///
  /// Each [Uint8List] chunk from [audio] is processed as PCM-16 audio and
  /// mapped to a [VADResult]. The returned stream completes when [audio]
  /// completes.
  Stream<VADResult> streamVAD(Stream<Uint8List> audio) async* {
    await for (final chunk in audio) {
      yield await detectVoiceActivity(chunk);
    }
  }

  // Internal helper to emit statistics after each detection call.
  void _emitStatistics(bool isSpeech) {
    _totalFrames++;
    if (isSpeech) {
      _speechFrames++;
      _speechEventCount++;
    }
    // Map to proto VADStatistics fields: recentAvg as speech fraction,
    // recentMax as total frames (normalized), ambientLevel as totalAudioMs.
    final speechFraction =
        _totalFrames > 0 ? _speechFrames / _totalFrames : 0.0;
    _statisticsCallback?.call(VADStatistics(
      ambientLevel: _totalAudioMs,
      recentAvg: speechFraction,
      recentMax: _speechEventCount.toDouble(),
    ));
  }

  // ---------------------------------------------------------------------
  // VAD Model management (separate from process lifecycle)
  // ---------------------------------------------------------------------

  /// True when a VAD model is loaded for the C++ component.
  bool get isModelLoaded => _loadedModelId != null;

  /// Currently-loaded VAD model id, or null.
  String? get currentModelId => _loadedModelId;

  /// Currently-loaded VAD model info, or null.
  ModelInfo? get currentModel => _loadedModel;

  /// Load a VAD model by id. Mirrors Swift's `loadVADModel(_:)`.
  ///
  /// Resolves the model from the registry, unloads any previously-loaded
  /// VAD model, then re-initializes the underlying VAD bridge.
  Future<void> loadModel(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    _logger.info('Loading VAD model: $modelId');
    final models = await RunAnywhereModels.shared.available();
    final model = models.where((m) => m.id == modelId).firstOrNull;

    if (model == null) {
      throw SDKException.modelNotFound('VAD model not found: $modelId');
    }
    if (model.localPath == null) {
      throw SDKException.modelNotDownloaded(
        'VAD model is not downloaded. Call downloadModel() first.',
      );
    }

    // Re-initialize the VAD component for the new model. The C++ side
    // does not currently expose a model-aware load — initialization is
    // sufficient for the energy-based path while still recording the
    // active model id for parity with Swift.
    await DartBridge.vad.initialize();

    _loadedModelId = modelId;
    _loadedModel = model;
    _logger.info('VAD model loaded: ${model.name}');
  }

  /// Unload the currently-loaded VAD model. Mirrors Swift's
  /// `unloadVADModel()`.
  Future<void> unloadModel() async {
    if (_loadedModelId == null) return;
    DartBridge.vad.cleanup();
    _loadedModelId = null;
    _loadedModel = null;
  }

  // ---------------------------------------------------------------------
  // Disposal (used by tests / SDK reset)
  // ---------------------------------------------------------------------

  /// Internal: tear down all controllers/subscriptions. Used by
  /// `RunAnywhereSDK.reset()`.
  Future<void> dispose() async {
    await _bridgeSubscription.cancel();
    await _activityController.close();
    DartBridge.vad.dispose();
  }
}
