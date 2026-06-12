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
  StreamSubscription<sdk.VADResult>? _vadSubscription;
  StreamSubscription<double>? _levelSubscription;

  // --- Component identity -----------------------------------------------------

  @override
  sdk.SDKComponent get component => sdk.SDKComponent.SDK_COMPONENT_VAD;

  @override
  sdk.EventCategory get eventCategory => sdk.EventCategory.EVENT_CATEGORY_VAD;

  @override
  ModelCategory get modelCategory =>
      ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;

  // --- UI state ----------------------------------------------------------------

  bool isProcessing = false;
  bool isListening = false;
  bool isSpeech = false;
  double confidence = 0;
  double energy = 0;
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
      sdk.RunAnywhere.vad.loadModel(model.id);

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
    if (!sdk.RunAnywhere.vad.isModelLoaded) {
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

    // Consume the SDK's streaming VAD session: one VADResult per mic chunk;
    // the SDK owns model framing — no app-side buffer math.
    _vadSubscription = sdk.RunAnywhere.vad.streamVAD(chunks).listen(
      (result) {
        if (result.errorMessage.isNotEmpty) {
          errorMessage = result.errorMessage;
          isListening = false;
          notify();
          unawaited(_capture.cancel());
          return;
        }
        isSpeech = result.isSpeech;
        confidence = result.confidence;
        energy = result.energy;
        frameCount += 1;
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

    await _vadSubscription?.cancel();
    _vadSubscription = null;
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
    unawaited(_vadSubscription?.cancel());
    unawaited(_levelSubscription?.cancel());
    unawaited(_capture.dispose());
    super.dispose();
  }
}
