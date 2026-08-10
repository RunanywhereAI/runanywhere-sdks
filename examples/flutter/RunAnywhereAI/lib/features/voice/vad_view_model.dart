import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/voice_component_view_model_base.dart';

/// ViewModel for the Voice Activity Detection view
/// (mirrors iOS `VADViewModel.swift`).
///
/// Manages microphone capture, VAD model loading, and the SDK `streamVAD`
/// session whose per-chunk results drive the live metrics.
class VADViewModel extends VoiceComponentViewModelBase {
  VADViewModel();

  final sdk.AudioCaptureManager _capture = sdk.AudioCaptureManager();
  StreamSubscription<sdk.VadEvent>? _vadSubscription;
  StreamSubscription<Uint8List>? _vadChunkSubscription;
  sdk.VadStream? _vadStream;
  StreamSubscription<double>? _levelSubscription;

  // --- Component identity -----------------------------------------------------

  @override
  ModelCategory get modelCategory =>
      ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;

  // --- UI state ----------------------------------------------------------------

  bool isProcessing = false;
  bool isListening = false;
  bool isSpeech = false;
  double probability = 0;
  int frameCount = 0;
  double audioLevel = 0;

  // --- Initialization -------------------------------------------------------------

  /// Initialize the ViewModel — idempotent. Microphone permission is handled
  /// by the recorder/SDK when capture starts.
  Future<void> initialize() async {
    if (!beginInitialization()) return;

    debugPrint('Initializing VAD view model');
    subscribeToSDKEvents();
    await checkInitialModelState();
  }

  /// Load model from the model selection sheet.
  Future<void> loadModelFromSelection(ModelInfo model) async {
    isProcessing = true;
    notify();
    await loadModel(model);
    isProcessing = false;
    notify();
  }

  @override
  Future<void> performLoad(ModelInfo model) =>
      sdk.RunAnywhere.models.load(model.id);

  /// VAD resolves the display name from the model catalog when available
  /// (mirrors iOS).
  @override
  void applyLoadedModel(ModelInfo model) {
    applyLoadedModelFromCatalog(model);
  }

  // --- Listening control ------------------------------------------------------------

  /// Toggle listening state (start/stop).
  Future<void> toggleListening() async {
    if (isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    debugPrint('Starting VAD listening');
    if (!hasModelSelected) {
      errorMessage = 'Select a VAD model first';
      notify();
      return;
    }

    final chunks = await _capture.startRecording(
      sampleRate: 16000,
      numChannels: 1,
    );
    if (chunks == null) {
      errorMessage = 'Microphone capture failed';
      notify();
      return;
    }

    await _levelSubscription?.cancel();
    _levelSubscription = _capture.audioLevelStream?.listen((level) {
      audioLevel = level;
      notify();
    });

    // Open the VAD session once with the capture format, then push each mic
    // chunk as a frame. The SDK owns model framing, so there is still no
    // app-side buffer math; the format is just established up front now
    // instead of being re-derived from every chunk.
    final stream = sdk.RunAnywhere.vad.openStream(
      const sdk.AudioFormatSpec(
        encoding: sdk.AudioEncoding.pcm16,
        sampleRate: 16000,
      ),
    );
    _vadStream = stream;
    _vadChunkSubscription = chunks.listen(
      (bytes) => stream.pushFrame(
        sdk.AudioFrame(samples: bytes, sampleCount: bytes.length),
      ),
      onDone: stream.finish,
    );

    _vadSubscription = stream.events.listen(
      (event) {
        switch (event) {
          case sdk.VadActivity(:final isSpeech, :final probability):
            this.isSpeech = isSpeech;
            this.probability = probability;
            frameCount += 1;
          case sdk.VadFailed(:final error):
            errorMessage = 'VAD failed: $error';
            isListening = false;
          case sdk.VadSpeechStarted():
          case sdk.VadSpeechEnded():
          case sdk.VadCompleted():
            break;
        }
        notify();
      },
      onError: (Object e) {
        errorMessage = 'VAD failed: $e';
        isListening = false;
        notify();
      },
      onDone: () {
        isListening = false;
        notify();
      },
    );

    isListening = true;
    errorMessage = null;
    frameCount = 0;
    notify();
  }

  Future<void> stopListening() async {
    debugPrint('Stopping VAD listening');

    await _vadChunkSubscription?.cancel();
    _vadChunkSubscription = null;
    await _vadSubscription?.cancel();
    _vadSubscription = null;
    final stream = _vadStream;
    _vadStream = null;
    await stream?.close();
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    await _capture.stopRecording();

    isListening = false;
    isSpeech = false;
    audioLevel = 0;
    notify();
  }

  // --- Cleanup ---------------------------------------------------------------------------

  @override
  void dispose() {
    unawaited(_vadChunkSubscription?.cancel());
    unawaited(_vadStream?.close());
    unawaited(_vadSubscription?.cancel());
    unawaited(_levelSubscription?.cancel());
    unawaited(_capture.dispose());
    super.dispose();
  }
}
