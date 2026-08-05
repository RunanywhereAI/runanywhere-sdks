import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/voice_component_view_model_base.dart';

/// TTSMetadata (matching iOS TTSMetadata / RATTSSpeakResult surface).
class TTSMetadata {
  final double durationMs;
  final int audioSize;
  final int sampleRate;

  const TTSMetadata({
    required this.durationMs,
    required this.audioSize,
    required this.sampleRate,
  });
}

/// ViewModel for the Text-to-Speech view (mirrors iOS `TTSViewModel.swift`).
///
/// Uses the simplified `RunAnywhere.speak()` API — the SDK handles all audio
/// synthesis and playback internally. The view only renders state.
class TTSViewModel extends VoiceComponentViewModelBase {
  TTSViewModel();

  // SDK-owned playback streams (RunAnywhere.speak plays internally).
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<double>? _progressSubscription;

  // --- Component identity -----------------------------------------------------

  @override
  ModelCategory get modelCategory =>
      ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;

  // --- UI state ----------------------------------------------------------------

  bool isGenerating = false;
  bool isPlaying = false;
  double currentTime = 0.0;
  double duration = 0.0;
  double playbackProgress = 0.0;

  /// Speech rate multiplier (0.5x – 2.0x).
  double _speechRate = 1.0;
  double get speechRate => _speechRate;
  set speechRate(double value) {
    _speechRate = value;
    notify();
  }

  /// While removed from the UI, the backend still supports pitch (iOS parity).
  double pitch = 1.0;

  /// Whether the loaded voice is the platform system TTS.
  bool isSystemTTS = false;

  /// Metadata of the last generated audio, or null.
  TTSMetadata? metadata;

  // --- Initialization -------------------------------------------------------------

  /// Initialize the TTS view model — idempotent.
  Future<void> initialize() async {
    if (!beginInitialization()) return;

    debugPrint('Initializing TTS view model');
    _subscribeToPlayback();
    subscribeToSDKEvents();
    await checkInitialModelState();
  }

  void _subscribeToPlayback() {
    // Subscribe to the SDK's speak() playback state.
    _playingSubscription =
        sdk.RunAnywhere.tts.playbackState.listen((playing) {
      isPlaying = playing;
      if (playing) isGenerating = false;
      notify();
    });

    _progressSubscription =
        sdk.RunAnywhere.tts.playbackProgress.listen((progress) {
      playbackProgress = progress;
      currentTime = duration * progress;
      notify();
    });
  }

  // --- Model management ------------------------------------------------------------

  /// Load a voice from the unified model selection sheet.
  Future<void> loadModelFromSelection(ModelInfo model) async {
    isGenerating = true;
    notify();
    await loadModel(model);
    isGenerating = false;
    notify();
  }

  @override
  Future<void> performLoad(ModelInfo model) =>
      sdk.RunAnywhere.models.load(model.id);

  @override
  void applyLoadedModel(ModelInfo model) {
    super.applyLoadedModel(model);
    isSystemTTS =
        model.framework == LLMFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS;
    notify();
  }

  // --- Speaking ----------------------------------------------------------------------

  /// Speak the given text aloud. One SDK entry point for every TTS path:
  /// speak() synthesizes AND plays (system voices and on-device models alike).
  Future<void> speak(String text) async {
    if (text.isEmpty) {
      errorMessage = 'Please enter text to speak';
      notify();
      return;
    }

    debugPrint('Speaking: ${text.length} chars');
    isGenerating = true;
    errorMessage = null;
    metadata = null;
    notify();

    try {
      if (!hasModelSelected) {
        throw StateError(
            'TTS component not loaded. Please load a TTS voice first.');
      }

      final options = sdk.TtsOptions(speed: _speechRate, pitch: pitch);
      // `speak()` returns a playback `SpeechHandle`, not audio bytes, so the
      // metadata card comes from a separate `synthesize()` call — the same
      // request commons would otherwise run once inside `speak()`.
      final audio = await sdk.RunAnywhere.tts.synthesize(text, options: options);
      duration = audio.durationMs / 1000.0;
      metadata = TTSMetadata(
        durationMs: audio.durationMs.toDouble(),
        audioSize: audio.data.length,
        sampleRate: audio.sampleRate,
      );
      debugPrint('Synthesized: ${audio.sampleRate} Hz, ${audio.durationMs}ms');

      final handle = sdk.RunAnywhere.tts.speak(text, options: options);
      await handle.waitForPlayout();
      final speakError = handle.error;
      if (speakError != null) throw speakError;
    } catch (e) {
      debugPrint('Speech generation failed: $e');
      errorMessage = 'Speech generation failed: $e';
    }

    isGenerating = false;
    notify();
  }

  /// Stop current speech playback.
  Future<void> stopSpeaking() async {
    debugPrint('Stopping speech');
    await sdk.RunAnywhere.tts.stop();
  }

  // --- Cleanup ---------------------------------------------------------------------------

  @override
  void dispose() {
    unawaited(_playingSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    super.dispose();
  }
}
